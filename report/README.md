# LaTeX Final Project Report

Author: **Giang Tran**

## Contents

| File | Description |
|------|-------------|
| `report.tex` | Main manuscript (compile to PDF) |
| `references.bib` | Bibliography (ENTSO-E, ERA5, Eurostat, GPW, literature) |
| `appendix_code.R` | Commented R excerpt (Appendix A) |
| `export-figures.R` | Regenerates figures in `figures/` (fig01--fig06) |
| `export-data-table.R` | Exports `data/panel_country_summary.csv` for Table 3.1 |

## Compile to PDF

From `final-project/` (recommended):

```bash
make all        # knit combined-analysis.Rmd, then compile report PDF
make analysis   # HTML notebook + all data/*.csv + report/figures/
make report     # PDF only (requires prior make analysis)
```

Or manually from `final-project/report/`:

```bash
pdflatex report && bibtex report && pdflatex report && pdflatex report
```

Requires: `natbib`, `booktabs`, `graphicx`, `hyperref`, `listings`, `longtable`.

**Canonical analysis:** [combined-analysis.Rmd](../combined-analysis.Rmd) — shared helpers in [R/analysis-helpers.R](../R/analysis-helpers.R). All CSV tables and report figures are produced by knitting the Rmd (`make analysis`); the old `export-*.R` scripts are deprecated.

## Replication pipeline (summary)

See Appendix B in `report.tex` for the full two-tier workflow.

### Fast path (no API keys)

1. Clone GitHub repo at tag `v1.0`
2. Download Zenodo archive into `../data/`
3. `pip install -r ../requirements.txt` and `Rscript ../setup-r.R`
4. From `final-project/`: `make all`

### Full path (raw API re-download)

Run from `final-project/codes/`:

1. `01_download_population.py` → `data/eurostat_population_annual.csv`, `data/gpw_grid_weights.parquet`
2. `02_download_load.py` / `03_download_weather.py` (raw downloads; API keys required)
3. `04_merge_data.py` → `data/final_integrated_u_curve_dataset.parquet`
4. `05_build_daily_panel.py` → `data/daily_integrated_u_curve_dataset.parquet`
5. `make all` from `final-project/`

Place GPW v4 GeoTIFF at `data/gpw_v4_population_2020.tif` for full spatial population weights.

## Key CSV exports

| File | Report use |
|------|------------|
| `data/panel_country_summary.csv` | Table 3.1 merged panel |
| `data/stationarity_focus_countries.csv` | Table 4.1 unit-root tests |
| `data/baseline_diagnostics_focus.csv` | Baseline OLS diagnostics |
| `data/baseline_ols_focus.csv` | Baseline OLS U-curve (focus countries) |
| `data/forecast_metrics_de.csv` | Hourly forecast holdout (DE) |
| `data/gts_ols_reduction_de.csv` | Static GTS reduction path (DE) |
| `data/gts_ols_surviving.csv` | Retained weather controls by country |
| `data/gts_month_merges.csv` | Month merges from static GTS |
| `data/gam_aic_comparison_de.csv` | Quadratic OLS vs GAM (DE) |
| `data/ardl_diagnostics_focus.csv` | Final ARDL diagnostics |
| `data/ardl_model_comparison_de.csv` | Dynamic GTS ARDL path (DE) |
| `data/ardl_vs_arima_de.csv` | ARDL vs ARIMA (DE) |

Canonical analysis notebook: `../combined-analysis.Rmd` (knit via `make analysis` or `Rscript run-all.R`).

## Figures

| File | Content |
|------|---------|
| `fig01_load_series.pdf` | Daily load time series |
| `fig02_temp_load_scatter.pdf` | Temperature vs load (quadratic) |
| `fig03_ols_acf_de.pdf` | OLS residual ACF (DE) |
| `fig04_ardl_acf_de.pdf` | ARDL residual ACF (DE) |
| `fig05_de_forecast.pdf` | Hourly forecast holdout (DE) |
| `fig06_turning_points.pdf` | U-curve turning points and comfort zones |

## Archive

Zenodo: [https://doi.org/10.5281/zenodo.XXXXXXX](https://doi.org/10.5281/zenodo.XXXXXXX) (replace after upload)
