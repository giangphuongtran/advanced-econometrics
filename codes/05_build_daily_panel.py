#!/usr/bin/env python3
"""
Aggregate hourly merged load–weather panel to daily frequency.

Rules (documented for Section 3.1 of the paper):
  - load_mw:           arithmetic mean of hourly MW (average power demand)
  - temperature_c, dewpoint_c, wind_speed_ms, solar_radiation_wm2, tcc:
                       arithmetic mean of hourly values
  - precipitation_mm:  sum of hourly mm (ERA5 tp converted to mm per hour in consolidate)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
HOURLY_IN = DATA_DIR / "final_integrated_u_curve_dataset.parquet"
DAILY_OUT = DATA_DIR / "daily_integrated_u_curve_dataset.parquet"

MEAN_COLS = [
    "load_mw",
    "temperature_c",
    "dewpoint_c",
    "wind_speed_ms",
    "solar_radiation_wm2",
    "tcc",
]
SUM_COLS = ["precipitation_mm"]


def aggregate_hourly_to_daily(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df["date"] = df["timestamp"].dt.floor("D")

    agg = {col: "mean" for col in MEAN_COLS if col in df.columns}
    for col in SUM_COLS:
        if col in df.columns:
            agg[col] = "sum"

    missing = [c for c in MEAN_COLS + SUM_COLS if c not in df.columns]
    if missing:
        raise ValueError(f"Hourly input missing expected columns: {missing}")

    daily = (
        df.groupby(["country_code", "date"], as_index=False)
        .agg(agg)
        .rename(columns={"date": "timestamp"})
    )
    daily["timestamp"] = pd.to_datetime(daily["timestamp"], utc=True)
    return daily


def main() -> None:
    if not HOURLY_IN.exists():
        raise FileNotFoundError(f"Hourly parquet not found: {HOURLY_IN}")

    print(f"Reading {HOURLY_IN} ...")
    hourly = pd.read_parquet(HOURLY_IN)
    daily = aggregate_hourly_to_daily(hourly)
    daily.to_parquet(DAILY_OUT, index=False, compression="snappy")
    print(f"Wrote {DAILY_OUT}: {len(daily):,} rows x {daily.shape[1]} columns")
    print(daily.groupby("country_code").size().describe())


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
