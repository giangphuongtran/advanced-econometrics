#!/usr/bin/env Rscript
# Render the canonical analysis notebook from final-project/

args <- commandArgs(trailingOnly = FALSE)
script_path <- sub("--file=", "", args[grep("--file=", args)])
if (length(script_path)) {
  setwd(dirname(normalizePath(script_path)))
} else {
  setwd("final-project")
}

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  stop("Install the rmarkdown package: install.packages('rmarkdown')", call. = FALSE)
}

rmarkdown::render(
  input = "combined-analysis.Rmd",
  output_format = "html_document",
  quiet = FALSE
)

message("Done. Output written next to combined-analysis.Rmd")
