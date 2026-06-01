import os
import time
import logging
from pathlib import Path

import pandas as pd
import numpy as np
from entsoe import EntsoePandasClient
from tqdm import tqdm

# Set ENTSOE_API_KEY in your environment before running this script.
API_KEY = os.environ.get("ENTSOE_API_KEY")
if not API_KEY:
    raise ValueError(
        "ENTSOE_API_KEY environment variable is not set. "
        "Export your ENTSO-E API token before downloading load data."
    )
YEARS = [2020, 2021, 2022, 2023, 2024]
OUTPUT_DIR = Path("energy_country_level")
OUTPUT_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# Bidding zone mapping (Country Level)
BIDDING_ZONES = {
    "AT": "AT", "BE": "BE", "BG": "BG", "HR": "HR", "CY": "CY",
    "CZ": "CZ", "DK": "DK", "EE": "EE", "FI": "FI", "FR": "FR",
    "DE_LU": "DE", "GR": "GR", "HU": "HU", "IE": "IE", "IT": "IT",
    "LV": "LV", "LT": "LT", "LU": "LU", "MT": "MT", "NL": "NL",
    "PL": "PL", "PT": "PT", "RO": "RO", "SK": "SK", "SI": "SI",
    "ES": "ES", "SE": "SE", "NO": "NO", "CH": "CH",
}

def normalize_load_response(load_data: pd.DataFrame | pd.Series) -> pd.DataFrame:
    if isinstance(load_data, pd.Series):
        df = load_data.rename("load_mw").reset_index()
        df.columns = ["timestamp", "load_mw"]
        return df

    if isinstance(load_data, pd.DataFrame):
        df = load_data.reset_index().copy()
        timestamp_col = df.columns[0]
        value_cols = [col for col in df.columns if col != timestamp_col]

        # Check common ENTSO-E column names
        if "Actual Load" in value_cols:
            value_col = "Actual Load"
        elif "Total Load" in value_cols:
            value_col = "Total Load"
        else:
            value_col = value_cols[0]

        df = df[[timestamp_col, value_col]].rename(
            columns={timestamp_col: "timestamp", value_col: "load_mw"}
        )
        return df
    raise TypeError(f"Unsupported ENTSO-E response type: {type(load_data).__name__}")

def download_entsoe_load(year: int) -> pd.DataFrame:
    cache_file = OUTPUT_DIR / f"_cache_entsoe_{year}.parquet"
    if cache_file.exists():
        log.info(f"Loading cached ENTSO-E data for {year}")
        return pd.read_parquet(cache_file)

    client = EntsoePandasClient(api_key=API_KEY)
    start = pd.Timestamp(f"{year}-01-01", tz="UTC")
    end   = pd.Timestamp(f"{year+1}-01-01", tz="UTC")

    frames = []
    for zone_code, country_iso in tqdm(BIDDING_ZONES.items(), desc=f"ENTSO-E {year}"):
        try:
            load_data = client.query_load(zone_code, start=start, end=end)
            df = normalize_load_response(load_data)
            df["country_code"] = country_iso
            frames.append(df)
            time.sleep(0.5) # Slight delay to be nice to the API
        except Exception as e:
            log.warning(f"  {zone_code}: {e}")

    if not frames:
        raise RuntimeError(f"No ENTSO-E data retrieved for {year}")

    result = pd.concat(frames, ignore_index=True)

    # Aggregate bidding zones to country totals (e.g., DE_LU -> DE)
    result = (
        result
        .groupby(["timestamp", "country_code"], as_index=False)["load_mw"]
        .sum()
    )
    result.to_parquet(cache_file, index=False)
    return result

def fill_gaps(df: pd.DataFrame) -> pd.DataFrame:
    """Interpolate gaps within each country group."""
    df = df.sort_values(["country_code", "timestamp"])
    df["load_mw"] = (
        df.groupby("country_code")["load_mw"]
        .transform(lambda s: s.interpolate(method="linear", limit=3))
    )
    return df

def quality_check(df: pd.DataFrame, year: int) -> None:
    n_missing = df["load_mw"].isna().sum()
    n_countries = df["country_code"].nunique()
    log.info(f"  Summary: {len(df):,} rows | {n_countries} countries | Missing: {n_missing}")

def main():
    print("\n" + "="*80)
    print("  Country-Level Hourly Load Data Pipeline (NUTS-0)")
    print("="*80 + "\n")

    for year in YEARS:
        out_file = OUTPUT_DIR / f"hourly_load_country_{year}.parquet"
        if out_file.exists():
            log.info(f"Output for {year} already exists, skipping.")
            continue

        log.info(f"Processing year {year}...")

        # 1. Download and aggregate to country level
        load_df = download_entsoe_load(year)

        # 2. Fill short gaps (<= 3 hours)
        load_df = fill_gaps(load_df)

        # 3. Quality check
        quality_check(load_df, year)

        # 4. Save
        load_df.to_parquet(out_file, compression='snappy', index=False)
        log.info(f"  Saved → {out_file}")

    log.info("\nAll done! Output files are in: energy_country_level/")

if __name__ == "__main__":
    main()