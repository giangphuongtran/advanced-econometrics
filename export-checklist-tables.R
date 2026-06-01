#!/usr/bin/env Rscript
# Export checklist CSV tables for LaTeX report (run from final-project/).

suppressPackageStartupMessages({
  library(tidyverse)
  library(zoo)
  library(dynlm)
  library(lmtest)
  library(forecast)
})

DATA_DIR <- "data"
FOCUS_COUNTRIES <- c("DE", "ES", "FI", "FR", "PL")
ANALYSIS_END <- as.Date("2024-12-31")

daily_clean <- read_csv(
  file.path(DATA_DIR, "cleaned_daily_weather_load.csv"),
  show_col_types = FALSE
) %>% mutate(date = as.Date(date))

to_daily_zoo <- function(dat) {
  dat <- dat %>% arrange(date)
  weekday_levels <- sort(unique(as.character(dat$weekday)))
  wf <- factor(as.character(dat$weekday), levels = weekday_levels)
  wmm <- model.matrix(~ wf)[, -1, drop = FALSE]
  colnames(wmm) <- paste0("wd_", make.names(colnames(wmm)))
  zoo(
    cbind(
      log_load = dat$log_load,
      temperature_c = dat$temperature_c,
      temp_c2 = dat$temp_c2,
      wmm
    ),
    order.by = dat$date
  )
}

weekday_rhs <- function(z) paste(grep("^wd_", colnames(z), value = TRUE), collapse = " + ")

fit_ardl_models <- function(z) {
  w <- weekday_rhs(z)
  build <- function(rhs) as.formula(paste("d(log_load) ~", rhs, "+", w))
  list(
    dl_full = dynlm(build("d(temperature_c) + L(d(temperature_c), 1:3) + d(temp_c2)"), data = z),
    dl_pars = dynlm(build("d(temperature_c) + L(d(temperature_c), c(1, 3)) + d(temp_c2)"), data = z),
    ardl_full = dynlm(build("L(d(log_load), 1:2) + d(temperature_c) + L(d(temperature_c), 1:3) + d(temp_c2)"), data = z),
    ardl_pars = dynlm(build("L(d(log_load), 1:2) + d(temperature_c) + L(d(temperature_c), c(1, 3)) + d(temp_c2)"), data = z),
    ardl_seasonal = dynlm(
      build("L(d(log_load), c(1, 2, 7)) + d(temperature_c) + L(d(temperature_c), c(1, 3, 7)) + d(temp_c2)"),
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
  bg_p <- sapply(bg_orders, function(k) bgtest(residuals(model) ~ 1, order = k)$p.value)
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  list(bg = bg_p, aic = AIC(model), short_run_temp = short_run_temp_effect(model))
}

ramsey_reset_p <- function(model) {
  tryCatch({
    e <- residuals(model)
    f <- fitted(model)
    m0 <- lm(e ~ 1)
    m1 <- lm(e ~ f + I(f^2) + I(f^3))
    anova(m0, m1)$`Pr(>F)`[2]
  }, error = function(e) NA_real_)
}

ardl_final_diagnostics <- function(model) {
  bg_orders <- c(1, 5, 7, 14)
  bg_p <- sapply(bg_orders, function(k) bgtest(residuals(model) ~ 1, order = k)$p.value)
  names(bg_p) <- paste0("bg_p_order", bg_orders)
  c(
    bg_p,
    bp_p = as.numeric(suppressWarnings(bptest(model)$p.value)),
    white_p = as.numeric(tryCatch({
      res <- residuals(model)
      f <- fitted(model)
      suppressWarnings(bptest(lm(res ~ f + I(f^2)))$p.value)
    }, error = function(e) NA_real_)),
    reset_p = as.numeric(ramsey_reset_p(model)),
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

# Diagnostics focus countries
ardl_diag_focus <- map_dfr(FOCUS_COUNTRIES, function(cc) {
  z <- to_daily_zoo(daily_clean %>% filter(country_code == cc))
  m <- fit_ardl_models(z)$ardl_seasonal
  bind_cols(
    tibble(country = cc, short_run_temp = short_run_temp_effect(m)),
    as_tibble(as.list(ardl_final_diagnostics(m)))
  )
})
write_csv(ardl_diag_focus, file.path(DATA_DIR, "ardl_diagnostics_focus.csv"))

# GTS table DE
de_sub <- daily_clean %>% filter(country_code == "DE")
z_de <- to_daily_zoo(de_sub)
mods_de <- fit_ardl_models(z_de)
gts_de <- bind_rows(
  model_step_summary(mods_de$dl_full, "DL full"),
  model_step_summary(mods_de$dl_pars, "DL parsimonious"),
  model_step_summary(mods_de$ardl_full, "ARDL full"),
  model_step_summary(mods_de$ardl_pars, "ARDL parsimonious"),
  model_step_summary(mods_de$ardl_seasonal, "Seasonal ARDL (final)")
)
write_csv(gts_de, file.path(DATA_DIR, "ardl_model_comparison_de.csv"))

# ARDL vs ARIMA daily DE
dlog <- diff(z_de$log_load)
dtemp <- diff(z_de$temperature_c)
dtemp2 <- diff(z_de$temp_c2)
wd_cols <- grep("^wd_", colnames(z_de), value = TRUE)
n_z <- nrow(z_de)
wd_for_diff <- as.matrix(z_de[2:n_z, wd_cols, drop = FALSE])
align_start <- 8L
y_arima <- as.numeric(dlog)[align_start:length(dlog)]
xreg_mat <- cbind(
  dtemp = as.numeric(dtemp)[align_start:length(dtemp)],
  dtemp2 = as.numeric(dtemp2)[align_start:length(dtemp2)],
  wd_for_diff[align_start:nrow(wd_for_diff), , drop = FALSE]
)
fit_arima_daily <- auto.arima(
  y_arima, xreg = xreg_mat, seasonal = FALSE,
  stepwise = TRUE, approximation = TRUE,
  max.p = 3, max.q = 3, max.order = 8
)
ardl_vs_arima <- tibble(
  model = c("Seasonal ARDL (final)", "ARIMA + weather xreg"),
  aic = c(AIC(mods_de$ardl_seasonal), AIC(fit_arima_daily)),
  bic = c(BIC(mods_de$ardl_seasonal), BIC(fit_arima_daily)),
  arima_order = c(NA_character_, paste(fit_arima_daily$arma[c(1, 6, 2)], collapse = ","))
)
write_csv(ardl_vs_arima, file.path(DATA_DIR, "ardl_vs_arima_de.csv"))

message("Exported: ardl_diagnostics_focus.csv, ardl_model_comparison_de.csv, ardl_vs_arima_de.csv")
print(ardl_vs_arima)
