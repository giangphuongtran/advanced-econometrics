# Weather and European Electricity Load — Final Project

Author: **Giang Tran**

Replication package for the econometric analysis of temperature--load dynamics across 21 European countries (2020--2024).

## Archive

- **GitHub:** `https://github.com/USERNAME/REPO` (release tag `v1.0`)
- **Zenodo:** [DOI: 10.5281/zenodo.XXXXXXX](https://doi.org/10.5281/zenodo.XXXXXXX) — replace after upload

## Quick start (fast path, ~5 minutes)

No API keys required if you use the Zenodo data archive.

```bash
git clone https://github.com/USERNAME/REPO.git
cd REPO/final-project

# Unpack Zenodo archive into data/ (see Zenodo record for file list)

pip install -r requirements.txt
Rscript setup-r.R

make all    # tables + figures + report.pdf
```

Outputs:

- `report/report.pdf` — main manuscript
- `report/figures/` — exported figures
- `data/*.csv` — tables backing the paper

## Full path (rebuild raw data from APIs)

Requires `ENTSOE_API_KEY` and a Copernicus CDS token (`~/.cdsapirc`).

```bash
export ENTSOE_API_KEY="your-token"
pip install -r requirements.txt
Rscript setup-r.R

make raw-data && make all
```

Pipeline scripts (in `codes/`):

| Step | Script | Output |
|------|--------|--------|
| 1 | `01_download_population.py` | `data/eurostat_population_annual.csv`, `data/gpw_grid_weights.parquet` |
| 2 | `02_download_load.py` | `energy_country_level/hourly_load_country_*.parquet` |
| 3 | `03_download_weather.py` | ERA5 NetCDF in `era5_eu_data/` |
| 4 | `04_merge_data.py` | `data/final_integrated_u_curve_dataset.parquet` |
| 5 | `05_build_daily_panel.py` | `data/daily_integrated_u_curve_dataset.parquet` |

Place `data/gpw_v4_population_2020.tif` (NASA SEDAC GPW v4) for full population-weighted weather aggregation.

## What to upload where

### GitHub (source code only)

- All files in this directory except large data and secrets
- Tag release `v1.0` for Zenodo GitHub integration

### Zenodo (citable data + PDF)

Upload alongside the GitHub release ZIP:

- `data/cleaned_daily_weather_load.csv`
- `data/daily_integrated_u_curve_dataset.parquet`
- `data/final_integrated_u_curve_dataset.parquet` (hourly; needed for Section 6)
- `data/eurostat_population_annual.csv`, `data/gpw_grid_weights.parquet`
- Exported CSV tables (`stationarity_*.csv`, `baseline_*.csv`, `ardl_*.csv`, etc.)
- `report/report.pdf`

### Never upload

- `codes/.env` (ENTSO-E API key) — use environment variable instead
- Raw ENTSO-E cache (`energy_country_level/_cache_*`)
- Raw ERA5 NetCDF (`era5_eu_data/*.nc`)
- `gpw_v4_population_2020.tif` (NASA SEDAC licence)

## Makefile targets

| Target | Description |
|--------|-------------|
| `make all` | `tables` + `figures` + `report` |
| `make tables` | Regenerate CSV exports |
| `make figures` | Regenerate `report/figures/*.pdf` |
| `make report` | Compile LaTeX PDF |
| `make analysis` | Knit `final-project-analysis.Rmd` |
| `make raw-data` | Run Python pipeline 01--05 |
| `make clean` | Remove derived artefacts |

## Main analysis files

- `final-project-analysis.Rmd` — full econometric notebook
- `report/report.tex` — LaTeX manuscript
- `export-publication-tables.R`, `export-checklist-tables.R` — table exports

Helper functions at repo root: `function_testdf2.R` (ADF selection).
