# Weather and European Electricity Load — Final Project

Author: **Giang Tran**

Replication package for the econometric analysis of temperature-load dynamics across 21 European countries (2020-2024).

## Archive

- **GitHub:** `https://github.com/giangphuongtran/advanced-econometrics` (release tag `v1.0`)
- **Zenodo:** [DOI: 10.5281/zenodo.20493283](https://doi.org/10.5281/zenodo.20493282)

## Quick start

No API keys required if you use the Zenodo data archive.

```bash

git clone https://github.com/giangphuongtran/advanced-econometrics.git

# Unpack Zenodo archive into data/ (see Zenodo record for file list)

pip install -r requirements.txt
Rscript setup-r.R

make all    # Knits Rmd, auto-generates LaTeX tables, and compiles report.pdf
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

<<<<<<< HEAD
## Makefile targets

| Target | Description |
|--------|-------------|
| `make all` | `tables` + `figures` + `report` |

=======
>>>>>>> saved-work
## Main analysis files

- `final-project-analysis.Rmd` — full econometric notebook
- `report/report.tex` — LaTeX manuscript

Helper functions at repo root: `function_testdf2.R` (ADF selection).
