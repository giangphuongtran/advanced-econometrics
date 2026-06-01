#!/usr/bin/env Rscript
# Install R packages required for replication (idempotent).

required_pkgs <- c(
  "tidyverse", "arrow", "zoo", "xts", "dynlm", "lmtest", "sandwich",
  "forecast", "tseries", "urca", "fUnitRoots", "mgcv", "patchwork", "car",
  "rmarkdown", "readr", "dplyr", "purrr"
)

missing <- required_pkgs[!vapply(required_pkgs, requireNamespace, quietly = TRUE, FUN. = logical(1))]

if (length(missing) == 0) {
  message("All required R packages are already installed.")
} else {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}

message("R setup complete.")
