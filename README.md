# Weather and European Electricity Load — Final Project

Author: **Giang Tran**

Replication package for the econometric analysis of temperature-load dynamics across 21 European countries (2020-2024).

## Quick start

No API keys required if you use the Zenodo data archive.

```bash
git clone [https://github.com/giangphuongtran/advanced-econometrics.git](https://github.com/giangphuongtran/advanced-econometrics.git)

# Unpack Zenodo archive into data/ (see Zenodo record for file list)

pip install -r requirements.txt
Rscript setup-r.R

make all    # Knits Rmd, auto-generates LaTeX tables, and compiles report.pdf