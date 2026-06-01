#!/usr/bin/env Rscript
# Export publication tables without full Rmd knit (stationarity + baseline diagnostics).

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(purrr)
  library(lmtest)
  library(tseries)
  library(urca)
  library(car)
})

DATA_DIR <- normalizePath("data", mustWork = TRUE)
FOCUS_COUNTRIES <- c("DE", "ES", "FI", "FR", "PL")

candidates <- c(
  "../function_testdf2.R",
  "../../function_testdf2.R",
  "function_testdf2.R"
)
testdf_path <- candidates[file.exists(candidates)][1]
if (is.na(testdf_path)) stop("function_testdf2.R not found")
source(testdf_path)

daily_clean <- read_csv(
  file.path(DATA_DIR, "cleaned_daily_weather_load.csv"),
  show_col_types = FALSE
) %>% mutate(date = as.Date(date))

best_adf <- function(x, test.type = "c", max.augmentations = 5, max.order = 5) {
  x <- na.omit(as.numeric(x))
  if (length(x) < 30) return(tibble(augmentations = NA_integer_, adf_stat = NA_real_, adf_p = NA_real_))
  tab <- testdf2(variable = x, test.type = test.type, max.augmentations = max.augmentations, max.order = max.order)
  pbg_cols <- grep("^p_bg", names(tab), value = TRUE)
  if (length(pbg_cols) > 0) tab$min_bg_p <- apply(tab[, pbg_cols, drop = FALSE], 1, min, na.rm = TRUE)
  else tab$min_bg_p <- NA_real_
  ok <- tab[!is.na(tab$min_bg_p) & tab$min_bg_p > 0.05, , drop = FALSE]
  pick <- if (nrow(ok) > 0) ok[1, ] else tab[1, ]
  tibble(augmentations = as.integer(pick$augmentations), adf_stat = as.numeric(pick$adf), adf_p = as.numeric(pick$p_adf))
}

run_kpss <- function(x, type = "mu") {
  x <- na.omit(as.numeric(x))
  k <- urca::ur.kpss(x, type = type)
  crit <- k@cval["critical values", "5pct"]
  tibble(kpss_stat = as.numeric(k@teststat), kpss_5pct_crit = as.numeric(crit),
         kpss_reject_5pct = as.numeric(k@teststat) > as.numeric(crit))
}

run_pp <- function(x, model = "constant") {
  x <- na.omit(as.numeric(x))
  p <- urca::ur.pp(x, type = "Z-tau", model = model)
  tt <- suppressWarnings(tseries::pp.test(x))
  tibble(pp_stat = as.numeric(p@teststat), pp_p = as.numeric(tt$p.value))
}

stationarity_block <- function(x, label, adf_type, kpss_type, pp_model) {
  cbind(tibble(series = label), best_adf(x, test.type = adf_type), run_pp(x, model = pp_model), run_kpss(x, type = kpss_type)) %>%
    mutate(stationary_all_three = (adf_p < 0.05) & (pp_p < 0.05) & (!kpss_reject_5pct))
}

adf_results <- map_dfr(FOCUS_COUNTRIES, function(cc) {
  sub <- daily_clean %>% filter(country_code == cc) %>% arrange(date)
  bind_rows(
    bind_cols(tibble(country = cc), stationarity_block(sub$log_load, "log_load_levels", "c", "mu", "constant")),
    bind_cols(tibble(country = cc), stationarity_block(diff(sub$log_load), "d_log_load", "nc", "mu", "constant")),
    bind_cols(tibble(country = cc), stationarity_block(sub$temperature_c, "temperature_c_levels", "c", "mu", "constant")),
    bind_cols(tibble(country = cc), stationarity_block(diff(sub$temperature_c), "d_temperature_c", "nc", "mu", "constant"))
  )
})

write_csv(adf_results, file.path(DATA_DIR, "stationarity_focus_countries.csv"))
message("Wrote stationarity_focus_countries.csv")

fit_baseline_ols <- function(dat) {
  lm(load_mw ~ temperature_c + I(temperature_c^2) + weekday + month +
       dewpoint_c + wind_speed_ms + solar_radiation_wm2 + tcc, data = dat)
}

baseline_diag_table <- map_dfr(FOCUS_COUNTRIES, function(cc) {
  sub <- daily_clean %>% filter(country_code == cc)
  m <- fit_baseline_ols(sub)
  res <- residuals(m)
  bg_orders <- c(1, 5, 7, 14)
  bg_p <- sapply(bg_orders, function(k) lmtest::bgtest(m, order = k)$p.value)
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  tibble(
    country = cc,
    bp_p = as.numeric(suppressWarnings(lmtest::bptest(m)$p.value)),
    reset_p = as.numeric(tryCatch(suppressWarnings(lmtest::resettest(m)$p.value), error = function(e) NA_real_)),
    jb_p = as.numeric(suppressWarnings(tseries::jarque.bera.test(res)$p.value)),
    !!!as.list(bg_p)
  )
})

write_csv(baseline_diag_table, file.path(DATA_DIR, "baseline_diagnostics_focus.csv"))
message("Wrote baseline_diagnostics_focus.csv")
