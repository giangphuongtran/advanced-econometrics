import os
import glob
import gc
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

from country_constants import COUNTRY_CENTROIDS, PANEL_COUNTRIES

# ==============================================================================
# CONFIGURATION & CONSTANTS
# ==============================================================================
ROOT = Path(__file__).resolve().parent.parent
INPUT_DIR = ROOT / "era5_eu_data"
EXTRACTION_STAGE = ROOT / "era5_extracted_staging"
WEATHER_STAGE_DIR = ROOT / "era5_processed_flat"
ENERGY_DIR = ROOT / "energy_country_level"
DATA_DIR = ROOT / "data"
FINAL_OUTPUT = DATA_DIR / "final_integrated_u_curve_dataset.parquet"
GRID_WEIGHTS_PATH = DATA_DIR / "gpw_grid_weights.parquet"
POP_ANNUAL_PATH = DATA_DIR / "eurostat_population_annual.csv"

WEATHER_COLS = [
    "temperature_c",
    "dewpoint_c",
    "wind_speed_ms",
    "solar_radiation_wm2",
    "precipitation_mm",
    "tcc",
]


def load_population_scaling() -> pd.DataFrame:
    """Annual population totals for year-specific weight rescaling."""
    if not POP_ANNUAL_PATH.exists():
        raise FileNotFoundError(
            f"Run 01_download_population.py first. Missing: {POP_ANNUAL_PATH}"
        )
    pop = pd.read_csv(POP_ANNUAL_PATH)
    return pop[["country_code", "year", "population"]]


def load_grid_weights() -> pd.DataFrame:
    """Grid cells and base population weights per country."""
    if not GRID_WEIGHTS_PATH.exists():
        raise FileNotFoundError(
            f"Run 01_download_population.py first. Missing: {GRID_WEIGHTS_PATH}"
        )
    return pd.read_parquet(GRID_WEIGHTS_PATH)


def year_scale_factor(pop_annual: pd.DataFrame, country: str, year: int) -> float:
    base = pop_annual.loc[
        (pop_annual["country_code"] == country) & (pop_annual["year"] == 2020),
        "population",
    ]
    current = pop_annual.loc[
        (pop_annual["country_code"] == country) & (pop_annual["year"] == year),
        "population",
    ]
    if base.empty or current.empty or float(base.iloc[0]) <= 0:
        return 1.0
    return float(current.iloc[0]) / float(base.iloc[0])


# ==============================================================================
# STEP 1: UNPACK AND FLATTEN ERA5 NETCDF STREAMS
# ==============================================================================
def extract_and_flatten_era5():
    """Unpacks zipped NetCDF climate data and flattens them into tabular Parquet stages."""
    os.makedirs(EXTRACTION_STAGE, exist_ok=True)
    os.makedirs(WEATHER_STAGE_DIR, exist_ok=True)

    nc_zip_files = sorted(glob.glob(str(INPUT_DIR / "*.nc")))
    if not nc_zip_files:
        raise FileNotFoundError(f"No files found in '{INPUT_DIR}'. Please check your paths.")

    print(f"Found {len(nc_zip_files)} monthly climate packages to unpack.\n")

    for zip_filepath in nc_zip_files:
        base_name = os.path.splitext(os.path.basename(zip_filepath))[0]
        print(f"=== Processing Raw Archive: {base_name} ===")

        current_extract_dir = EXTRACTION_STAGE / base_name
        current_extract_dir.mkdir(parents=True, exist_ok=True)

        try:
            with zipfile.ZipFile(zip_filepath, "r") as zip_ref:
                zip_ref.extractall(current_extract_dir)
            extracted_files = os.listdir(current_extract_dir)
        except zipfile.BadZipFile:
            print(f"⚠️ {zip_filepath} is a standard NetCDF grid file. Processing directly...")
            extracted_files = [os.path.basename(zip_filepath)]
            current_extract_dir = INPUT_DIR

        df_instant, df_accum = pd.DataFrame(), pd.DataFrame()

        for file_name in extracted_files:
            full_file_path = current_extract_dir / file_name

            with xr.open_dataset(full_file_path) as ds:
                df_temp = ds.to_dataframe().reset_index()
                df_temp.drop(columns=["expver", "number"], errors="ignore", inplace=True)

                time_col = "valid_time" if "valid_time" in df_temp.columns else "time"
                if time_col in df_temp.columns:
                    df_temp.rename(columns={time_col: "timestamp"}, inplace=True)

                if "instant" in file_name:
                    df_instant = df_temp
                elif "accum" in file_name:
                    df_accum = df_temp

        if not df_instant.empty:
            df_instant.to_parquet(WEATHER_STAGE_DIR / f"{base_name}_instant.parquet", index=False)
        if not df_accum.empty:
            df_accum.to_parquet(WEATHER_STAGE_DIR / f"{base_name}_accum.parquet", index=False)

        print(f"   -> Successfully extracted streams for {base_name}")


# ==============================================================================
# STEP 2: POPULATION-WEIGHTED WEATHER AGGREGATION
# ==============================================================================
def population_weighted_weather(df_month: pd.DataFrame, grid_weights: pd.DataFrame, pop_annual: pd.DataFrame) -> pd.DataFrame:
    """
    For each country and timestamp, compute population-weighted average of weather
    across ERA5 grid cells in the country bounding box.
    """
    df_month = df_month.copy()
    df_month["year"] = pd.to_datetime(df_month["timestamp"]).dt.year

    country_frames = []
    for country in PANEL_COUNTRIES:
        if country not in COUNTRY_CENTROIDS:
            continue
        gw = grid_weights.loc[grid_weights["country_code"] == country].copy()
        if gw.empty:
            continue

        cells = df_month.merge(
            gw[["latitude", "longitude", "pop_base"]],
            on=["latitude", "longitude"],
            how="inner",
        )
        if cells.empty:
            continue

        # Year-specific rescaling of base GPW weights
        scale = cells["year"].map(lambda y: year_scale_factor(pop_annual, country, int(y)))
        cells["w"] = cells["pop_base"] * scale
        cells["w"] = cells.groupby(["timestamp"])["w"].transform(lambda s: s / s.sum())

        agg = {"w": "sum"}
        for col in WEATHER_COLS:
            cells[f"_wx_{col}"] = cells[col] * cells["w"]
            agg[f"_wx_{col}"] = "sum"

        grouped = cells.groupby("timestamp", as_index=False).agg(agg)
        for col in WEATHER_COLS:
            grouped[col] = grouped[f"_wx_{col}"]
            grouped.drop(columns=[f"_wx_{col}"], inplace=True)

        grouped["country_code"] = country
        country_frames.append(grouped[["timestamp", "country_code"] + WEATHER_COLS])

    if not country_frames:
        return pd.DataFrame()
    return pd.concat(country_frames, ignore_index=True)


def process_population_weighted_weather():
    """Merge ERA5 streams, convert units, and aggregate with GPW population weights."""
    print("\n--- Population-Weighted Weather Aggregation ---")
    grid_weights = load_grid_weights()
    pop_annual = load_population_scaling()

    instant_files = sorted(glob.glob(str(WEATHER_STAGE_DIR / "*_instant.parquet")))
    weather_country_records = []

    for inst_fp in instant_files:
        base_name = os.path.basename(inst_fp).replace("_instant.parquet", "")
        accum_fp = WEATHER_STAGE_DIR / f"{base_name}_accum.parquet"

        if not accum_fp.exists():
            print(f"⚠️ Missing accumulation match for {base_name}, skipping.")
            continue

        print(f"   Processing: {base_name}")
        df_inst = pd.read_parquet(inst_fp)
        df_acc = pd.read_parquet(accum_fp)

        df_month = pd.merge(df_inst, df_acc, on=["timestamp", "latitude", "longitude"], how="inner")
        del df_inst, df_acc

        df_month["temperature_c"] = df_month["t2m"] - 273.15
        df_month["dewpoint_c"] = df_month["d2m"] - 273.15
        df_month["wind_speed_ms"] = np.sqrt(df_month["u10"] ** 2 + df_month["v10"] ** 2)
        df_month["solar_radiation_wm2"] = df_month["ssrd"] / 3600.0
        df_month["precipitation_mm"] = df_month["tp"] * 1000.0
        df_month.drop(columns=["t2m", "d2m", "u10", "v10", "ssrd", "tp"], inplace=True)

        weighted = population_weighted_weather(df_month, grid_weights, pop_annual)
        weather_country_records.append(weighted)

        del df_month, weighted
        gc.collect()

    weather_df = pd.concat(weather_country_records, ignore_index=True)
    weather_df["timestamp"] = pd.to_datetime(weather_df["timestamp"]).dt.tz_localize("UTC")
    return weather_df


# ==============================================================================
# STEP 3: INTEGRATE WITH LOCAL GRID DEMAND LOADS
# ==============================================================================
def integrate_with_energy_load(weather_compiled_df: pd.DataFrame):
    """Merge population-weighted weather with hourly ENTSO-E load."""
    print("\n--- Coupling Weather Metrics with Grid Load Data ---")
    energy_files = sorted(glob.glob(str(ENERGY_DIR / "hourly_load_country_*.parquet")))

    if not energy_files:
        raise FileNotFoundError(f"No hourly load parquets found in '{ENERGY_DIR}'.")

    energy_df = pd.concat([pd.read_parquet(fp) for fp in energy_files], ignore_index=True)
    energy_df["timestamp"] = pd.to_datetime(energy_df["timestamp"])

    if energy_df["timestamp"].dt.tz is None:
        energy_df["timestamp"] = energy_df["timestamp"].dt.tz_localize("UTC")
    else:
        energy_df["timestamp"] = energy_df["timestamp"].dt.tz_convert("UTC")

    final_df = pd.merge(energy_df, weather_compiled_df, on=["timestamp", "country_code"], how="inner")

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    final_df.to_parquet(FINAL_OUTPUT, index=False, compression="snappy")
    print(f"\nIntegrated dataset saved -> {FINAL_OUTPUT}")
    print(f"Total: {final_df.shape[0]:,} rows x {final_df.shape[1]} columns.")
    print(final_df.head())


# ==============================================================================
# MAIN PIPELINE RUNNER
# ==============================================================================
if __name__ == "__main__":
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    extract_and_flatten_era5()
    weather_compiled_df = process_population_weighted_weather()
    integrate_with_energy_load(weather_compiled_df)
