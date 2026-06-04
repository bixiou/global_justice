# ============================================================================
# Inequality Figures — Italy and World
# DCE — Sustainable Development Scenarios Survey
# ============================================================================
# Reads ineq_2100.csv with columns:
#   bracket, IT_PI, IT_PC, IT_SC1, IT_SC2, IT_SC45k, IT_SC30k, IT_SC15k,
#            World_PI, World_PC, World_SC1, World_SC2, World_SC45k, World_SC30k, World_SC15k
# Values: average ANNUAL net income (€, 2025 PPP) — converted to monthly
# Generates 7 Italy figures + 7 World figures = 14 PNG files
# ============================================================================
# Dependencies: ggplot2, patchwork, dplyr
# install.packages(c("ggplot2", "patchwork", "dplyr"))
# ============================================================================

library(ggplot2)
library(patchwork)
library(dplyr)

# ── 1. PATHS ─────────────────────────────────────────────────────────────────

input_dir  <- "/Users/viola/Dropbox/DCE conjoint analysis/data"
output_dir <- "/Users/viola/Dropbox/DCE conjoint analysis/output"

# ── 2. SETTINGS ──────────────────────────────────────────────────────────────

scenarios <- c("PI", "PC", "SC1", "SC2", "SC45k", "SC30k", "SC15k")

# ── 3. BRACKET STRUCTURE ─────────────────────────────────────────────────────

brackets <- c(
  "p0p5","p5p10","p10p15","p15p20","p20p25",
  "p25p30","p30p35","p35p40","p40p45","p45p50",
  "p50p55","p55p60","p60p65","p65p70","p70p75",
  "p75p80","p80p85","p85p90","p90p95","p95p99","p99p100"
)

interval_width <- c(rep(5, 19), 4, 1)

# ── 4. COLOURS ───────────────────────────────────────────────────────────────

col_bottom <- "#2166AC"
col_median <- "#4DAC26"
col_top    <- "#D6604D"
col_other  <- "#D9D9D9"

color_values <- c(
  "bottom10" = col_bottom,
  "median"   = col_median,
  "top10"    = col_top,
  "other"    = col_other
)

# ── 5. LOAD DATA ─────────────────────────────────────────────────────────────

df_input <- read.csv(file.path(input_dir, "ineq_2100.csv"))

# ── 6. PLOT FUNCTION ─────────────────────────────────────────────────────────

plot_inequality <- function(df_input, col_name, title,
                            label_bottom, label_median, label_top) {

  # Extract annual values and convert to monthly
  monthly_income <- df_input[[col_name]] / 12

  # Compute proportional x positions (no gaps)
  norm_factor <- length(brackets) / sum(interval_width)
  bar_width   <- interval_width * norm_factor
  cum_width   <- cumsum(c(0, bar_width[-length(bar_width)]))

  df <- data.frame(
    bracket   = factor(brackets, levels = brackets),
    value     = monthly_income,
    x_pos     = cum_width + bar_width / 2,
    bar_width = bar_width
  )

  df$color_group <- case_when(
    df$bracket %in% c("p0p5","p5p10")              ~ "bottom10",
    df$bracket %in% c("p45p50","p50p55")            ~ "median",
    df$bracket %in% c("p90p95","p95p99","p99p100")  ~ "top10",
    TRUE                                             ~ "other"
  )

  fmt_eur      <- function(x) paste0("€", format(round(x), big.mark = ".", decimal.mark = ","))
  bottom10_val <- mean(df$value[df$bracket %in% c("p0p5","p5p10")])
  median_val   <- mean(df$value[df$bracket %in% c("p45p50","p50p55")])
  top10_val    <- mean(df$value[df$bracket %in% c("p90p95","p95p99","p99p100")])

  # ── Histogram ───────────────────────────────────────────────────────────────
  p_hist <- ggplot(df, aes(x = x_pos, y = value,
                            fill = color_group, width = bar_width)) +
    geom_col(color = NA, linewidth = 0) +
    scale_fill_manual(values = color_values, guide = "none") +
    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.02))) +
    labs(title = title) +
    theme_void() +
    theme(
      plot.title  = element_text(face = "bold", size = 9, color = "#000000",
                                 margin = margin(b = 4), hjust = 0),
      plot.margin = margin(6, 2, 4, 6)
    )

  # ── Sidebar caption ──────────────────────────────────────────────────────────
  caption_df <- data.frame(
    y     = c(0.78, 0.50, 0.22),
    color = c(col_bottom, col_median, col_top),
    label = c(label_bottom, label_median, label_top),
    value = c(fmt_eur(bottom10_val), fmt_eur(median_val), fmt_eur(top10_val))
  )

  p_side <- ggplot() +
    geom_rect(
      data = caption_df,
      aes(xmin = 0.02, xmax = 0.12, ymin = y - 0.09, ymax = y + 0.09,
          fill = color),
      color = NA
    ) +
    scale_fill_identity() +
    geom_text(
      data = caption_df,
      aes(x = 0.18, y = y + 0.03, label = label, color = color),
      hjust = 0, vjust = 0.5, size = 2.8, fontface = "bold"
    ) +
    geom_text(
      data = caption_df,
      aes(x = 0.18, y = y - 0.06, label = value),
      hjust = 0, vjust = 0.5, size = 2.8, color = "#000000"
    ) +
    scale_color_identity() +
    xlim(0, 1) + ylim(0, 1) +
    theme_void() +
    theme(plot.margin = margin(6, 6, 4, 2))

  p_hist + p_side + plot_layout(widths = c(3, 1.4))
}

# ── 7. GENERATE ITALY FIGURES ────────────────────────────────────────────────

for (sc in scenarios) {
  p <- plot_inequality(
    df_input,
    col_name     = paste0("IT_", sc),
    title        = "Redditi mensili italiani del 2100",
    label_bottom = "10% più povero",
    label_median = "Reddito tipico",
    label_top    = "10% più ricco"
  )
  outfile <- file.path(output_dir, paste0("inequality_italy_", sc, ".png"))
  ggsave(outfile, plot = p, width = 5, height = 3, dpi = 150, bg = "white")
  cat("Saved:", outfile, "\n")
}

# ── 8. GENERATE WORLD FIGURES ────────────────────────────────────────────────

for (sc in scenarios) {
  p <- plot_inequality(
    df_input,
    col_name     = paste0("World_", sc),
    title        = "Redditi mensili mondiali del 2100",
    label_bottom = "Paesi a basso reddito",
    label_median = "Paesi a medio reddito",
    label_top    = "Paesi ad alto reddito"
  )
  outfile <- file.path(output_dir, paste0("inequality_world_", sc, ".png"))
  ggsave(outfile, plot = p, width = 5, height = 3, dpi = 150, bg = "white")
  cat("Saved:", outfile, "\n")
}
