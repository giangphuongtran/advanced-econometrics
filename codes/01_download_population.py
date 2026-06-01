#!/usr/bin/env python3
"""
Download annual population (Eurostat demo_pjan compatible) and build GPW grid weights.

Population source (primary attempt):
  Eurostat JSON-stat API for demo_pjan (Population on 1 January).
Fallback:
  World Bank indicator SP.POP.TOTL (closely aligned national totals).

GPW v4 weights (primary):
  Sample population count from a local GeoTIFF placed at:
    ../data/gpw_v4_population_2020.tif
  Download from NASA SEDAC GPW v4 (Population Count, 2020, 15 arc-min):
    https://sedac.ciesin.columbia.edu/data/gpw-v4/gridded-population-counts-with-adjustments-to-1-common-resolution/data

Fallback when GeoTIFF is absent:
  cos(latitude) area weights within each country bounding box on the ERA5 0.25° grid,
  then scaled to Eurostat/World Bank annual totals.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import requests

from country_constants import (
    BBOX_HALF_WIDTH,
    COUNTRY_CENTROIDS,
    ERA5_GRID_STEP,
    ISO2_TO_ISO3,
    PANEL_COUNTRIES,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
GPW_TIF = DATA_DIR / "gpw_v4_population_2020.tif"
POP_OUT = DATA_DIR / "eurostat_population_annual.csv"
WEIGHTS_OUT = DATA_DIR / "gpw_grid_weights.parquet"
YEARS = list(range(2020, 2025))

EUROSTAT_URL = (
    "https://ec.europa.eu/eurostat/api/discover/statistics/1.0/data/demo_pjan"
    "?format=JSON&lang=en&sex=T&age=TOTAL&unit=NR"
)


def fetch_eurostat_population() -> pd.DataFrame | None:
    """Try Eurostat demo_pjan; return long DataFrame or None if unavailable."""
    frames = []
    for cc in PANEL_COUNTRIES:
        for year in YEARS:
            url = f"{EUROSTAT_URL}&geo={cc}&time={year}"
            try:
                resp = requests.get(url, timeout=20)
                if resp.status_code != 200:
                    continue
                payload = resp.json()
                values = payload.get("value", {})
                if not values:
                    continue
                pop = float(next(iter(values.values())))
                frames.append({"country_code": cc, "year": year, "population": int(pop)})
            except (requests.RequestException, json.JSONDecodeError, ValueError, StopIteration):
                continue
    if len(frames) < len(PANEL_COUNTRIES):
        return None
    return pd.DataFrame(frames)


def fetch_worldbank_population() -> pd.DataFrame:
    """World Bank SP.POP.TOTL for 2020–2024 (fallback aligned with Eurostat totals)."""
    iso3_list = ";".join(ISO2_TO_ISO3[cc] for cc in PANEL_COUNTRIES)
    url = (
        "https://api.worldbank.org/v2/country/"
        f"{iso3_list}/indicator/SP.POP.TOTL"
        f"?date=2020:2024&format=json&per_page=500"
    )
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    payload = resp.json()
    if len(payload) < 2 or not payload[1]:
        raise RuntimeError("World Bank population API returned no records.")

    iso3_to_iso2 = {v: k for k, v in ISO2_TO_ISO3.items()}
    rows = []
    for rec in payload[1]:
        iso2 = iso3_to_iso2.get(rec["countryiso3code"])
        if iso2 is None or rec.get("value") is None:
            continue
        rows.append(
            {
                "country_code": iso2,
                "year": int(rec["date"]),
                "population": int(rec["value"]),
            }
        )
    df = pd.DataFrame(rows)
    df = df[df["year"].isin(YEARS)].sort_values(["country_code", "year"])
    if df["country_code"].nunique() < len(PANEL_COUNTRIES):
        missing = set(PANEL_COUNTRIES) - set(df["country_code"])
        raise RuntimeError(f"Missing World Bank population for: {sorted(missing)}")
    return df


def era5_grid_points(country: str) -> pd.DataFrame:
    """All ERA5 0.25° grid nodes inside the country bounding box."""
    lat0, lon0 = COUNTRY_CENTROIDS[country]
    lats = np.arange(
        math.floor((lat0 - BBOX_HALF_WIDTH) / ERA5_GRID_STEP) * ERA5_GRID_STEP,
        math.ceil((lat0 + BBOX_HALF_WIDTH) / ERA5_GRID_STEP) * ERA5_GRID_STEP + 1e-9,
        ERA5_GRID_STEP,
    )
    lons = np.arange(
        math.floor((lon0 - BBOX_HALF_WIDTH) / ERA5_GRID_STEP) * ERA5_GRID_STEP,
        math.ceil((lon0 + BBOX_HALF_WIDTH) / ERA5_GRID_STEP) * ERA5_GRID_STEP + 1e-9,
        ERA5_GRID_STEP,
    )
    grid = pd.DataFrame(
        [(float(lat), float(lon)) for lat in lats for lon in lons],
        columns=["latitude", "longitude"],
    )
    grid["country_code"] = country
    return grid


def sample_gpw_weights(grid: pd.DataFrame) -> pd.Series:
    """Sample GPW population count at grid points from local GeoTIFF."""
    import rasterio
    from rasterio.warp import transform

    with rasterio.open(GPW_TIF) as src:
        xs, ys = transform(
            "EPSG:4326",
            src.crs,
            grid["longitude"].to_numpy(),
            grid["latitude"].to_numpy(),
        )
        samples = list(src.sample(zip(xs, ys)))
        pop = np.array([s[0] if s[0] is not None else 0.0 for s in samples], dtype=float)
        pop = np.clip(pop, 0, None)
    return pd.Series(pop, index=grid.index)


def area_proxy_weights(grid: pd.DataFrame) -> pd.Series:
    """cos(lat) area proxy when GPW raster is unavailable."""
    w = np.cos(np.deg2rad(grid["latitude"].to_numpy()))
    w = np.clip(w, 0.01, None)
    return pd.Series(w, index=grid.index)


def build_grid_weights(pop_annual: pd.DataFrame) -> pd.DataFrame:
    """Base GPW (or proxy) weights per grid cell; annual scaling applied at merge time."""
    records = []
    use_gpw = GPW_TIF.exists()
    if not use_gpw:
        print(
            f"WARNING: {GPW_TIF.name} not found. Using cos(lat) area proxy within bbox.\n"
            "Place the GPW v4 2020 GeoTIFF at that path for full spatial weighting."
        )

    for country in PANEL_COUNTRIES:
        grid = era5_grid_points(country)
        if use_gpw:
            base_w = sample_gpw_weights(grid)
        else:
            base_w = area_proxy_weights(grid)
        total = base_w.sum()
        if total <= 0:
            base_w = pd.Series(1.0, index=grid.index)
            total = base_w.sum()
        grid["pop_base"] = (base_w / total).astype(float)
        records.append(grid[["country_code", "latitude", "longitude", "pop_base"]])

    weights = pd.concat(records, ignore_index=True)
    # Attach 2020 Eurostat/WB total for reference scaling
    pop_2020 = pop_annual.loc[pop_annual["year"] == 2020, ["country_code", "population"]]
    weights = weights.merge(pop_2020, on="country_code", how="left")
    weights.rename(columns={"population": "population_2020"}, inplace=True)
    return weights


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    print("Fetching annual population (Eurostat demo_pjan, then World Bank fallback)...")
    pop = fetch_eurostat_population()
    source = "eurostat_demo_pjan"
    if pop is None:
        print("Eurostat API unavailable; using World Bank SP.POP.TOTL.")
        pop = fetch_worldbank_population()
        source = "worldbank_sp_pop_totl"

    pop["source"] = source
    pop.to_csv(POP_OUT, index=False)
    print(f"Wrote {POP_OUT} ({len(pop)} rows, source={source})")

    print("Building grid weights for population-weighted weather...")
    weights = build_grid_weights(pop)
    weights.to_parquet(WEIGHTS_OUT, index=False)
    print(f"Wrote {WEIGHTS_OUT} ({len(weights)} grid-country rows)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
