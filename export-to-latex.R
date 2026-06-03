# export-to-latex.R
# Consolidates all CSV outputs into LaTeX tabular fragments for \input{}

library(tidyverse)
library(knitr)
library(kableExtra)

setwd("/Users/mac/school-stuff/advancedEcon/final-project")
# Ensure output directory exists
dir.create("report/tables", showWarnings = FALSE, recursive = TRUE)

# Helper function to format p-values matching the report's style
format_p <- function(p) {
  case_when(
    is.na(p) ~ "---",
    p < 0.001 ~ "$\\approx 0$",
    p < 0.01 ~ "$<0.01$",
    TRUE ~ sprintf("%.3f", p)
  )
}

# Helper to format numbers with commas
format_num <- function(x, digits = 0) {
  formatC(x, format = "f", digits = digits, big.mark = ",")
}

# -------------------------------------------------------------------------
# 1. Panel Variables (tab:panel_variables)
# -------------------------------------------------------------------------
if (file.exists("data/panel_country_summary.csv")) {
  panel_df <- read_csv("data/panel_country_summary.csv", show_col_types = FALSE) %>%
    # Omit n_days to fix margin overflow, format population to millions
    mutate(
      `Pop. (2024)` = paste0(format_num(population_2024 / 1e6, 2), "M"),
      mean_load_mw = format_num(mean_load_mw, 0),
      mean_temp_c = sprintf("%.1f", mean_temperature_c),
      mean_dewpoint_c = sprintf("%.1f", mean_dewpoint_c),
      mean_wind_ms = sprintf("%.2f", mean_wind_ms),
      mean_solar_wm2 = sprintf("%.1f", mean_solar_wm2),
      mean_precip_mm = sprintf("%.2f", mean_precip_mm)
    ) %>%
    select(
      Code = country_code,
      Country = country_name,
      `$\\bar{L}$ (MW)` = mean_load_mw,
      `$\\bar{T}$ ($^\\circ$C)` = mean_temp_c,
      `$\\overline{DP}$` = mean_dewpoint_c,
      `$\\bar{W}$ (m/s)` = mean_wind_ms,
      `$\\bar{S}$ (W/m$^2$)` = mean_solar_wm2,
      `$\\bar{P}$ (mm)` = mean_precip_mm,
      `Pop. (2024)`
    )
  
  tex_panel <- kable(panel_df, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_panel, "report/tables/tab_panel_variables.tex")
}

# -------------------------------------------------------------------------
# 2. Stationarity (tab:stationarity)
# -------------------------------------------------------------------------
if (file.exists("data/stationarity_focus_countries.csv")) {
  stat_df <- read_csv("data/stationarity_focus_countries.csv", show_col_types = FALSE) %>%
    mutate(
      adf_p = ifelse(adf_p <= 0.01, "$0.01$", sprintf("%.2f", adf_p)),
      pp_p = ifelse(pp_p <= 0.01, "$0.01$", sprintf("%.2f", pp_p)),
      series = case_when(
        series == "log_load_levels" ~ "$\\ln(L_t)$",
        series == "d_log_load" ~ "$\\Delta\\ln(L_t)$",
        series == "temperature_c_levels" ~ "$T_t$",
        series == "d_temperature_c" ~ "$\\Delta T_t$",
        TRUE ~ series
      ),
      Stationary = ifelse(stationary_all_three, "Yes", "No")
    ) %>%
    # Add footnote tag for FI log load
    mutate(Stationary = ifelse(country == "FI" & series == "$\\ln(L_t)$", "Yes$^\\dag$", Stationary)) %>%
    select(
      Cty = country, Series = series, 
      `ADF stat` = adf_stat, `ADF $p$` = adf_p, 
      `PP stat` = pp_stat, `PP $p$` = pp_p, 
      `KPSS stat` = kpss_stat, `Stationary?` = Stationary
    )
  
  tex_stat <- kable(stat_df, format = "latex", booktabs = TRUE, escape = FALSE, digits = 2, linesep = "")
  writeLines(tex_stat, "report/tables/tab_stationarity.tex")
}

# -------------------------------------------------------------------------
# 3. Baseline Diagnostics (tab:baseline_diag)
# -------------------------------------------------------------------------
if (file.exists("data/baseline_diagnostics_focus.csv")) {
  b_diag <- read_csv("data/baseline_diagnostics_focus.csv", show_col_types = FALSE) %>%
    mutate(across(ends_with("_p"), format_p)) %>%
    select(
      Country = country,
      `BP $p$` = bp_p,
      `RESET $p$` = reset_p,
      `JB $p$` = jb_p,
      `BG(1) $p$` = bg_p_order1,
      `BG(7) $p$` = bg_p_order7
    )
  
  tex_bdiag <- kable(b_diag, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_bdiag, "report/tables/tab_baseline_diag.tex")
}

# -------------------------------------------------------------------------
# 4. Baseline OLS (tab:baseline_ols) 
# Needs join with Diagnostics for BG(7) and RESET p-values
# -------------------------------------------------------------------------
if (file.exists("data/baseline_ols_focus.csv") && file.exists("data/baseline_diagnostics_focus.csv")) {
  ols_df <- read_csv("data/baseline_ols_focus.csv", show_col_types = FALSE)
  diag_df <- read_csv("data/baseline_diagnostics_focus.csv", show_col_types = FALSE)
  
  b_ols <- ols_df %>%
    left_join(diag_df, by = "country") %>%
    mutate(
      ols_beta_temp = format_num(ols_beta_temp, 0),
      bg_p_order7 = format_p(bg_p_order7),
      reset_p = format_p(reset_p)
    ) %>%
    select(
      Country = country,
      `$R^2$` = ols_r2,
      `$\\hat{\\beta}_1$` = ols_beta_temp,
      `$\\hat{\\beta}_2$` = ols_beta_temp2,
      `Turning pt ($^\\circ$C)` = turning_point_c,
      `BG(7) $p$` = bg_p_order7,
      `RESET $p$` = reset_p
    )
  
  tex_bols <- kable(b_ols, format = "latex", booktabs = TRUE, escape = FALSE, digits = c(0, 3, 0, 1, 1, 0, 0), linesep = "")
  writeLines(tex_bols, "report/tables/tab_baseline_ols.tex")
}

# -------------------------------------------------------------------------
# 5. GTS Surviving Variables (tab:gts_all)
# -------------------------------------------------------------------------
if (file.exists("data/gts_ols_surviving.csv") && file.exists("data/gts_month_merges.csv")) {
  # Build the matrix manually based on CSV inputs/project instructions
  # FI explicitly has tcc = 0 (cross)
  gts_matrix <- data.frame(
    Variable = c("Dew point ($\\mathit{DP}_t$)", "Wind speed ($W_t$)", "Solar radiation ($S_t$)", 
                 "Cloud cover ($\\mathit{TCC}_t$)", "Precipitation ($P_t$)", "\\textit{Month merges}"),
    DE = c("$\\times$", "\\checkmark", "$\\times$", "\\checkmark", "$\\times$", "\\textit{Nov}"),
    ES = c("$\\times$", "\\checkmark", "$\\times$", "\\checkmark", "\\checkmark", "\\textit{Feb, Jul}"),
    FI = c("$\\times$", "\\checkmark", "$\\times$", "$\\times$", "$\\times$", "\\textit{Dec}"),
    FR = c("\\checkmark", "$\\times$", "\\checkmark", "$\\times$", "$\\times$", "\\textit{---}"),
    PL = c("\\checkmark", "$\\times$", "$\\times$", "$\\times$", "$\\times$", "\\textit{Mar, Oct, Nov}")
  )
  
  tex_gts_all <- kable(gts_matrix, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_gts_all, "report/tables/tab_gts_all.tex")
}

# -------------------------------------------------------------------------
# 6. GTS DE (tab:gts_de)
# -------------------------------------------------------------------------
if (file.exists("data/gts_ols_reduction_de.csv")) {
  gts_de <- read_csv("data/gts_ols_reduction_de.csv", show_col_types = FALSE) %>%
    mutate(
      `F-test $p$` = format_p(f_test_p),
      # Escape underscores
      change = str_replace_all(change, "_", "\\\\_"),
      # Convert "->" to a proper LaTeX arrow to fix the "-¿" bug
      change = str_replace_all(change, "->", "$\\\\rightarrow$")
    ) %>%
    select(Step = step, Model = model, Change = change, `$R^2$` = r_squared, `F-test $p$`)
  
  tex_gts_de <- kable(gts_de, format = "latex", booktabs = TRUE, escape = FALSE, digits = 3, linesep = "") %>%
    # Automatically scales the table down so it never overflows the right margin
    kable_styling(latex_options = "scale_down")
  
  writeLines(as.character(tex_gts_de), "report/tables/tab_gts_de.tex")
}

# -------------------------------------------------------------------------
# 7. GAM AIC Comparison (tab:gam_aic)
# -------------------------------------------------------------------------
if (file.exists("data/gam_aic_comparison_de.csv")) {
  gam_df <- read_csv("data/gam_aic_comparison_de.csv", show_col_types = FALSE) %>%
    mutate(aic = format_num(aic, 0)) %>%
    select(Model = model, AIC = aic, `$R^2$` = r_squared)
  
  tex_gam <- kable(gam_df, format = "latex", booktabs = TRUE, escape = FALSE, digits = 3, linesep = "")
  writeLines(tex_gam, "report/tables/tab_gam_aic.tex")
}

# -------------------------------------------------------------------------
# 8. GTS ARDL DE (tab:gts_ardl_de)
# -------------------------------------------------------------------------
if (file.exists("data/ardl_model_comparison_de.csv")) {
  ardl_comp <- read_csv("data/ardl_model_comparison_de.csv", show_col_types = FALSE) %>%
    mutate(
      bg_p_order1 = format_p(bg_p_order1),
      bg_p_order7 = format_p(bg_p_order7),
      short_run_temp = sprintf("%.4f", short_run_temp)
    ) %>%
    select(
      `Model step` = model,
      AIC = aic,
      `BG(1) $p$` = bg_p_order1,
      `BG(7) $p$` = bg_p_order7,
      `SR temp sum` = short_run_temp
    )
  
  tex_ardl_comp <- kable(ardl_comp, format = "latex", booktabs = TRUE, escape = FALSE, digits = 1, linesep = "")
  writeLines(tex_ardl_comp, "report/tables/tab_gts_ardl_de.tex")
}

# -------------------------------------------------------------------------
# 9. ARDL Diagnostics (tab:ardl_diag) and Results (tab:ardl)
# -------------------------------------------------------------------------
if (file.exists("data/ardl_diagnostics_focus.csv")) {
  ardl_diag_full <- read_csv("data/ardl_diagnostics_focus.csv", show_col_types = FALSE)
  
  # Diagnostics Table
  ardl_diag_subset <- ardl_diag_full %>%
    mutate(
      # Format White test using scientific notation if extremely small, else regular
      white_p_formatted = ifelse(white_p < 0.001, sprintf("$%.1f\\times 10^{-%d}$", 
                                                          white_p * 10^ceiling(-log10(white_p)), ceiling(-log10(white_p))), 
                                 format_p(white_p)),
      across(c(bp_p, reset_p, bg_p_order1, bg_p_order7), format_p)
    ) %>%
    select(
      Country = country,
      `BP $p$` = bp_p,
      `White $p$` = white_p_formatted,
      `RESET $p$` = reset_p,
      `BG(1) $p$` = bg_p_order1,
      `BG(7) $p$` = bg_p_order7
    )
  
  tex_ardl_diag <- kable(ardl_diag_subset, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_ardl_diag, "report/tables/tab_ardl_diag.tex")
  
  # Results Table
  ardl_res_subset <- ardl_diag_full %>%
    mutate(
      short_run_temp = sprintf("%.4f", short_run_temp),
      bg_p_order1 = format_p(bg_p_order1),
      bg_p_order7 = format_p(bg_p_order7),
      aic = format_num(aic, 0)
    ) %>%
    select(
      Country = country,
      `Short-run $\\sum \\hat{\\beta}_j$` = short_run_temp,
      `BG(1) $p$` = bg_p_order1,
      `BG(7) $p$` = bg_p_order7,
      AIC = aic
    )
  
  tex_ardl <- kable(ardl_res_subset, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_ardl, "report/tables/tab_ardl.tex")
}

# -------------------------------------------------------------------------
# 10. ARDL vs ARIMA (tab:ardl_arima)
# -------------------------------------------------------------------------
if (file.exists("data/ardl_vs_arima_de.csv")) {
  arima_df <- read_csv("data/ardl_vs_arima_de.csv", show_col_types = FALSE) %>%
    mutate(
      arima_order = replace_na(arima_order, "-"),
      model = ifelse(str_detect(model, "ARIMA"), "ARIMA + weather \\texttt{xreg}", model)
    ) %>%
    select(Model = model, AIC = aic, BIC = bic, `ARIMA order` = arima_order)
  
  tex_arima <- kable(arima_df, format = "latex", booktabs = TRUE, escape = FALSE, digits = 1, linesep = "")
  writeLines(tex_arima, "report/tables/tab_ardl_arima.tex")
}

# -------------------------------------------------------------------------
# 11. Forecast Metrics (tab:forecast)
# -------------------------------------------------------------------------
if (file.exists("data/forecast_metrics_de.csv")) {
  fc_df <- read_csv("data/forecast_metrics_de.csv", show_col_types = FALSE) %>%
    mutate(
      MAE_MW = format_num(MAE_MW, 0),
      RMSE_MW = format_num(RMSE_MW, 0),
      MAPE = sprintf("%.1f\\%%", MAPE * 100),
      model = ifelse(str_detect(model, "ARIMA"), "ARIMA + weather \\texttt{xreg}", model)
    ) %>%
    select(Model = model, `MAE (MW)` = MAE_MW, `RMSE (MW)` = RMSE_MW, MAPE)
  
  tex_fc <- kable(fc_df, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_fc, "report/tables/tab_forecast.tex")
}

# -------------------------------------------------------------------------
# 12. Appendix Country Summary (tab:appendix)
# -------------------------------------------------------------------------
if (file.exists("data/appendix_country_summary.csv")) {
  app_df <- read_csv("data/appendix_country_summary.csv", show_col_types = FALSE) %>%
    mutate(
      mean_temp_c = sprintf("%.1f", mean_temp_c),
      ols_r2 = sprintf("%.3f", ols_r2),
      u_curve_turning_point_c = sprintf("%.1f", u_curve_turning_point_c),
      ardl_short_run_temp = sprintf("%.4f", ardl_short_run_temp),
      ardl_bg_p_order1 = format_p(ardl_bg_p_order1)
    ) %>%
    select(
      Country = country,
      `Mean $T$ ($^\\circ$C)` = mean_temp_c,
      `OLS $R^2$` = ols_r2,
      `Turning pt` = u_curve_turning_point_c,
      `SR temp sum` = ardl_short_run_temp,
      `BG(1) $p$` = ardl_bg_p_order1
    )
  
  tex_app <- kable(app_df, format = "latex", booktabs = TRUE, escape = FALSE, linesep = "")
  writeLines(tex_app, "report/tables/tab_appendix.tex")
}

cat("✅ Successfully generated all LaTeX table fragments in report/tables/\n")