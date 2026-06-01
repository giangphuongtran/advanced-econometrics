# Replication Makefile — run from final-project/
# Fast path: download Zenodo data into data/, then `make all`
# Full path: set ENTSOE_API_KEY + CDS token, then `make raw-data && make all`

.PHONY: all tables figures report analysis raw-data clean help

all: tables figures report

tables:
	Rscript export-publication-tables.R
	Rscript export-checklist-tables.R
	cd report && Rscript export-data-table.R

figures:
	cd report && Rscript export-figures.R

report:
	cd report && pdflatex -interaction=nonstopmode report.tex
	cd report && bibtex report
	cd report && pdflatex -interaction=nonstopmode report.tex
	cd report && pdflatex -interaction=nonstopmode report.tex

analysis:
	Rscript run-all.R

raw-data:
	cd codes && python3 01_download_population.py
	cd codes && python3 02_download_load.py
	cd codes && python3 03_download_weather.py
	cd codes && python3 04_merge_data.py
	cd codes && python3 05_build_daily_panel.py

clean:
	rm -f data/stationarity_focus_countries.csv \
	      data/baseline_diagnostics_focus.csv \
	      data/ardl_diagnostics_focus.csv \
	      data/ardl_model_comparison_de.csv \
	      data/ardl_vs_arima_de.csv \
	      data/appendix_country_summary.csv \
	      data/panel_country_summary.csv
	rm -f report/report.pdf report/report.aux report/report.bbl report/report.blg report/report.log report/report.out

help:
	@echo "Targets:"
	@echo "  make all       - tables + figures + report PDF (default; uses data/ on disk)"
	@echo "  make tables    - export CSV tables for LaTeX"
	@echo "  make figures   - export PDF figures for report/"
	@echo "  make report    - compile report/report.tex"
	@echo "  make analysis  - knit final-project-analysis.Rmd to HTML"
	@echo "  make raw-data  - rebuild parquet from ENTSO-E + ERA5 (API keys required)"
	@echo "  make clean     - remove derived CSV/PDF artefacts"
