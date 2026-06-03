# Export LaTeX report figures from the analysis notebook pipeline.
# Called from combined-analysis.Rmd after models are estimated.

export_report_figures <- function(
    daily_clean,
    hourly_raw = NULL,
    focus_countries = c("DE", "ES", "FI", "FR", "PL"),
    analysis_end = as.Date("2024-12-31"),
    fig_dir = "report/figures",
    fit_arima_xreg = NULL,
    y_test = NULL,
    fc_mean = NULL,
    y_sub_for_plot = NULL,
    holdout_idx = NULL,
    plot_idx = NULL
) {
  suppressPackageStartupMessages({
    library(tidyverse)
    library(forecast)
  })

  dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
  focus <- daily_clean %>% filter(country_code %in% focus_countries)

  p1 <- ggplot(focus, aes(x = date, y = load_mw, color = country_code)) +
    geom_line(linewidth = 0.25, alpha = 0.9) +
    facet_wrap(~country_code, ncol = 1, scales = "free_y") +
    labs(x = NULL, y = "Load (MW)") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "none", strip.text = element_text(face = "bold"))
  ggsave(file.path(fig_dir, "fig01_load_series.pdf"), p1, width = 10, height = 8)

  p2 <- ggplot(focus, aes(x = temperature_c, y = load_mw)) +
    geom_point(alpha = 0.08, size = 0.35, color = "steelblue") +
    geom_smooth(
      method = "lm",
      formula = y ~ poly(x, 2, raw = TRUE),
      se = TRUE,
      color = "darkred",
      linewidth = 0.8
    ) +
    facet_wrap(~country_code, scales = "free") +
    labs(
      x = expression("Temperature (" * degree * "C)"),
      y = "Load (MW)"
    ) +
    theme_minimal(base_size = 11)
  ggsave(file.path(fig_dir, "fig02_temp_load_scatter.pdf"), p2, width = 10, height = 7)

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
    facet_wrap(~country_code, scales = "free") +
    labs(
      x = expression("Temperature (" * degree * "C)"),
      y = "Load (MW)"
    ) +
    theme_minimal(base_size = 11)
  ggsave(file.path(fig_dir, "fig06_turning_points.pdf"), p6, width = 10, height = 7)

  plot_acf_pdf <- function(residuals, filename, max_lag = 60) {
    n <- length(residuals)
    max_lag <- min(max_lag, n - 1)
    acf_vals <- acf(residuals, lag.max = max_lag, plot = FALSE)$acf[, , 1]
    ci <- 1.96 / sqrt(n)
    df <- data.frame(lag = 0:max_lag, acf = acf_vals)
    p <- ggplot(df, aes(lag, acf)) +
      geom_segment(aes(xend = lag, yend = 0), linewidth = 0.5) +
      geom_hline(yintercept = c(-ci, ci), linetype = "dotted", color = "red") +
      labs(x = "Lag (days)", y = "ACF") +
      theme_minimal(base_size = 11)
    ggsave(file.path(fig_dir, filename), p, width = 8, height = 4)
  }

  de <- daily_clean %>% filter(country_code == "DE")
  m_ols <- fit_baseline_ols(de)
  plot_acf_pdf(residuals(m_ols), "fig03_ols_acf_de.pdf")

  z_de <- to_daily_zoo(de)
  m_ardl <- fit_ardl_models(z_de, country_code = "DE")$ardl_seasonal
  plot_acf_pdf(residuals(m_ardl), "fig04_ardl_acf_de.pdf")

  if (!is.null(y_test) && !is.null(fc_mean) && !is.null(plot_idx) && !is.null(holdout_idx)) {
    pdf(file.path(fig_dir, "fig05_de_forecast.pdf"), width = 10, height = 5)
    plot(
      plot_idx, y_sub_for_plot[plot_idx], type = "l", col = "gray50", lwd = 1,
      xlab = "Observation index", ylab = expression(log(load))
    )
    lines(holdout_idx, y_test, col = "black", lwd = 1.5)
    lines(holdout_idx, fc_mean, col = "red", lwd = 1.5)
    legend(
      "topleft",
      legend = c("Actual (holdout)", "ARIMA + xreg forecast"),
      col = c("black", "red"),
      lty = 1,
      bty = "n"
    )
    dev.off()
  }

  invisible(normalizePath(fig_dir))
}
