#!/usr/bin/env Rscript
# Export Section 3.1 panel summary table (country names + merged variables + population).

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

args <- commandArgs(trailingOnly = FALSE)
script_path <- sub("--file=", "", args[grep("--file=", args)])
if (length(script_path)) {
  setwd(dirname(normalizePath(script_path)))
}

DATA_DIR <- normalizePath("../data", mustWork = TRUE)

COUNTRY_NAMES <- c(
  AT = "Austria", BE = "Belgium", BG = "Bulgaria", HR = "Croatia", CZ = "Czechia",
  DK = "Denmark", FI = "Finland", FR = "France", DE = "Germany", GR = "Greece",
  HU = "Hungary", IE = "Ireland", IT = "Italy", NL = "Netherlands", PL = "Poland",
  PT = "Portugal", RO = "Romania", SK = "Slovakia", SI = "Slovenia", ES = "Spain",
  SE = "Sweden"
)

daily <- read_csv(
  file.path(DATA_DIR, "cleaned_daily_weather_load.csv"),
  show_col_types = FALSE
)

pop <- read_csv(
  file.path(DATA_DIR, "eurostat_population_annual.csv"),
  show_col_types = FALSE
) %>%
  filter(year == 2024)

panel_summary <- daily %>%
  group_by(country_code) %>%
  summarise(
    n_days = n(),
    date_start = min(date),
    date_end = max(date),
    mean_load_mw = round(mean(load_mw), 0),
    mean_temperature_c = round(mean(temperature_c), 1),
    mean_dewpoint_c = round(mean(dewpoint_c), 1),
    mean_wind_ms = round(mean(wind_speed_ms), 2),
    mean_solar_wm2 = round(mean(solar_radiation_wm2), 1),
    mean_precip_mm = round(mean(precipitation_mm), 2),
    mean_tcc = round(mean(tcc), 3),
    .groups = "drop"
  ) %>%
  mutate(country_name = unname(COUNTRY_NAMES[country_code])) %>%
  left_join(
    pop %>% select(country_code, population_2024 = population),
    by = "country_code"
  ) %>%
  arrange(country_code)

write_csv(panel_summary, file.path(DATA_DIR, "panel_country_summary.csv"))
message("Wrote ", file.path(DATA_DIR, "panel_country_summary.csv"))
print(panel_summary, n = 25)
