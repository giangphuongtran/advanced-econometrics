#!/usr/bin/env Rscript
# Render the final project analysis notebook from final-project/

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
  input = "final-project-analysis.Rmd",
  output_format = "html_document",
  quiet = FALSE
)

message("Done. Output written next to final-project-analysis.Rmd")
