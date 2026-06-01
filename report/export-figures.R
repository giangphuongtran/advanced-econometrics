#!/usr/bin/env Rscript
# Export key figures for the LaTeX report.
# Run from final-project/report/:  Rscript export-figures.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(zoo)
  library(dynlm)
  library(lmtest)
  library(forecast)
  library(arrow)
})

FOCUS_COUNTRIES <- c("DE", "ES", "FI", "FR", "PL")
ANALYSIS_END <- as.Date("2024-12-31")

script_dir <- if (length(grep("^--file=", commandArgs(trailingOnly = FALSE))) > 0) {
  dirname(sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]))
} else {
  "."
}
setwd(script_dir)

fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

daily <- read_csv("../data/cleaned_daily_weather_load.csv", show_col_types = FALSE) %>%
  mutate(date = as.Date(date))

focus <- daily %>% filter(country_code %in% FOCUS_COUNTRIES)

# 1. Daily load time series
p1 <- ggplot(focus, aes(x = date, y = load_mw, color = country_code)) +
  geom_line(linewidth = 0.25, alpha = 0.9) +
  facet_wrap(~country_code, ncol = 1, scales = "free_y") +
  labs(
    title = "Daily electricity load (focus countries, 2020--2024)",
    x = NULL, y = "Load (MW)"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none", strip.text = element_text(face = "bold"))

ggsave(file.path(fig_dir, "fig01_load_series.pdf"), p1, width = 10, height = 8)

# 2. Temperature vs load scatter
p2 <- ggplot(focus, aes(x = temperature_c, y = load_mw)) +
  geom_point(alpha = 0.08, size = 0.35, color = "steelblue") +
  geom_smooth(
    method = "lm",
    formula = y ~ poly(x, 2, raw = TRUE),
    se = TRUE,
    color = "darkred",
    linewidth = 0.8
  ) +
  facet_wrap(~country_code, scales = "free_y") +
  labs(
    title = "Temperature vs. daily load (quadratic fit)",
    x = expression("Temperature (" * degree * "C)"),
    y = "Load (MW)"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(fig_dir, "fig02_temp_load_scatter.pdf"), p2, width = 10, height = 7)

# 2b. U-curve turning points and comfort zones (baseline OLS quadratic)
turning_points <- focus %>%
  group_by(country_code) %>%
  summarise(
    fit = list(lm(load_mw ~ temperature_c + I(temperature_c^2), data = pick(everything()))),
    .groups = "drop"
  ) %>%
  mutate(
    beta0 = vapply(fit, function(m) coef(m)["(Intercept)"], numeric(1)),
    beta1 = vapply(fit, function(m) coef(m)["temperature_c"], numeric(1)),
    beta2 = vapply(fit, function(m) coef(m)["I(temperature_c^2)"], numeric(1)),
    t_star = -beta1 / (2 * beta2)
  )

curve_df <- turning_points %>%
  rowwise() %>%
  reframe(
    country_code = country_code,
    temperature_c = seq(-10, 30, length.out = 200),
    load_hat = beta0 + beta1 * temperature_c + beta2 * temperature_c^2
  )

p6 <- ggplot() +
  geom_point(
    data = focus,
    aes(x = temperature_c, y = load_mw),
    alpha = 0.05, size = 0.3, color = "grey50"
  ) +
  geom_rect(
    data = turning_points,
    aes(xmin = t_star - 2, xmax = t_star + 2, ymin = -Inf, ymax = Inf),
    fill = "steelblue", alpha = 0.15, inherit.aes = FALSE
  ) +
  geom_line(
    data = curve_df,
    aes(x = temperature_c, y = load_hat),
    color = "darkred", linewidth = 0.8
  ) +
  geom_vline(
    data = turning_points,
    aes(xintercept = t_star),
    linetype = "dashed", color = "darkred"
  ) +
  geom_text(
    data = turning_points,
    aes(x = t_star, y = Inf, label = sprintf("T* = %.1f°C", t_star)),
    inherit.aes = FALSE,
    vjust = 1.4, hjust = -0.05, size = 3.2, color = "darkred"
  ) +
  facet_wrap(~country_code, scales = "free_y") +
  labs(
    title = "U-curve turning points and comfort zones (focus countries)",
    subtitle = "Comfort band = T* +/- 2°C; curve from baseline OLS quadratic",
    x = expression("Temperature (" * degree * "C)"),
    y = "Load (MW)"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(fig_dir, "fig06_turning_points.pdf"), p6, width = 10, height = 7)

# Helpers for ARDL / OLS
fit_baseline_ols <- function(dat) {
  lm(
    load_mw ~ temperature_c + I(temperature_c^2) + weekday + month +
      dewpoint_c + wind_speed_ms + solar_radiation_wm2 + tcc,
    data = dat
  )
}

to_daily_zoo <- function(dat) {
  dat <- dat %>% arrange(date)
  weekday_levels <- sort(unique(as.character(dat$weekday)))
  wf <- factor(as.character(dat$weekday), levels = weekday_levels)
  wmm <- model.matrix(~ wf)[, -1, drop = FALSE]
  colnames(wmm) <- paste0("wd_", make.names(colnames(wmm)))
  base <- data.frame(
    log_load = dat$log_load,
    temperature_c = dat$temperature_c,
    temp_c2 = dat$temp_c2
  )
  zoo(cbind(base, wmm), order.by = dat$date)
}

weekday_rhs <- function(z) paste(grep("^wd_", colnames(z), value = TRUE), collapse = " + ")

fit_seasonal_ardl <- function(z) {
  w <- weekday_rhs(z)
  rhs <- paste(
    "L(d(log_load), c(1, 2, 7)) +",
    "d(temperature_c) + L(d(temperature_c), c(1, 3, 7)) +",
    "d(temp_c2)"
  )
  dynlm(as.formula(paste("d(log_load) ~", rhs, "+", w)), data = z)
}

plot_acf_pdf <- function(residuals, title, filename, max_lag = 60) {
  n <- length(residuals)
  max_lag <- min(max_lag, n - 1)
  acf_vals <- acf(residuals, lag.max = max_lag, plot = FALSE)$acf[, , 1]
  ci <- 1.96 / sqrt(n)
  df <- data.frame(lag = 0:max_lag, acf = acf_vals)
  p <- ggplot(df, aes(lag, acf)) +
    geom_segment(aes(xend = lag, yend = 0), linewidth = 0.5) +
    geom_hline(yintercept = c(-ci, ci), linetype = "dotted", color = "red") +
    labs(title = title, x = "Lag (days)", y = "ACF") +
    theme_minimal(base_size = 11)
  ggsave(file.path(fig_dir, filename), p, width = 8, height = 4)
}

de <- daily %>% filter(country_code == "DE")

# 3. OLS residual ACF (DE)
m_ols <- fit_baseline_ols(de)
plot_acf_pdf(
  residuals(m_ols),
  "Baseline OLS residual ACF — Germany",
  "fig03_ols_acf_de.pdf"
)

# 4. Seasonal ARDL residual ACF (DE)
z_de <- to_daily_zoo(de)
m_ardl <- fit_seasonal_ardl(z_de)
plot_acf_pdf(
  residuals(m_ardl),
  "Seasonal ARDL residual ACF — Germany",
  "fig04_ardl_acf_de.pdf"
)

# 5. DE hourly forecast holdout plot (temperature-only xreg for fast export;
#    full metrics in report.tex come from the full Rmd with hour dummies.)
hourly <- arrow::open_dataset("../data/final_integrated_u_curve_dataset.parquet") %>%
  filter(country_code == "DE") %>%
  collect() %>%
  mutate(
    timestamp = as.POSIXct(timestamp, tz = "UTC"),
    date = as.Date(timestamp)
  ) %>%
  filter(date <= ANALYSIS_END, is.finite(load_mw), is.finite(temperature_c)) %>%
  arrange(timestamp) %>%
  mutate(log_load = log(load_mw))

y <- hourly$log_load
temp_xreg <- as.matrix(hourly$temperature_c)
h_holdout <- 14 * 24
n <- length(y)

sub_start <- max(1, n - 400 * 24 - h_holdout)
y_sub <- y[sub_start:n]
xreg_sub <- temp_xreg[sub_start:n, , drop = FALSE]
n_sub <- length(y_sub)

y_train <- y_sub[1:(n_sub - h_holdout)]
xreg_train <- xreg_sub[1:(n_sub - h_holdout), , drop = FALSE]
y_test <- y_sub[(n_sub - h_holdout + 1):n_sub]
xreg_test <- xreg_sub[(n_sub - h_holdout + 1):n_sub, , drop = FALSE]

fit_arima <- auto.arima(
  ts(y_train, frequency = 24),
  xreg = xreg_train,
  seasonal = TRUE,
  stepwise = TRUE,
  approximation = TRUE
)
fc_mean <- as.numeric(forecast(fit_arima, h = h_holdout, xreg = xreg_test)$mean)

holdout_idx <- (n_sub - h_holdout + 1):n_sub
plot_idx <- max(1, (n_sub - h_holdout - 7 * 24)):n_sub

pdf(file.path(fig_dir, "fig05_de_forecast.pdf"), width = 10, height = 5)
plot(
  plot_idx, y_sub[plot_idx], type = "l", col = "gray50", lwd = 1,
  main = "DE hourly log(load): 14-day holdout forecast (illustrative)",
  xlab = "Observation index (subsample)", ylab = expression(log(load))
)
lines(holdout_idx, y_test, col = "black", lwd = 1.5)
lines(holdout_idx, fc_mean, col = "red", lwd = 1.5)
legend(
  "topleft",
  legend = c("Actual (holdout)", "ARIMA + weather forecast"),
  col = c("black", "red"),
  lty = 1,
  bty = "n"
)
dev.off()

message("Figures saved to ", normalizePath(fig_dir))
