# Shared analysis helpers for combined-analysis.Rmd and replication scripts.

suppressPackageStartupMessages({
  library(tidyverse)
  library(zoo)
  library(dynlm)
  library(lmtest)
  library(tseries)
  library(urca)
  library(mgcv)
  library(car)
})

testdf_candidates <- c(
  "../function_testdf2.R",
  "../../function_testdf2.R",
  "function_testdf2.R"
)
testdf_path <- testdf_candidates[file.exists(testdf_candidates)][1]
if (is.na(testdf_path)) {
  stop("function_testdf2.R not found in expected repository locations.", call. = FALSE)
}
source(testdf_path)

COUNTRY_NAMES <- c(
  AT = "Austria", BE = "Belgium", BG = "Bulgaria", HR = "Croatia", CZ = "Czechia",
  DK = "Denmark", FI = "Finland", FR = "France", DE = "Germany", GR = "Greece",
  HU = "Hungary", IE = "Ireland", IT = "Italy", NL = "Netherlands", PL = "Poland",
  PT = "Portugal", RO = "Romania", SK = "Slovakia", SI = "Slovenia", ES = "Spain",
  SE = "Sweden"
)

GTS_OLS_SURVIVING <- tribble(
  ~variable, ~DE, ~ES, ~FI, ~FR, ~PL,
  "dewpoint_c", 0, 0, 0, 1, 1,
  "wind_speed_ms", 1, 1, 1, 0, 0,
  "solar_radiation_wm2", 0, 0, 0, 1, 0,
  "tcc", 1, 1, 0, 0, 0,
  "precipitation_mm", 0, 1, 0, 0, 0
)

GTS_MONTH_MERGES <- tibble(
  country = c("DE", "ES", "FI", "FR", "PL"),
  month_merges = c(
    "Nov -> Jan", "Feb, Jul -> Jan", "Dec -> Jan", "None", "Mar, Oct, Nov -> Jan"
  )
)

best_adf <- function(x, test.type = "c", max.augmentations = 5, max.order = 5) {
  x <- na.omit(as.numeric(x))
  if (length(x) < 30) {
    return(tibble(augmentations = NA_integer_, adf_stat = NA_real_, adf_p = NA_real_))
  }
  tab <- testdf2(
    variable = x,
    test.type = test.type,
    max.augmentations = max.augmentations,
    max.order = max.order
  )
  pbg_cols <- grep("^p_bg", names(tab), value = TRUE)
  if (length(pbg_cols) > 0) {
    tab$min_bg_p <- apply(tab[, pbg_cols, drop = FALSE], 1, min, na.rm = TRUE)
  } else {
    tab$min_bg_p <- NA_real_
  }
  ok <- tab[!is.na(tab$min_bg_p) & tab$min_bg_p > 0.05, , drop = FALSE]
  pick <- if (nrow(ok) > 0) ok[1, ] else tab[1, ]
  tibble(
    augmentations = as.integer(pick$augmentations),
    adf_stat = as.numeric(pick$adf),
    adf_p = as.numeric(pick$p_adf)
  )
}

run_kpss <- function(x, type = "mu") {
  x <- na.omit(as.numeric(x))
  if (length(x) < 30) {
    return(tibble(kpss_stat = NA_real_, kpss_5pct_crit = NA_real_, kpss_reject_5pct = NA))
  }
  k <- urca::ur.kpss(x, type = type)
  crit <- k@cval["critical values", "5pct"]
  tibble(
    kpss_stat = as.numeric(k@teststat),
    kpss_5pct_crit = as.numeric(crit),
    kpss_reject_5pct = as.numeric(k@teststat) > as.numeric(crit)
  )
}

run_pp <- function(x, model = "constant") {
  x <- na.omit(as.numeric(x))
  if (length(x) < 30) return(tibble(pp_stat = NA_real_, pp_p = NA_real_))
  p <- urca::ur.pp(x, type = "Z-tau", model = model)
  tt <- suppressWarnings(tseries::pp.test(x))
  tibble(
    pp_stat = as.numeric(p@teststat),
    pp_p = as.numeric(tt$p.value)
  )
}

stationarity_block <- function(x, label, adf_type, kpss_type, pp_model) {
  cbind(
    tibble(series = label),
    best_adf(x, test.type = adf_type),
    run_pp(x, model = pp_model),
    run_kpss(x, type = kpss_type)
  ) %>%
    mutate(
      stationary_all_three = (adf_p < 0.05) & (pp_p < 0.05) & (!kpss_reject_5pct)
    )
}

fit_baseline_ols <- function(dat) {
  lm(
    load_mw ~ temperature_c + I(temperature_c^2) + is_weekend + month +
      dewpoint_c + wind_speed_ms + solar_radiation_wm2 + tcc,
    data = dat
  )
}

fit_baseline_gam <- function(dat) {
  dat <- dat %>%
    mutate(temperature_c_centered = temperature_c - mean(temperature_c, na.rm = TRUE))
  gam(
    load_mw ~ s(temperature_c_centered, bs = "cr", k = 10) +
      is_weekend + month + dewpoint_c + wind_speed_ms + solar_radiation_wm2 + tcc,
    data = dat,
    method = "REML"
  )
}

u_curve_turning_point <- function(model) {
  b <- coef(model)
  if (!all(c("temperature_c", "I(temperature_c^2)") %in% names(b))) return(NA_real_)
  beta1 <- b["temperature_c"]
  beta2 <- b["I(temperature_c^2)"]
  -beta1 / (2 * beta2)
}

baseline_diagnostics <- function(model) {
  res <- residuals(model)
  bg_orders <- c(1, 5, 7, 14)
  bg_p <- sapply(bg_orders, function(k) bgtest(model, order = k)$p.value)
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  bp_p <- suppressWarnings(bptest(model)$p.value)
  reset_p <- tryCatch(suppressWarnings(resettest(model)$p.value), error = function(e) NA_real_)
  jb_p <- tryCatch(
    suppressWarnings(tseries::jarque.bera.test(res)$p.value),
    error = function(e) NA_real_
  )
  vif_vals <- tryCatch(car::vif(model), error = function(e) NULL)
  vif_temp <- if (!is.null(vif_vals)) {
    v <- vif_vals
    if (is.matrix(v)) v <- v[, "GVIF"]
    nm <- names(v)
    tmp_idx <- nm == "temperature_c"
    if (any(tmp_idx)) as.numeric(v[tmp_idx]) else NA_real_
  } else {
    NA_real_
  }
  c(
    bg_p,
    bp_p = as.numeric(bp_p),
    reset_p = as.numeric(reset_p),
    jb_p = as.numeric(jb_p),
    vif_temperature = vif_temp
  )
}

build_panel_country_summary <- function(daily_clean, pop_annual) {
  daily_clean %>%
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
      pop_annual %>%
        filter(year == 2024) %>%
        select(country_code, population_2024 = population),
      by = "country_code"
    ) %>%
    arrange(country_code)
}

f_test_p <- function(model, hyp) {
  as.numeric(linearHypothesis(model, hyp)$`Pr(>F)`[2])
}

build_gts_ols_reduction_de <- function(
    model_ols_general,
    model_ols_reduced2,
    model_ols_reduced3
) {
  r2 <- function(m) summary(m)$r.squared
  tibble(
    step = 1:5,
    model = c(
      "General OLS",
      "Collinearity check (dewpoint, solar)",
      "Joint F on insignificant set",
      "Merge Nov into Jan",
      "Drop precipitation (final)"
    ),
    change = c(
      "Full model with all weather controls",
      "Test H0: dewpoint_c = solar_radiation_wm2 = 0",
      "Test H0: dewpoint, solar, month02, month11, precipitation = 0",
      "month_reduced with Nov merged to Jan baseline",
      "Drop precipitation_mm -> final parsimonious OLS"
    ),
    r_squared = c(
      r2(model_ols_general),
      r2(model_ols_general),
      r2(model_ols_general),
      r2(model_ols_reduced2),
      r2(model_ols_reduced3)
    ),
    f_test_p = c(
      NA_real_,
      f_test_p(model_ols_general, c("dewpoint_c = 0", "solar_radiation_wm2 = 0")),
      f_test_p(model_ols_general, c(
        "dewpoint_c = 0", "solar_radiation_wm2 = 0", "month02 = 0",
        "month11 = 0", "precipitation_mm = 0"
      )),
      f_test_p(model_ols_general, c(
        "dewpoint_c = 0", "solar_radiation_wm2 = 0", "month11 = 0"
      )),
      f_test_p(model_ols_general, c(
        "dewpoint_c = 0", "solar_radiation_wm2 = 0", "month11 = 0",
        "precipitation_mm = 0"
      ))
    )
  )
}

get_retained_vars <- function(country_code) {
  vars <- list(
    DE = c("wind_speed_ms", "tcc"),
    ES = c("wind_speed_ms", "tcc", "precipitation_mm"),
    FI = c("wind_speed_ms"),
    FR = c("dewpoint_c", "solar_radiation_wm2"),
    PL = c("dewpoint_c")
  )
  if (country_code %in% names(vars)) vars[[country_code]] else character(0)
}

to_daily_zoo <- function(dat) {
  dat <- dat %>% arrange(date)
  if (!"weekday" %in% names(dat)) {
    dat$weekday <- weekdays(as.Date(dat$date))
  }
  weekday_levels <- sort(unique(as.character(dat$weekday)))
  if (length(weekday_levels) >= 2) {
    wf <- factor(as.character(dat$weekday), levels = weekday_levels)
    wmm <- model.matrix(~ wf)[, -1, drop = FALSE]
    colnames(wmm) <- paste0("wd_", make.names(colnames(wmm)))
    wmm_df <- as.data.frame(wmm)
  } else {
    wmm_df <- data.frame()
  }
  base <- data.frame(
    log_load = dat$log_load,
    temperature_c = dat$temperature_c,
    temp_c2 = dat$temp_c2,
    wind_speed_ms = dat$wind_speed_ms,
    tcc = dat$tcc,
    precipitation_mm = dat$precipitation_mm,
    dewpoint_c = dat$dewpoint_c,
    solar_radiation_wm2 = dat$solar_radiation_wm2
  )
  res <- if (ncol(wmm_df) > 0) cbind(base, wmm_df) else base
  zoo(res, order.by = dat$date)
}

weekday_rhs <- function(z) {
  paste(grep("^wd_", colnames(z), value = TRUE), collapse = " + ")
}

fit_ardl_models <- function(z, start_date = NULL, country_code = NULL) {
  if (!is.null(start_date)) {
    z <- window(z, start = start_date)
  }
  w <- weekday_rhs(z)
  extra_vars <- get_retained_vars(country_code)
  extra_rhs <- ""
  if (length(extra_vars) > 0) {
    extra_rhs <- paste0(" + ", paste(paste0("d(", extra_vars, ")"), collapse = " + "))
  }
  build <- function(rhs) {
    form_str <- paste("d(log_load) ~", rhs, extra_rhs)
    if (nzchar(w)) form_str <- paste(form_str, "+", w)
    as.formula(form_str)
  }
  list(
    dl_full = dynlm(
      build("d(temperature_c) + L(d(temperature_c), 1:3) + d(temp_c2)"),
      data = z
    ),
    dl_pars = dynlm(
      build("d(temperature_c) + L(d(temperature_c), c(1, 3)) + d(temp_c2)"),
      data = z
    ),
    ardl_full = dynlm(
      build("L(d(log_load), 1:2) + d(temperature_c) + L(d(temperature_c), 1:3) + d(temp_c2)"),
      data = z
    ),
    ardl_pars = dynlm(
      build("L(d(log_load), 1:2) + d(temperature_c) + L(d(temperature_c), c(1, 3)) + d(temp_c2)"),
      data = z
    ),
    ardl_seasonal = dynlm(
      build(paste(
        "L(d(log_load), c(1, 2, 7)) +",
        "d(temperature_c) + L(d(temperature_c), c(1, 3, 7)) +",
        "d(temp_c2)"
      )),
      data = z
    )
  )
}

short_run_temp_effect <- function(model) {
  cf <- coef(model)
  nm <- names(cf)
  idx <- (nm == "d(temperature_c)") | grepl("^L\\(d\\(temperature_c\\),", nm)
  sum(cf[idx], na.rm = TRUE)
}

ardl_diagnostics <- function(model) {
  bg_orders <- c(1, 5, 7, 14)
  bg_p <- sapply(bg_orders, function(k) {
    lmtest::bgtest(residuals(model) ~ 1, order = k)$p.value
  })
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  list(
    bg = bg_p,
    aic = AIC(model),
    short_run_temp = short_run_temp_effect(model)
  )
}

ramsey_reset_p <- function(model) {
  tryCatch({
    e <- residuals(model)
    f <- fitted(model)
    anova(lm(e ~ 1), lm(e ~ f + I(f^2) + I(f^3)))$`Pr(>F)`[2]
  }, error = function(e) NA_real_)
}

ardl_final_diagnostics <- function(model) {
  bg_orders <- c(1, 5, 7, 14)
  bg_p <- sapply(bg_orders, function(k) {
    lmtest::bgtest(residuals(model) ~ 1, order = k)$p.value
  })
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  c(
    bg_p,
    bp_p = as.numeric(suppressWarnings(lmtest::bptest(model)$p.value)),
    white_p = as.numeric(tryCatch({
      res <- residuals(model)
      f <- fitted(model)
      suppressWarnings(lmtest::bptest(lm(res ~ f + I(f^2)))$p.value)
    }, error = function(e) NA_real_)),
    reset_p = as.numeric(tryCatch(
      suppressWarnings(lmtest::resettest(model)$p.value),
      error = function(e) ramsey_reset_p(model)
    )),
    aic = AIC(model),
    bic = BIC(model)
  )
}

model_step_summary <- function(fitted_model, label) {
  d <- ardl_diagnostics(fitted_model)
  tibble(
    model = label,
    aic = AIC(fitted_model),
    bic = BIC(fitted_model),
    bg_p_order1 = d$bg[["bg_p_order1"]],
    bg_p_order7 = d$bg[["bg_p_order7"]],
    short_run_temp = d$short_run_temp
  )
}
