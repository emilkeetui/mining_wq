.libPaths("Z:/ek559/RPackages")
# git change
install.packages('fixest')
install.packages('arrow')
install.packages('ggplot2')
install.packages('ISOweek')
install.packages("data.table")
install.packages("dplyr")
install.packages("modelsummary")
install.packages("grid")
install.packages('tinytable')
install.packages('patchwork')
install.packages('grid')
install.packages('estimatr')
install.packages("DIDmultiplegtDYN")
install.packages("ggfixest") 
install.packages("tidyr")
install.packages("magrittr")

library(tidyr)
library(ggfixest)   
library(DIDmultiplegtDYN)
library(patchwork)
library(grid)
library(tinytable)
library(grid)
library(dplyr)
library(fixest)
library(arrow)
library(ggplot2)
library(ISOweek)
library(tidyverse)
library(knitr)
library(kableExtra)
library(modelsummary)
library(lubridate)
library(magrittr)
#library(estimatr)

# story should be summary table of why mine and upstream cant be directly compared
# then why diff and diff doesnt work because of production changes depending on sulfur content 
# show how the trends in violations changes within mine when you account for sulfur 
# ie plot mine violations low sulfur vs mine violations high sulfur
# Then show ddd parallel trends and results

#################################################
# Plotting coal production relationship to sulfur
#################################################
# Sample: mine HUC12s that (1) a downstream-only 2SLS CWS draws water from — identified
# as fromhuc in "downstream_of_mine" rows of prod_sulfur.csv — and (2) had at least one
# active mine in 1985–2005. No exclusion based on whether the HUC12 also has a CWS intake.
prod_s_scatter <- read.csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv", stringsAsFactors = FALSE)
ds_rows_scatter         <- prod_s_scatter[prod_s_scatter$minehuc == "downstream_of_mine" & !is.na(prod_s_scatter$fromhuc), ]
upstream_mine_hucs_scatter <- unique(sprintf("%012.0f", ds_rows_scatter$fromhuc))

huccoal <- arrow::read_parquet("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet")
huccoal <- huccoal[huccoal$huc12 %in% upstream_mine_hucs_scatter &
                   huccoal$year >= 1985 & huccoal$year <= 2005, ]

# Keep only HUC12s with at least one active mine year in 1985–2005
active_scatter_hucs <- huccoal %>%
  group_by(huc12) %>%
  summarise(max_mines = max(num_coal_mines_colocated, na.rm = TRUE)) %>%
  filter(max_mines > 0) %>%
  pull(huc12)
huccoal <- huccoal[huccoal$huc12 %in% active_scatter_hucs, ]
cat("Scatter sample — upstream mine HUC12s with >= 1 mine year:", length(active_scatter_hucs), "\n")
cat("Scatter sample rows:", nrow(huccoal), "\n")

# Left plot: before 1995
p_before <- huccoal %>%
  filter(year < 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
  geom_point(alpha = 0.4, size = 1.5, color = "steelblue") +
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.9) +
  labs(
    title = "Before 1995",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw()

# Right plot: 1995 and after
p_after <- huccoal %>%
  filter(year >= 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
  geom_point(alpha = 0.4, size = 1.5, color = "steelblue") +
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.9) +
  labs(
    title = "1995 and After",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw()

(p_before + p_after) +
  plot_annotation(
    title   = "HUC12 sulfur (%) vs. number of coal mines",
    caption = "Sample: mine HUC12s upstream of downstream-only 2SLS CWS intakes, no CWS intake, >= 1 active mine year 1985-2005."
  )

ggsave("Z:/ek559/mining_wq/output/fig/scatterhuccoalsulfur.png", width = 8, height = 5, dpi = 500)


########################
# CWS data and analysis
########################
full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")

### PRIOR TO 2006 and AFTER 1985
full <- full[full$year<2006 & full$year>1984,]
full <- full[full$PWSID!="WV3303401",]

############################
# How sulfur varies by PWSID
############################
# mean sulfur a PWSID experiences is based on which 
# HUCs a PWS draws water from which is based on which
# intakes are active. Over the period from 1985 until 2005
# only one PWSID in the only colocated subset experience a 
# closing facility that leads to a change in which HUCs
# the system draws water from. It is PWSID=WV3303401.
# For now we drop that one PWSID

sulfur_variation <- full %>%
  group_by(PWSID) %>%
  summarise(
    n_distinct_sulfur = n_distinct(sulfur_unified),
    sd_sulfur         = sd(sulfur_unified, na.rm = TRUE),
    min_sulfur        = min(sulfur_unified, na.rm = TRUE),
    max_sulfur        = max(sulfur_unified, na.rm = TRUE),
    range_sulfur      = max_sulfur - min_sulfur,
    n_years           = n_distinct(year)
  ) %>%
  filter(n_distinct_sulfur > 1) %>%
  arrange(desc(range_sulfur))

cat("PWSIDs with time-varying sulfur_unified:", nrow(sulfur_variation), "\n")
print(sulfur_variation)
full <- full[full$PWSID!="WV3303401",]

###########################
### Histogram of violations
###########################
histogram_of_violation_length <- function(df, vars_to_plot, nice_labels, plottitle, outpath){
### Histogram of violations
# Reshape to long format and keep only values > 0
plot_df <- df %>%
  select(all_of(vars_to_plot)) %>%
  pivot_longer(cols = everything(), names_to = "variable", values_to = "value") %>%
  filter(!is.na(value), value > 0)

# Plot histograms in a 2x2 grid
ggplot(plot_df, aes(x = value)) +
  geom_histogram(color = "white", fill = "#2C7FB8", bins = 30, boundary = 0) +
  facet_wrap(~ variable, scales = "free_x", labeller = as_labeller(nice_labels), ncol = 2) +
    scale_x_continuous(
    breaks = function(x) seq(0, max(x), by = 50)) +
  labs(
    x = "Days of the Year",
    y = "Count",
    title = plottitle
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

ggsave(outpath, width = 8, height = 6, dpi = 300)
}

histogram_of_violation_length(full,
c("radionuclides_share_days",
  "inorganic_chemicals_share_days",
  "arsenic_share_days",
  "nitrates_share_days"),
c(radionuclides_share_days    = "Radionuclides",
  inorganic_chemicals_share_days = "Inorganic chemicals",
  arsenic_share_days          = "Arsenic",
  nitrates_share_days         = "Nitrates"),
  "Histograms of Days in Violation",
"Z:/ek559/mining_wq/output/fig/mineviolengthhist.png")

histogram_of_violation_length(full,
c("voc_share_days","soc_share_days","surface_ground_water_rule_share_days","total_coliform_share_days"),
c(voc_share_days    = "VOC",
  soc_share_days = "SOC",
  surface_ground_water_rule_share_days          = "S/G Water Rule",
  total_coliform_share_days         = "Total Coliforms"),
  "Histograms of Days in Violation",
"Z:/ek559/mining_wq/output/fig/nonmineviolengthhist.png")

##################################
# Day of the year violation starts
##################################

violation <- read.csv("Z:/ek559/mining_wq/clean_data/cws_data/violation.csv")
violation %<>% mutate(NON_COMPL_PER_BEGIN_DATE= as.Date(NON_COMPL_PER_BEGIN_DATE, format= "%Y-%m-%d"))
violation %<>% mutate(NON_COMPL_PER_END_DATE= as.Date(NON_COMPL_PER_END_DATE, format= "%Y-%m-%d"))
violation$dayofyearviostart <- yday(violation$NON_COMPL_PER_BEGIN_DATE)
violation$dayofyearvioend <- yday(violation$NON_COMPL_PER_END_DATE)

histogram_of_violation_length(
violation[1985<=violation$year & violation$year<=2005,],
c("dayofyearviostart","dayofyearvioend"),
c(dayofyearviostart    = "Violation start day",
  dayofyearvioend = "Violation end day"),
"Day of the year violations begin and end",
"Z:/ek559/mining_wq/output/fig/dayvioendstarthist.png")

#####################
# Violation trends
#####################

stackmineviobytreat <- function(varlist, dset, plot_title, vartitle, numcol, groupvar, outname, legndnrow = 2, legndncol = 2, morethantwolegndobj =FALSE){
    # stacks a list of violations within minehucs but each line is low sulfur vs high

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        df <- dset %>%
                group_by(.data[[groupvar]], year) %>%
                summarise(val = mean(.data[[varlist[i]]], na.rm = TRUE),
                        .groups="drop")

        plot = ggplot(df, aes(x=year, y=val, color= .data[[groupvar]])) +
            geom_line() +
            labs(title = vartitle[i], y = "Mean days", x = "Year") +
        theme_minimal() +
        theme(legend.position = "none") +
        scale_x_continuous(breaks = c(1985, 1990, 1995, 2000, 2005))

        plotlist[[varname]] <- plot

    }
    # Combine the plots
    if (isTRUE(morethantwolegndobj)){
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")  &
    guides(color = guide_legend(nrow = legndnrow, ncol = legndncol))
    }
    else{
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")
    }
    ggsave(outname, combined_plot, height = 5, width = 5)
}

full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine ==1 ] <- "Upstream of mining"
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine ==0 ] <- "Colocated/Downstream of mining"

stackmineviobytreat(c("nitrates_share_days",
                        "arsenic_share_days",
                        "inorganic_chemicals_share_days",
                        "radionuclides_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "minehuc_upstream_of_mine",
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_mining_viol_raw_line1985to2005.png")

stackmineviobytreat(c("voc_share_days",
                        "soc_share_days",
                        "surface_ground_water_rule_share_days",
                        "total_coliform_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Volatile Organic Chemicals",
                        "Synthetic Organic Chemicals",
                        "Surface/Ground Water Rule",
                        "Total Coliforms"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_nonmining_viol_raw_line1985to2005.png")

# high sulfur
full$HighSulfur <- ifelse(full$sulfur_colocated > 1.5,
                          "High sulfur",
                          "Low sulfur")

stackmineviobytreat(c("nitrates_share_days",
                        "arsenic_share_days",
                        "inorganic_chemicals_share_days",
                        "radionuclides_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      'HighSulfur',
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_mining_viol_raw_line1985to2005_sulfur.png")

stackmineviobytreat(c("voc_share_days",
                        "soc_share_days",
                        "surface_ground_water_rule_share_days",
                        "total_coliform_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Volatile Organic Chemicals",
                        "Synthetic Organic Chemicals",
                        "Surface/Ground Water Rule",
                        "Total Coliforms"),
                      2,
                      'HighSulfur',
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_nonmining_viol_raw_line1985to2005_sulfur.png")

# high-sulfur upstream/low-sulfur upstream 
# high-sulfur downstream-colocated/low-sulfur downstream-colocated

full$sulfur_location <- "High sulfur upstream"
full$sulfur_location[(full$minehuc_upstream_of_mine == 1) & (full$HighSulfur == "Low sulfur")] <- "Low sulfur upstream"
full$sulfur_location[(full$minehuc_upstream_of_mine == 0) & (full$HighSulfur == "High sulfur")] <- "High sulfur downstream/colocated"
full$sulfur_location[(full$minehuc_upstream_of_mine == 0) & (full$HighSulfur == "Low sulfur")] <- "Low sulfur downstream/colocated"

stackmineviobytreat(c("nitrates_share_days",
                        "arsenic_share_days",
                        "inorganic_chemicals_share_days",
                        "radionuclides_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/mining_viol_mean_line1985to2005_sulfur_location.png",
                      morethantwolegndobj = TRUE)

stackmineviobytreat(c("voc_share_days",
                        "soc_share_days",
                        "surface_ground_water_rule_share_days",
                        "total_coliform_share_days"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Volatile Organic Chemicals",
                        "Synthetic Organic Chemicals",
                        "Surface/Ground Water Rule",
                        "Total Coliforms"),
                        2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/non_mining_viol_mean_line1985to2005_sulfur_location.png",
                      morethantwolegndobj = TRUE)

stackmineviobytreat(c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Number of violations in a year PWSs"), 
                      c("Total",
                        "Mining related",
                        "Non-mining related"),
                        2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/number_vio_mean_line1985to2005_sulfur_location.png",
                      morethantwolegndobj = TRUE)

# high-sulfur colocated/low-sulfur colocated 
# high-sulfur downstream/low-sulfur downstream

full$sulfur_location <- "High sulfur downstream"
full$sulfur_location[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) & (full$HighSulfur == "Low sulfur")] <- "Low sulfur downstream"
full$sulfur_location[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) & (full$HighSulfur == "High sulfur")] <- "High sulfur colocated"
full$sulfur_location[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) & (full$HighSulfur == "Low sulfur")] <- "Low sulfur colocated"

stackmineviobytreat(c("nitrates_share_days",
                        "arsenic_share_days",
                        "inorganic_chemicals_share_days",
                        "radionuclides_share_days"), 
                      full[full$minehuc_upstream_of_mine == 0 & full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/mining_viol_mean_line1985to2005_dwnstreamcolocatedsulfur.png",
                      morethantwolegndobj = TRUE)

stackmineviobytreat(c("voc_share_days",
                        "soc_share_days",
                        "surface_ground_water_rule_share_days",
                        "total_coliform_share_days"), 
                      full[full$minehuc_upstream_of_mine == 0 & full$year>1984 & full$year<2006,], 
                      c("Days of the year PWSs spent in violation"), 
                      c("Volatile Organic Chemicals",
                        "Synthetic Organic Chemicals",
                        "Surface/Ground Water Rule",
                        "Total Coliforms"),
                        2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/non_mining_viol_mean_line1985to2005_dwnstreamcolocatedsulfur.png",
                      morethantwolegndobj = TRUE)

stackmineviobytreat(c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"), 
                      full[full$minehuc_upstream_of_mine == 0 & full$year>1984 & full$year<2006,], 
                      c("Number of violations in a year PWSs"), 
                      c("Total",
                        "Mining related",
                        "Non-mining related"),
                        2,
                      "sulfur_location",
                      "Z:/ek559/mining_wq/output/fig/number_vio_mean_line1985to2005_dwnstreamcolocatedsulfur.png",
                      morethantwolegndobj = TRUE)

###################
# Summary Tables
###################

# HUC and PWS characteristiscs

full$pws_deactivated <- "N"
full$pws_deactivated[full$year_pws_deactivated<2006] <- "Y"

pwssum <- full

pwssum$minehuc_upstream_of_mine[pwssum$minehuc_upstream_of_mine==1] <- "Upstream"
pwssum$minehuc_upstream_of_mine[pwssum$minehuc_upstream_of_mine==0] <- "Mine/Downstream"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="F"] <- "Fed govt"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="L"] <- "Loc govt"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="M"] <- "Pub/pvt"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="N"] <- "Native"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="P"] <- "Pvt"
pwssum$OWNER_TYPE_CODE[pwssum$OWNER_TYPE_CODE=="S"] <- "State govt"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="GW"] <- "Ground water (GW)"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="GWP"] <- "GW purchased"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="SW"] <- "Surface water (SW)"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="SWP"] <- "SW purchased"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="GU"] <- "GW influenced by SW"
pwssum$PRIMARY_SOURCE_CODE[pwssum$PRIMARY_SOURCE_CODE=="GUP"] <- "Bought GW influenced by SW"
pwssum$FILTRATION_STATUS_CODE_FIL[pwssum$FILTRATION_STATUS_CODE_FIL==1]<-"Y"
pwssum$FILTRATION_STATUS_CODE_FIL[pwssum$FILTRATION_STATUS_CODE_FIL==0]<-"N"
pwssum$FILTRATION_STATUS_CODE_MIF[pwssum$FILTRATION_STATUS_CODE_MIF==1]<-"Y"
pwssum$FILTRATION_STATUS_CODE_MIF[pwssum$FILTRATION_STATUS_CODE_MIF==0]<-"N"
pwssum$FILTRATION_STATUS_CODE_SAF[pwssum$FILTRATION_STATUS_CODE_SAF==1]<-"Y"
pwssum$FILTRATION_STATUS_CODE_SAF[pwssum$FILTRATION_STATUS_CODE_SAF==0]<-"N"
pwssum$SOURCE_WATER_PROTECTION_CODE_Y[pwssum$SOURCE_WATER_PROTECTION_CODE_Y==1]<-"Y"
pwssum$SOURCE_WATER_PROTECTION_CODE_Y[pwssum$SOURCE_WATER_PROTECTION_CODE_Y==0]<-"N"
pwssum$IS_SOURCE_TREATED_IND_Y[pwssum$IS_SOURCE_TREATED_IND_Y==0] <-"N"
pwssum$IS_SOURCE_TREATED_IND_Y[pwssum$IS_SOURCE_TREATED_IND_Y==1] <-"Y"

pwssum[['water source use']] <- 'NA'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_E']]==1]<-'Emergency'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_O']]==1]<-'Other'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_I']]==1]<-'Interim'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_P']]==1]<-'Permanent'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_S']]==1]<-'Seasonal'
pwssum[['water source use']][pwssum[['AVAILABILITY_CODE_nan']]==1]<-'NA'

pwssum <- pwssum %>%
  rename("Avoiding filtration" = FILTRATION_STATUS_CODE_SAF,
         "Need filtration" = FILTRATION_STATUS_CODE_MIF,
         "Filtration in place" = FILTRATION_STATUS_CODE_FIL,
         "Wholesaler"= IS_WHOLESALER_IND,
         "PWS N Source HUC12" = num_hucs,
         "HUC12 N coal mine upstream"=num_coal_mines_upstream,
         "HUC12 N coal mine colocated"=num_coal_mines_colocated,
         "HUC12 coal tons upstream"=production_short_tons_coal_upstream,
         "HUC12 coal tons colocated"=production_short_tons_coal_colocated,
         "HUC12 avg coal BTU upstream"=btu_upstream,
         "HUC12 avg coal BTU colocated"=btu_colocated,
         "HUC12 avg coal sulfur upstream"=sulfur_upstream,
         "HUC12 avg coal sulfur colocated"=sulfur_colocated,
         "Source protected"=SOURCE_WATER_PROTECTION_CODE_Y,
         "Source treated"=IS_SOURCE_TREATED_IND_Y,
         "Population served"=POPULATION_SERVED_COUNT,
         "PWS owner" = OWNER_TYPE_CODE,
         "PWS deactivated"=pws_deactivated,
         "Primary water source" = PRIMARY_SOURCE_CODE,
         "Grant eligible"=IS_GRANT_ELIGIBLE_IND)

# sum table 1 part 1

datasummary_balance(~minehuc_upstream_of_mine,
                    data = pwssum[, c("minehuc_upstream_of_mine",
                                      "water source use",
                                      "Filtration in place",
                                      "Source treated",
                                      "Primary water source")],
                    title = "PWS source features summary statistics",
                    notes = c("NA is missing data. Water source use refers to the upstream/mine/downstream HUC12 source use."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pwssource.tex", overwrite = TRUE)

# sum table 1 part 2
datasummary_balance(~minehuc_upstream_of_mine,
                    data = pwssum[,c("minehuc_upstream_of_mine", 
                                     "HUC12 N coal mine colocated",
                                     "HUC12 coal tons colocated",
                                     "HUC12 avg coal BTU colocated",
                                     "HUC12 avg coal sulfur colocated")],
                    title = "PWS HUC12 source summary statistics",
                    notes = c("Upstream coal production is 0 by construction."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_hucfeatures.tex", overwrite = TRUE)

# sum table 1 part 3
datasummary_balance(~minehuc_upstream_of_mine,
                    data = pwssum[,c("minehuc_upstream_of_mine",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Wholesaler", 
                                     "Grant eligible", 
                                     "PWS N Source HUC12",
                                     "Population served")],
                    title = "PWS summary statistics",
                    notes = c("NA is missing data."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pws.tex", overwrite = TRUE)

# violation summary
pwssum$VIOLATION_CATEGORY <- " No violation"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MCL==1] <- "MCL"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MON==1] <- "MON"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MR==1] <- "MR"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_Other==1] <- "OTHER"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_RPT==1] <- "RPT"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_TT==1] <- "TT"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MCL==1] <- "MCL"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_nan==1] <- "NA"

pwssum <- pwssum %>%
  rename("Volatile Organic Chemicals"="voc_share_days",
         "Synthetic Organic Chemicals"="soc_share_days",
         "Surface/Ground Water Rule"="surface_ground_water_rule_share_days",
         "Total Coliform"="total_coliform_share_days",
         "Radionuclides"="radionuclides_share_days",
         "Inorganic chemicals"="inorganic_chemicals_share_days",
         "Arsenic"="arsenic_share_days",
         "Nitrates"="nitrates_share_days")

datasummary_balance(~minehuc_upstream_of_mine,
                    data = pwssum[,c("minehuc_upstream_of_mine",
                                     "VIOLATION_CATEGORY")],
                    title = "PWS Violations by Category",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_viol_category.tex", overwrite = TRUE)

datasummary_balance(~minehuc_upstream_of_mine,
                    data = pwssum[, c("minehuc_upstream_of_mine",
                                     "Total Coliform",
                                     "Surface/Ground Water Rule",
                                     "Volatile Organic Chemicals",
                                     "Synthetic Organic Chemicals",
                                     "Radionuclides",
                                     "Inorganic chemicals",
                                     "Arsenic",
                                     "Nitrates")],
                    title = "Mean Number of Days in a Year with Violation Type",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_viol_rule.tex", overwrite = TRUE)

###################################################################
# summary tables of high sulfur downstream vs low sulfur downstream
###################################################################


downstream <- pwssum
downstream <- downstream[downstream$sulfur_location == "Low sulfur downstream" | downstream$sulfur_location == "High sulfur downstream", ]

histogram_of_violation_length(full[full$PWSID %in% unique(downstream$PWSID), ],
c("radionuclides_share_days",
  "inorganic_chemicals_share_days",
  "arsenic_share_days",
  "nitrates_share_days"),
c(radionuclides_share_days    = "Radionuclides",
  inorganic_chemicals_share_days = "Inorganic chemicals",
  arsenic_share_days          = "Arsenic",
  nitrates_share_days         = "Nitrates"),
  "Histograms of Days in Violation for Downstream CWS",
"Z:/ek559/mining_wq/output/fig/mineviolengthhist_downstream.png")

histogram_of_violation_length(full[full$PWSID %in% unique(downstream$PWSID), ],
c("voc_share_days","soc_share_days","surface_ground_water_rule_share_days","total_coliform_share_days"),
c(voc_share_days    = "VOC",
  soc_share_days = "SOC",
  surface_ground_water_rule_share_days          = "S/G Water Rule",
  total_coliform_share_days         = "Total Coliforms"),
  "Histograms of Days in Violation for Downstream CWS",
"Z:/ek559/mining_wq/output/fig/nonmineviolengthhist_downstream.png")

violation <- read.csv("Z:/ek559/mining_wq/clean_data/cws_data/violation.csv")
violation <- violation[violation$PWSID %in% unique(downstream$PWSID), ]
violation %<>% mutate(NON_COMPL_PER_BEGIN_DATE= as.Date(NON_COMPL_PER_BEGIN_DATE, format= "%Y-%m-%d"))
violation %<>% mutate(NON_COMPL_PER_END_DATE= as.Date(NON_COMPL_PER_END_DATE, format= "%Y-%m-%d"))
violation$dayofyearviostart <- yday(violation$NON_COMPL_PER_BEGIN_DATE)
violation$dayofyearvioend <- yday(violation$NON_COMPL_PER_END_DATE)

histogram_of_violation_length(
violation[1985<=violation$year & violation$year<=2005,],
c("dayofyearviostart","dayofyearvioend"),
c(dayofyearviostart    = "Violation start day",
  dayofyearvioend = "Violation end day"),
"Day of the year violations begin and end",
"Z:/ek559/mining_wq/output/fig/dayvioendstarthist_downstream.png")

# downstream-sulfur sum part 1

datasummary_balance(~sulfur_location,
                    data = downstream[, c("sulfur_location",
                                      "water source use",
                                      "Filtration in place",
                                      "Source treated",
                                      "Primary water source")],
                    title = "CWS source features summary statistics",
                    notes = c("NA is missing data."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_downstream.tex", overwrite = TRUE)

# downstream-sulfur sum part 2
datasummary_balance(~sulfur_location,
                    data = downstream[,c("sulfur_location", 
                                     "HUC12 N coal mine upstream",
                                     "HUC12 coal tons upstream",
                                     "HUC12 avg coal BTU upstream",
                                     "HUC12 avg coal sulfur upstream")],
                    title = "CWS HUC12 source summary statistics",
                    notes = c("All CWS's are downstream of coal production and have no co-located coal production in intake HUC."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_hucfeatures_downstream.tex", overwrite = TRUE)

# sum table 1 part 3
datasummary_balance(~sulfur_location,
                    data = downstream[,c("sulfur_location",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Wholesaler", 
                                     "Grant eligible", 
                                     "PWS N Source HUC12",
                                     "Population served")],
                    title = "CWS summary statistics",
                    notes = c("NA is missing data."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pws_downstream.tex", overwrite = TRUE)

datasummary_balance(~sulfur_location,
                    data = downstream[,c("sulfur_location",
                                     "VIOLATION_CATEGORY")],
                    title = "CWS Violations by Category",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_viol_category_downstream.tex", overwrite = TRUE)

datasummary_balance(~sulfur_location,
                    data = downstream[, c("sulfur_location",
                                     "Total Coliform",
                                     "Surface/Ground Water Rule",
                                     "Volatile Organic Chemicals",
                                     "Synthetic Organic Chemicals",
                                     "Radionuclides",
                                     "Inorganic chemicals",
                                     "Arsenic",
                                     "Nitrates")],
                    title = "Mean Number of Days in a Year with Violation Type",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_viol_rule_downstream.tex", overwrite = TRUE)


# Balance panel
# 16 rows between 1985 and 2005
full <- full %>%
  group_by(PWSID) %>%
  mutate(total_pwsid_obs = n())
full <- full[full$total_pwsid_obs==21,]

# specific mining violations
full[["nitrates"]] <- 0
full[["nitrates"]][full$RULE_CODE_331.0==1] <- 1

full[["arsenic"]] <- 0
full[["arsenic"]][full$RULE_CODE_332.0==1] <- 1

full[["inorganic_chemicals"]] <- 0
full[["inorganic_chemicals"]][full$RULE_CODE_333.0==1] <- 1

full[["radionuclides"]] <- 0
full[["radionuclides"]][full$RULE_CODE_340.0==1] <- 1

full[["lead_copper_rule"]] <- 0
full[["lead_copper_rule"]][full$RULE_CODE_350.0==1] <- 1

# non mining violations
full[["total_coliform"]] <- 0
full[["total_coliform"]][full$RULE_CODE_110.0==1 | full$RULE_CODE_111.0==1] <- 1

full[["surface_ground_water_rule"]] <- 0
full[["surface_ground_water_rule"]][full$RULE_CODE_121.0==1 | full$RULE_CODE_140.0==1 | full$RULE_CODE_122.0==1 | full$RULE_CODE_123.0==1] <- 1

full[["dbpr"]] <- 0
full[["dbpr"]][full$RULE_CODE_210.0==1 | full$RULE_CODE_220.0==1 | full$RULE_CODE_230.0==1] <- 1

full[["voc"]] <- 0
full[["voc"]][full$RULE_CODE_310.0==1] <- 1

full[["soc"]] <- 0
full[["soc"]][full$RULE_CODE_320.0==1] <- 1

# Pre-rule years: set binary indicators to NA based on first recorded violations in SDWIS
full$total_coliform[full$year < 1991] <- NA
full$voc[full$year < 1990] <- NA
full$soc[full$year < 1987] <- NA
full$surface_ground_water_rule[full$year < 1990] <- NA

##############
# Num mine treat diff in diff
##############

stackddnummineheteventstudy <- function(varlist,
                                        dset, 
                                        plot_title, 
                                        plot_subtitle, 
                                        vartitle, 
                                        numcol, 
                                        footnote, 
                                        outname, 
                                        tablepath,
                                        tablelabel){
    # stacks a list of violations within minehucs but each line is low sulfur vs high

    plotlist <- list()

    outdf <- data.frame(
      "Violation name" = numeric(),
      "P-value placebo joint nullity" = numeric(),
      "P-value effects joint nullity" = numeric(),
      "Normalized ATE" = numeric(),
      "Normalized ATE SE" = numeric(),
      "Normalized ATE LB CI" = numeric(),
      "Normalized ATE UB CI" = numeric(),
      check.names = FALSE)

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        tempestdset <- dset[dset[[varname]] == 1 | dset$no_violation == 1, ]
        tempddhet <-did_multiplegt_dyn(df = tempestdset, 
                    outcome = varname, 
                    group = "PWSID", 
                    time = "year", 
                    treatment = "num_coal_mines",
                    cluster = "PWSID",
                    effects = 10, 
                    placebo = 6)
        print(tempddhet)
        
        # assign table values to out table

        tempdf <- data.frame(
        "Violation name" = vartitle[i],
        "P-value placebo joint nullity" = tempddhet$results$p_jointplacebo,
        "P-value effects joint nullity" = tempddhet$results$p_jointeffects,
        "Normalized ATE" = tempddhet$results$ATE[1, c("Estimate")],
        "Normalized ATE SE" = tempddhet$results$ATE[1, c("SE")],
        "Normalized ATE LB CI" = tempddhet$results$ATE[1,c("LB CI")],
        "Normalized ATE UB CI" = tempddhet$results$ATE[1,c("UB CI")],
        check.names = FALSE)

        outdf <- rbind(outdf, tempdf)

        # Assign the plot to new object (to avoid writing its full path every time)
        plt <- tempddhet$plot

        plt$layers[[1]] <- NULL # drop the line
        plt <- plt + geom_hline(yintercept = 0, linetype = "dashed", color = "black") +  # Add the reference line
                geom_vline(xintercept = 0, linetype = "dashed", color = "blue") +  # Vertical reference line
            theme(plot.title = element_text(hjust = 0.5), panel.grid.major = element_blank(), # Clean the background
                panel.grid.minor = element_blank(), panel.background = element_blank(), 
                axis.line = element_line(colour = "black")
            ) + scale_x_continuous(breaks=c(-4,-2,0,2,4,6,8,10))+
            ylab("Likelihood") + xlab("Time to treat")+ggtitle(vartitle[i]) # Add titles    

        plotlist[[varname]] <- plt

    }

    # Combine the plots
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title   = plot_title,
                    subtitle = plot_subtitle,
                    caption = footnote) +
    plot_layout(guides = "collect") &
    theme(legend.position = "bottom",
          plot.caption.position = "plot",        # puts caption below the entire patchwork
          plot.caption = element_text(size = 9, color = "gray30", hjust = 0))

    ggsave(outname, combined_plot, height = 5, width = 5)

    # output the sum table
    latex_table <- kableExtra::kbl(outdf,
                               format = "latex",
                               booktabs = TRUE,
                               caption = plot_title,
                               digits = 4,
                               label = tablelabel) %>%
      kableExtra::kable_paper("striped", full_width = FALSE)

    sink(tablepath)
    cat(
        latex_table %>% kableExtra::kable_styling(latex_options = "scale_down") %>%
        kableExtra::add_footnote(plot_subtitle, notation = "number")
    )
    sink()
    print(latex_table)
}

stackddnummineheteventstudy(c("nitrates_share",
                        "arsenic_share",
                        "inorganic_chemicals_share",
                        "radionuclides_share"), 
                      full[full$year>1984 & full$year<2006,], 
                      "Likelihood of any violation post coal mine open",
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: SEs clustered at PWSID level. Binary dependent variable if system\nhad current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/nummine_hetdd_mine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/nummine_hetdd_mine_vio_1985to2005.tex",
                      "tab:nummine_hetdd_mine_vio_1985to2005")

stackddnummineheteventstudy(c("total_coliform_share",
                        "surface_ground_water_rule_share",
                        "voc_share",
                        "soc_share"),
                      full[full$year>1984 & full$year<2006,], 
                      "Likelihood of any violation post coal mine open", 
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: SEs clustered at PWSID level. Binary dependent variable if system\nhad current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/nummine_hetdd_nonmine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/nummine_hetdd_nonmine_vio_1985to2005.tex",
                      "tab:nummine_hetdd_nonmine_vio_1985to2005")

#######################################
### Seperate mine openings and closings
#######################################

onlymineopenorclosedf <- function(df, increase) {
    # creates a dataset consisting of upstream PWSs
    # and either only places that had a coal mine open
    # or places that had a coal mine closed.
    # To make an opening dataset set increase=1
    # df is the dataset called full
  df <- df %>%
    mutate(
      num_coal_mines = as.numeric(num_coal_mines)
    ) %>%
    arrange(PWSID, year) %>%
    group_by(PWSID) %>%
    mutate(
      change = dplyr::lead(num_coal_mines) - num_coal_mines
    )

  if (increase == 1) {
    # Drop observations AFTER the first negative change
    df <- df %>%
    arrange(PWSID, year) %>%          # ensure time order within unit
    group_by(PWSID) %>%
    mutate(
        post_cut = cumany(change < 0),
        # keep rows strictly BEFORE the first negative change
        keep = !lag(post_cut, default = FALSE)
    ) %>%
    filter(keep) %>%
    ungroup() %>%
    select(-post_cut, -keep)

  } else {
    # Drop observations AFTER the first positive change
    df <- df %>%
    arrange(PWSID, year) %>%          # ensure time order within unit
    group_by(PWSID) %>%
    mutate(
        post_cut = cumany(change > 0),
        # keep rows strictly BEFORE the first negative change
        keep = !lag(post_cut, default = FALSE)
    ) %>%
    filter(keep) %>%
    ungroup() %>%
    select(-post_cut, -keep)
  }

  return(df)
}

### mining violations after closures
df <- onlymineopenorclosedf(full, increase=0)

stackddnummineheteventstudy(c("nitrates_share",
                        "arsenic_share",
                        "inorganic_chemicals_share",
                        "radionuclides_share"), 
                      df, 
                      "Likelihood of any violation: only coal mine closure",
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: Only observations with mine closures are included. SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/mineclose_hetdd_mine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/mineclose_hetdd_mine_vio_1985to2005.tex",
                      "tab:mineclose_hetdd_mine_vio_1985to2005")

stackddnummineheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                      df, 
                      "Likelihood of any violation: only coal mine closure", 
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: Only observations with mine closures are included. SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/mineclose_hetdd_nonmine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/mineclose_hetdd_nonmine_vio_1985to2005.tex",
                      "tab:mineclose_hetdd_nonmine_vio_1985to2005")

### mining violations after opening
df <- onlymineopenorclosedf(full, increase=1)

stackddnummineheteventstudy(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      df, 
                      "Likelihood of any violation: only coal mine open",
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: Only observations with mine openings are included. SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/mineopen_hetdd_mine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/mineopen_hetdd_mine_vio_1985to2005.tex",
                      "tab:mineopen_hetdd_mine_vio_1985to2005")

stackddnummineheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                      df, 
                      "Likelihood of any violation: only coal mine open", 
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: Only observations with mine openings are included. SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/mineopen_hetdd_nonmine_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/mineopen_hetdd_nonmine_vio_1985to2005.tex",
                      "tab:mineopen_hetdd_nonmine_vio_1985to2005")

################################################
### Mine openings and closings by MCL violations
################################################

stackddnummineheteventstudy(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[full$VIOLATION_CATEGORY_CODE_MCL == 1 | full$no_violation==1,], 
                      "Likelihood of MCL violation post coal mine open",
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: SEs clustered at PWSID level. Binary dependent variable if system\nhad current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/nummine_hetdd_mine_mcl_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/nummine_hetdd_mine_mcl_vio_1985to2005.tex",
                      "tab:nummine_hetdd_mine_mcl_vio_1985to2005")

stackddnummineheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                      full[full$VIOLATION_CATEGORY_CODE_MCL == 1 | full$no_violation==1,], 
                      "Likelihood of MCL violation post coal mine open", 
                      "Non-normalized event-study (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: SEs clustered at PWSID level. Binary dependent variable if system\nhad current violation type = 1, and 0 if no violation.\nData is from 1985-2005.",
                      "Z:/ek559/mining_wq/output/fig/nummine_hetdd_nonmine_mcl_vio_1985to2005.png",
                      "Z:/ek559/mining_wq/output/reg/nummine_hetdd_nonmine_mcl_vio_1985to2005.tex",
                      "tab:nummine_hetdd_nonmine_mcl_vio_1985to2005")

################################################
### 2SLS regression
################################################
# ── Modified tsls_reg_output ────────────────────────────────────────────────

tsls_reg_output <- function(dset, varlist, coalvar, regoutname, title, label,
                             instr_str, storage_list_name = NULL,
                             subheader = NULL, fulldset = 1) {

  controls             <- c("num_facilities")
  drop_controls_exact  <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe                   <- "PWSID + STATE_CODE + year"
  controls_str         <- paste(controls, collapse = " + ")
  fe_str               <- fe

  get_data_subset <- function(outcome) {
    if (fulldset == 0) {
      dset[(dset[[outcome]] > 0) | (dset$no_violation == 1), , drop = FALSE]
    } else {
      dset
    }
  }

  result <- list()

  for (y in varlist) {
    dat_y <- get_data_subset(y)

    f_ols <- as.formula(
      paste0(y, " ~ ", paste(c(paste(coalvar, collapse = "+"), controls_str),
                              collapse = " + "), " | ", fe_str)
    )
    f_rf <- as.formula(
      paste0(y, " ~ ", paste(c(instr_str, controls_str), collapse = " + "),
             " | ", fe_str)
    )
    f_iv <- as.formula(
      paste0(y, " ~ ", controls_str,
             " | ", fe_str,
             " | ", paste(coalvar, collapse = "+"), " ~ ", instr_str)
    )
    print(f_rf)
    print(f_iv)

    mod_ols <- fixest::feols(f_ols, data = dat_y, cluster = ~ PWSID)
    mod_rf  <- fixest::feols(f_rf,  data = dat_y, cluster = ~ PWSID)
    mod_iv  <- fixest::feols(f_iv,  data = dat_y, cluster = ~ PWSID)
    print(summary(mod_rf))
    print(summary(mod_iv, stage = 2))
    print(mod_iv$fixef_removed)

    result[[y]] <- list(OLS = mod_ols, RF = mod_rf, IV = mod_iv)
  }

  # ── Persist first stages to global list ──────────────────────────────────
  if (!is.null(storage_list_name) && !is.null(subheader)) {

    # Create the list in .GlobalEnv if it doesn't exist yet
    if (!exists(storage_list_name, envir = .GlobalEnv)) {
      assign(storage_list_name, list(), envir = .GlobalEnv)
    }

    fs_list <- get(storage_list_name, envir = .GlobalEnv)

    # Initialise this subheader bucket if needed
    if (is.null(fs_list[[subheader]])) {
      fs_list[[subheader]] <- list()
    }

    # Store the first stage for every outcome; key = outcome depvar name
    # iv_first_stage is a named list of feols objects, one per endogenous var
    for (y in varlist) {
      for (cv in coalvar) {
        fs_list[[subheader]][[y]][[cv]] <- result[[y]]$IV$iv_first_stage[[cv]]
      }
    }

    assign(storage_list_name, fs_list, envir = .GlobalEnv)
  }

  # ── Main etable output (unchanged) ───────────────────────────────────────
  model_list <- unlist(
    lapply(varlist, function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )

  do.call(etable, c(
    model_list,
    list(
      fitstat   = ~ . + ivf1,
      style.tex = style.tex("aer", adjustbox = TRUE),
      tex       = TRUE,
      drop      = drop_controls_exact,
      title     = title,
      label     = label,
      file      = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  ))
}


# ── First-stage table function ───────────────────────────────────────────────
#
# Produces a single etable from every first stage stored in `storage_list_name`.
#
# Column layout (two-level header):
#   Top row    – subheader label, spanning as many columns as outcomes in that call
#   Bottom row – outcome (structural-equation depvar) name, one column each
#
# If coalvar had multiple endogenous regressors, pass the one you want via
# `which_coalvar`; defaults to the first one found.

first_stage_table <- function(storage_list_name, outfile, title = NULL,
                               label = NULL, which_coalvar = NULL,
                               drop = NULL) {

  fs_list <- get(storage_list_name, envir = .GlobalEnv)

  model_list      <- list()   # flat list of feols first-stage objects
  inner_headers   <- list()   # one entry per column: depvar name, spans 1
  outer_headers   <- list()   # one entry per subheader: name, spans N cols

  for (subheader in names(fs_list)) {

    depvar_bucket <- fs_list[[subheader]]   # list keyed by structural depvar
    n_cols        <- 0

    for (depvar in names(depvar_bucket)) {

      coal_models <- depvar_bucket[[depvar]]   # named list by coalvar

      # Pick the endogenous regressor to tabulate
      cv <- if (!is.null(which_coalvar)) {
        which_coalvar
      } else {
        names(coal_models)[1]
      }

      model_list             <- c(model_list, list(coal_models[[cv]]))
      inner_headers[[depvar]] <- 1L   # each depvar spans exactly 1 column
      n_cols                 <- n_cols + 1L
    }

    outer_headers[[subheader]] <- n_cols
  }

  # etable accepts a list-of-lists for multi-row headers:
  #   first list  = top    header row (subheaders)
  #   second list = bottom header row (depvar labels)
  two_level_headers <- list(outer_headers, inner_headers)

  do.call(etable, c(
    model_list,
    list(
      fitstat   = ~ . + ivf1,
      style.tex = style.tex("aer", adjustbox = TRUE),
      tex       = TRUE,
      drop      = drop,
      headers   = two_level_headers,
      title     = title,
      label     = label,
      file      = paste0("Z:/ek559/mining_wq/output/reg/", outfile, ".tex")
    )
  ))
}

# Each call names the global list ("fs_store") and its own subheader.
# Repeated calls with the same list name append rather than overwrite.

tsls_reg_output(
  full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1), ],
  c("nitrates_share", "arsenic_share", "inorganic_chemicals_share", "radionuclides_share"),
  c("num_coal_mines_unified"),
  "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
  "Effect of number of mines on PWS violations (only colocated PWS's)",
  "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
  "post95*sulfur_unified",
  storage_list_name = "fs_store_minevio",
  subheader         = "Colocated"
)

tsls_reg_output(
  full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ],
  c("nitrates_share", "arsenic_share", "inorganic_chemicals_share", "radionuclides_share"),
  c("num_coal_mines_upstream"),
  "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
  "Effect of number of mines on PWS violations (only downstream PWS's)",
  "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
  "post95*sulfur_unified",
  storage_list_name = "fs_store_minevio",
  subheader         = "Downstream"
)

tsls_reg_output(full[full$minehuc_upstream_of_mine == 0, ],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1985to2005colocateddownstream_coalunified",
                "Effect of number of mines on PWS violations (colocated and downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005colocateddownstream_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

# After all coalunified calls, produce the combined first-stage table
first_stage_table(
  storage_list_name = "fs_store_minevio",
  outfile           = "first_stages_combined",
  title             = "First Stage Results Across Samples",
  label             = "tab:first_stages",
  drop              = "num_facilities"
)

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

## number of mines related violations and robustness checks binary outcome
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005allhucs",
                "post95*sulfur_colocated")

###############
## non-mine vio
###############
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate_coalunified",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm_coalunified",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

## number of mines related violations and robustness checks binary outcome
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated and downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs",
                "post95*sulfur_colocated")

###################################################
# Num violations/mine violations/nonmine violations
###################################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005colocate_coalunified",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm_coalunified",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full,
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

#############################################
# Num mines as above but years from 1990-2000
#############################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                     (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0)
                     & (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1)
                     & (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs",
                "post95*sulfur_colocated")

###############
## non-mine vio
###############
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                     (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0)&
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs",
                "post95*sulfur_colocated")

###################################################
# Num violations/mine violations/nonmine violations
###################################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000allhucs",
                "post95*sulfur_colocated")


####################
# poisson regression
####################

tsls_poisson_reg_output <- function(dset, varlist, coalvar, regoutname, title, label){
    no_fe_controls <- c("post95", "sulfur", "POPULATION_SERVED_COUNT","SOURCE_WATER_PROTECTION_CODE_Y",
                  "PRIMARY_SOURCE_CODE_GU", "PRIMARY_SOURCE_CODE_GUP", "PRIMARY_SOURCE_CODE_GW",
                  "PRIMARY_SOURCE_CODE_SW", "PRIMARY_SOURCE_CODE_SWP", "IS_WHOLESALER_IND_Y",
                  "IS_GRANT_ELIGIBLE_IND_Y", "IS_SOURCE_TREATED_IND_Y", "num_hucs",
                  "num_facilities", "PRIMARY_SOURCE_CODE_GWP")
    fe_controls <- paste(no_fe_controls, collapse = " + ")

    fe <- "PWSID + year"
    fe_controls <- paste(fe_controls, fe, sep = " | ")
    iv <- paste(coalvar, "~ post95*sulfur")

    poisson_no_fe <- paste(paste("~", coalvar, "+"), paste(no_fe_controls, collapse = " + "))
    poisson <- paste(paste("~", coalvar, "+"), paste(fe_controls, collapse = " + "))
    rf <- paste("~ post95*sulfur +", paste(fe_controls, collapse = " + "))
    tsls <- paste(paste(" ~ ", fe_controls), iv, sep = " | ")

    result <- list()
    num <- 0
    for (i in varlist) {
        num <- num + 1
        panelname <- paste0(paste0("Panel ", as.character(num), ": "), i)
        print(panelname)
        result[[panelname]] <- list(
            "Poisson" = fepois(as.formula(paste(i, poisson_no_fe)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "Poisson (FE)" = fepois(as.formula(paste(i, poisson)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "Poisson RF" = fepois(as.formula(paste(i, rf)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID))
        print(result[[panelname]][['Poisson']])
        print(result[[panelname]][['Poisson (FE)']])
        print(result[[panelname]][['Poisson RF']])
    }

    print(result[[panelname]])

    modelsummary(result,
                title = paste0(title, "\\label{tab:", label,"}"),
                stars = c('*' = .1, '**' = .05, '***' = .01),
                escape = FALSE,
                statistic = "conf.int",
                fmt = "%.3f",
                coef_omit = "^(?!.*post95|.*num_coal|.*production_short_tons_coal|.*fit_)",
                gof_omit = "BIC|AIC|R2 Within|Std",
                shape = "cbind",
                notes = c("Data is from 1990 to 2005.",
                          "Standard errors clustered at PWS level.")) |>                     
    format_tt(escape = FALSE) |>
    theme_latex(resize_width= 1, resize_direction="down") |>
    save_tt(paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex"), overwrite = TRUE)
}

## mining related violations and robustness checks 
tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("nitrates_share_days",
                "arsenic_share_days",
                "inorganic_chemicals_share_days",
                "radionuclides_share_days"),
                "num_coal_mines",
                "olsrf2slspoisson_nummine_mine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "poisson_nummine_mine_vio_1985to2005dwnstrmcolocate")

tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("nitrates_share_days",
                "arsenic_share_days",
                "inorganic_chemicals_share_days",
                "radionuclides_share_days"),
                "num_coal_mines",
                "olsrf2slspoisson_nummine_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "poisson_nummine_mine_vio_1985to2005dwnstrm")

## non-mine vio
tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("total_coliform_share_days",
                  "surface_ground_water_rule_share_days",
                  "voc_share_days",
                  "soc_share_days"),
                "num_coal_mines",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrmcolocate")

tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "num_coal_mines",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrm")




### Sum vars of het DiD
# First year number of mines each system exposed to
full <- full %>%
  arrange(PWSID, year) %>%
  group_by(PWSID) %>%
  mutate(first_nummines = first(num_coal_mines)) %>%
  ungroup()
unique(full$first_nummines)
# 0  2  3  1  4  5  7  8 14 12  6

# whats the direction of the increases and decreases of coal mine
full <- full %>%
  arrange(PWSID, year) %>%
  group_by(PWSID) %>%
  mutate(d_num_coal_mines = num_coal_mines - lag(num_coal_mines)) %>%
  ungroup()
unique(full$d_num_coal_mines)
# NA  2  0 -1  1  3 -2  4 -3  5 -5  8 -7 -6  9  7 -4

# how many times does num coal mine change
full$switch <- as.integer(full$d_num_coal_mines != 0 & !is.na(full$d_num_coal_mines))
full <- full %>%
  group_by(PWSID) %>%
  mutate(
    switch = sum(switch, na.rm = TRUE)
  ) %>%
  ungroup()
unique(full$switch)
# 6  0  2  4  7 12  5  3 13  1  9 10  8 14 15 17 16 18 19 11

##############
# Het treat diff in diff
##############

full$high_sulfur <- 0  # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- 1  # Set to 1 where condition is TRUE
full$arp <- 1
full$arp[full$minehuc_mine==0] <- 0
full$arp[full$year<1993] <- 0
full$groups <- 'upstream_lowsulfur'
full$groups[full$high_sulfur== 1 & full$minehuc_mine==0] <- 'upstream_highsulfur'
full$groups[full$high_sulfur== 1 & full$minehuc_mine==1] <- 'mine_highsulfur'
full$groups[full$high_sulfur== 0 & full$minehuc_mine==1] <- 'mine_lowsulfur'

stackddheteventstudy <- function(varlist, dset, plot_title, plot_subtitle, vartitle, numcol, footnote, outname){
    # stacks a list of violations within minehucs but each line is low sulfur vs high

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        tempddhet <-did_multiplegt_dyn(df = dset, 
                    outcome = varname, 
                    group = "groups", 
                    time = "year", 
                    treatment = "arp",
                    cluster = "groups",
                    effects = 10, 
                    placebo = 4)
        print(tempddhet)
        
        plt <- tempddhet$plot # Assign the plot to new object (to avoid writing its full path every time)

        plt$layers[[1]] <- NULL # drop the line
        plt <- plt + geom_hline(yintercept = 0, linetype = "dashed", color = "black") +  # Add the reference line
                geom_vline(xintercept = 0, linetype = "dashed", color = "blue") +  # Vertical reference line
            theme(plot.title = element_text(hjust = 0.5), panel.grid.major = element_blank(), # Clean the background
                panel.grid.minor = element_blank(), panel.background = element_blank(), 
                axis.line = element_line(colour = "black")
            ) + scale_x_continuous(breaks=c(-4,-2,0,2,4,6,8,10))+
            ylab(" ") + xlab("time to treat")+ggtitle(vartitle[i]) # Add titles    

        plotlist[[varname]] <- plt

    }
    # Combine the plots
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title   = plot_title,
                    subtitle = plot_subtitle,
                    caption = footnote) +
    plot_layout(guides = "collect") &
    theme(legend.position = "bottom",
          plot.caption.position = "plot",        # puts caption below the entire patchwork
          plot.caption = element_text(size = 9, color = "gray30", hjust = 0))

    ggsave(outname, combined_plot, height = 5, width = 5)
}

stackddheteventstudy(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[full$year>1984 & full$year<2006,], 
                      "ARP on PWS mine type SDWA violations (1985-2005)", 
                      "Heterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                       "Notes: PWS's grouped by upstream/mine-colocated high/low sulfur.\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_mine_vio_1985to2005.png")

stackddheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                      full[full$year>1984 & full$year<2006,], 
                      "ARP on PWS non-mine type SDWA violations (1985-2005)", 
                      "Heterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))",
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: PWS's grouped by upstream/mine-colocated high/low sulfur.\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_nonmine_vio_1985to2005.png")

## effect of just low suflur mine
stackddheteventstudy(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[(full$year>1984 & full$year<2006)&
                           (full$groups!='mine_highsulfur'),], 
                      "ARP on PWS mine type SDWA violations (1985-2005)", 
                      "Excluding PWSs co-located with mines in high-sulfur HUC12s", 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: PWS's grouped by upstream/mine colocated and high/low sulfur.\nHeterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_mine_vio_1985to2005_highsulf.png")

## effect of just high sulfur mine
stackddheteventstudy(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[(full$year>1984 & full$year<2006)&
                           (full$groups!='mine_lowsulfur'),], 
                      "ARP on PWS mine type SDWA violations (1985-2005)", 
                      "Excluding PWSs co-located with mines in low-sulfur HUC12s", 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Notes: PWS's grouped by upstream/mine colocated and high/low sulfur.\nHeterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_mine_vio_1985to2005_lowsulf.png")

# effect of non mine het high sulfur
stackddheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                        full[(full$year>1984 & full$year<2006)&
                           (full$groups!='mine_lowsulfur'),],
                      "ARP on PWS non-mine type SDWA violations (1985-2005)", 
                      "Excluding PWSs co-located with mines in low-sulfur HUC12s", 
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: PWS's grouped by upstream/mine colocated and high/low sulfur.\nHeterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_nonmine_vio_1985to2005_highsulfur.png")

# effect of non mine het low sulfur
stackddheteventstudy(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                        full[(full$year>1984 & full$year<2006)&
                           (full$groups!='mine_highsulfur'),],
                      "ARP on PWS non-mine type SDWA violations (1985-2005)", 
                      "Excluding PWSs co-located with mines in high-sulfur HUC12s", 
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: PWS's grouped by upstream/mine colocated and high/low sulfur.\nHeterogeneity-robust DiD (Chaisemartin and D’Haultfoeuille (2024))\nSEs clustered at group level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/es_het_nonmine_vio_1985to2005_lowsulfur.png")

###
# diff in diff regression
###

########################
# raw plot of violations 
########################

stackmineviobytreat <- function(varlist, dset, plot_title, vartitle, numcol, outname){
    # stacks a list of violations within minehucs but each line is low sulfur vs high

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        df <- dset %>%
                group_by(CoalMineHUC12, year) %>%
                summarise(val = mean(.data[[varlist[i]]], na.rm = TRUE),
                        .groups="drop")

        plot = ggplot(df, aes(x=year, y=val, color= CoalMineHUC12)) +
            geom_line() +
            labs(title = vartitle[i], y = "Share of systems", x = "Year") +
        theme_minimal() +
        theme(legend.position = "none") +
        scale_x_continuous(breaks = c(1990, 1994, 2000, 2005))

        plotlist[[varname]] <- plot

    }
    # Combine the plots

    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")  # or "right", "top", etc.

    ggsave(outname, combined_plot, height = 5, width = 5)
}

full$CoalMineHUC12 <- full$minehuc_mine
full$CoalMineHUC12[full$CoalMineHUC12 ==1 ] <- "Mine"
full$CoalMineHUC12[full$CoalMineHUC12 ==0 ] <- "Upstream"

stackmineviobytreat(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[full$year>1984 & full$year<2006 & full$high_sulfur==1,], 
                      c("Share high sulfur HUC12 CWS with mine violation (1985-2005)"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/high_sulf_mining_viol_raw_line1985to2005.png")

stackmineviobytreat(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides"), 
                      full[full$year>1984 & full$year<2006 & full$high_sulfur==0,], 
                      c("Share low sulfur HUC12 CWS with mine violation (1985-2005)"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/low_sulf_mining_viol_raw_line1985to2005.png")

############################
# event study: mining
############################

# time to treat
full$time_to_treat <- ifelse(full$minehuc_mine==1,
                             full$year-1995,
                             0)

evvio <- function(varlist, dset, plot_title, vartitle, numcol, outname){
    # stacks event studies on top of each

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        formula_str <- paste(varname, "~", paste("i(time_to_treat, minehuc_mine, ref = -1) | year+PWSID"))
        mod_twfe = feols(as.formula(formula_str), # FEs
                     cluster = ~PWSID, # Clustered SEs. It is best practice to cluster SEs at the unit level.
                     data= dset)

        plot <- ggiplot(mod_twfe,                    # event study model (fixest object)
                        ylab = "Experiencing violation",
                        xlab = "Time to treatment",  # same label as before
                        main = paste0(vartitle[i])   # plot title
                        )
        plotlist[[varname]] <- plot

    }
    # Combine the plots
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")  # or "right", "top", etc.

    ggsave(outname, combined_plot, height = 5, width = 5)
}

evvio(c("nitrates",
        "arsenic",
        "inorganic_chemicals",
        "radionuclides"), 
      full[full$year>1989 & full$year<2006 & full$high_sulfur==0,], 
      c("Share low sulfur HUC12 CWS with mine violation"), 
      c("Nitrates",
        "Arsenic",
        "Inorg chem",
        "Radionuclides"),
        2,
        "Z:/ek559/mining_wq/output/fig/low_sulf_mining_viol_eventstudy1990to2005.png")

evvio(c("nitrates",
        "arsenic",
        "inorganic_chemicals",
        "radionuclides"), 
      full[full$year>1989 & full$year<2006 & full$high_sulfur==1,], 
      c("Share low sulfur HUC12 CWS with mine violation"), 
      c("Nitrates",
        "Arsenic",
        "Inorg chem",
        "Radionuclides"),
        2,
        "Z:/ek559/mining_wq/output/fig/high_sulf_mining_viol_eventstudy1990to2005.png")

########################
# Diff in diff by sulfur
########################

full$CoalMineHUC12 <- 1
full$CoalMineHUC12[full$minehuc_mine==0] <- 0
full$post93 <- 0
full$post93[full$year>1992] <- 1

mining_pollutants <- list(
    "Nitrates"= feols(nitrates ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==1, ],
                             cluster = ~ PWSID),
    "Arsenic"= feols(arsenic ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==1, ],
                             cluster = ~ PWSID),
    "Inorganic chemicals"=feols(inorganic_chemicals ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==1, ],
                             cluster = ~ PWSID),
    "Radionuclides"=feols(radionuclides ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==1, ],
                             cluster = ~ PWSID))

modelsummary(mining_pollutants,
             title = "Effect of ARP on drinking water violations at high sulfur coal PWSs",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post93:CoalMineHUC12" = "post93 x CoalMineHUC12"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1985 to 2005.",
                       "Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if PWS intake HUC12 has coal production over sample period.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(outer = "label={tblr:diff_diff_miningviol_highsulf}",resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/diff_diff_miningviol_highsulf.tex", overwrite = TRUE)

mining_pollutants <- list(
    "Nitrates"= feols(nitrates ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==0, ],
                             cluster = ~ PWSID),
    "Arsenic"= feols(arsenic ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==0, ],
                             cluster = ~ PWSID),
    "Inorganic chemicals"=feols(inorganic_chemicals ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==0, ],
                             cluster = ~ PWSID),
    "Radionuclides"=feols(radionuclides ~ post93*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1984 & full$year<2006 & full$high_sulfur==0, ],
                             cluster = ~ PWSID))

modelsummary(mining_pollutants,
             title = "Effect of ARP on drinking water violations at low sulfur coal PWSs",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post93:CoalMineHUC12" = "post93 x CoalMineHUC12"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1985 to 2005.",
                       "Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if PWS intake HUC12 has coal production over sample period.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(outer = "label={tblr:diff_diff_miningviol_lowsulf}", resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/diff_diff_miningviol_lowsulf.tex", overwrite = TRUE)

##############
# Mine closure
##############
# THIS CODE IS BROKEN IT DOES NOT 
# REstrict the regression to only observations 
# where num_coal_mines either only fell
# or only increased
#

minenumdf <- function(df, increase, year_window){
    # if you want to study a mine increase then increase = 1
    # if you want to study a mine decrease then increase = 0

    df <- df %>%
    arrange(PWSID, year) %>%               # ensure proper panel order
    group_by(PWSID) %>%
    mutate(
        # change = mines at t+1 minus mines at t
        change = dplyr::lead(num_coal_mines) - num_coal_mines,
        
        # first year when mines increased (t+1 > t); else 3000
        first_year_increase = {
        idx <- which(change > 0)
        if (length(idx)) year[idx[1]] else 3000
        },
        
        # first year when mines decreased (t+1 < t); else 3000
        first_year_decrease = {
        idx <- which(change < 0)
        if (length(idx)) year[idx[1]] else 3000
        }
    ) %>%
    ungroup()

    upstream <- df[df$minehuc_mine==0,]

    if (increase == 1){
        df <- df %>%
            filter(
                year >= (first_year_increase - year_window) &
                year <= (first_year_increase + year_window)
            )
        # Remove pwsids that have any negative change in df_window
        df <- df %>%
            group_by(PWSID) %>%
            filter(!any(change < 0, na.rm = TRUE)) %>%
            ungroup()
        df <- rbind(df, upstream)

        df$time_to_treat <- ifelse(df$minehuc_mine==1,
                                   df$year - df$first_year_increase,
                                   0)
            
    } else {
        df <- df %>%
            filter(
                year >= (first_year_decrease - year_window) &
                year <= (first_year_decrease + year_window)
            )
                # Remove pwsids that have any positive change in df_window
        df <- df %>%
            group_by(PWSID) %>%
            filter(!any(change > 0, na.rm = TRUE)) %>%
            ungroup()
        df <- rbind(df, upstream)

        df$time_to_treat <- ifelse(df$minehuc_mine==1,
                                   df$year - df$first_year_decrease,
                                   0)
    }

    return(df)
}

esminecloseoropen <- function(varlist, dset, plot_title, vartitle, numcol, footnote, outname){
    # stacks event studies on top of each

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        formula_str <- paste(varname, "~", paste("i(time_to_treat, minehuc_mine, ref = -1) | year+PWSID"))
        mod_twfe = feols(as.formula(formula_str), # FEs
                     cluster = ~PWSID, # Clustered SEs. It is best practice to cluster SEs at the unit level.
                     data= dset)

        print(mod_twfe)
        plot <- ggiplot(mod_twfe,                    # event study model (fixest object)
                        ylab = "Violation likelihood",
                        xlab = "Time to treatment",  # same label as before
                        main = paste0(vartitle[i])   # plot title
                        )
        plotlist[[varname]] <- plot

    }
    # Combine the plots
    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title,
                    caption = footnote) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom",
          plot.caption.position = "plot",        # puts caption below the entire patchwork
          plot.caption = element_text(size = 9, color = "gray30", hjust = 0))
    ggsave(outname, combined_plot, height = 5, width = 5)
}

# mine close (num mine decrease)
df <- minenumdf(full, increase=0, year_window=5)

esminecloseoropen(c("nitrates",
        "arsenic",
        "inorganic_chemicals",
        "radionuclides"), 
      df, 
      c("Share PWS with mine violation following mine closure"), 
      c("Nitrates",
        "Arsenic",
        "Inorg chem",
        "Radionuclides"),
        2,
        "Notes: PWS's upstream or mine closed in HUC12 and none opened in 5 years.\nTWFE DiD with SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type.",
        "Z:/ek559/mining_wq/output/fig/mine_closure_viol_eventstudy1985to2005.png")

esminecloseoropen(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                        df,
                        c("Share CWS with non-mine violation following mine closure"), 
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: PWS's upstream or mine closed in HUC12 and none opened in 5 years.\nTWFE DiD with SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/mine_closure_nonmineviol_eventstudy1985to2005.png")

# mine open (num mine increase)
df <- minenumdf(full, increase=1, year_window=5)

esminecloseoropen(c("nitrates",
        "arsenic",
        "inorganic_chemicals",
        "radionuclides"), 
      df, 
      c("Share CWS with mine violation following mine opening"), 
      c("Nitrates",
        "Arsenic",
        "Inorg chem",
        "Radionuclides"),
        2,
        "Notes: PWS's upstream or mine opened in HUC12 and none closed in 5 years.\nTWFE DiD with SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type.",
        "Z:/ek559/mining_wq/output/fig/mine_open_viol_eventstudy1985to2005.png")

esminecloseoropen(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                        df,
                        c("Share CWS with non-mine violation following mine opening"), 
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Notes: PWS's upstream or mine opened in HUC12 and none closed in 5 years.\nTWFE DiD with SEs clustered at PWSID level.\nBinary dependent variable if system had current violation type.",
                      "Z:/ek559/mining_wq/output/fig/mine_open_nonmineviol_eventstudy1985to2005.png")

###################
# ARCHIVE CODE
###################

tsls_reg_output <- function(dset, varlist, coalvar, regoutname, title, label){
    controls <- c("post95", "sulfur", "POPULATION_SERVED_COUNT","SOURCE_WATER_PROTECTION_CODE_Y",
                  "PRIMARY_SOURCE_CODE_GU", "PRIMARY_SOURCE_CODE_GUP", "PRIMARY_SOURCE_CODE_GW",
                  "PRIMARY_SOURCE_CODE_SW", "PRIMARY_SOURCE_CODE_SWP", "IS_WHOLESALER_IND_Y",
                  "IS_GRANT_ELIGIBLE_IND_Y", "IS_SOURCE_TREATED_IND_Y", "num_hucs",
                  "num_facilities", "PRIMARY_SOURCE_CODE_GWP")
    controls <- paste(controls, collapse = " + ")
    fe <- "PWSID + year"
    controls <- paste(controls, fe, sep = " | ")
    iv <- paste(coalvar, "~ post95*sulfur")

    ols <- paste(paste("~", coalvar, "+"), paste(controls, collapse = " + "))
    rf <- paste("~ post95*sulfur +", paste(controls, collapse = " + "))
    tsls <- paste(paste(" ~ ", controls), iv, sep = " | ")

    result <- list()
    num <- 0
    for (i in varlist) {
        num <- num + 1
        panelname <- paste0(paste0("Panel ", as.character(num), ": "), i)
        twostage <- feols(as.formula(paste(i, tsls)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID)

        result[[panelname]] <- list(
            "OLS" = feols(as.formula(paste(i, ols)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "RF" = feols(as.formula(paste(i, rf)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "1st Stage" = summary(twostage, stage=1, se="cluster", cluster = "PWSID"),   
            "2nd Stage" = summary(twostage, stage=2, se="cluster", cluster = "PWSID"))
            #"2SLS" = feols(as.formula(paste(i, tsls)),
            #            data = dset[(dset[[i]] > 0) |
            #                        (dset$no_violation == 1), ],
            #            cluster = ~ PWSID))         
            fit <- fitstat(result[[panelname]][['1st Stage']], ~ ivf1, cluster = "PWSID", verbose=FALSE)
            print(fit$ivf1$stat)
    }

    modelsummary(result,
                title = paste0(title, "\\label{tab:", label,"}"),
                stars = c('*' = .1, '**' = .05, '***' = .01),
                escape = FALSE,
                statistic = "conf.int",
                fmt = "%.3f",
                coef_omit = "^(?!.*post95|.*num_coal|.*production_short_tons_coal|.*fit_)",
                gof_omit = "BIC|AIC|R2 Within|Std",
                shape = "cbind",
                notes = c("All estimations include PWS and year fixed effects.", 
                          "Data is from 1990 to 2005.",
                          "Standard errors clustered at PWS level.")) |>                     
    format_tt(escape = FALSE) |>
    theme_latex(resize_width= 1, resize_direction="down") |>
    save_tt(paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex"), overwrite = TRUE)
}

tsls_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                "num_coal_mines",
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm")

tsls_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "num_coal_mines",
                "olsrf2sls_nummine_nonmine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_nonmine_vio_1985to2005dwnstrm")

################################################
# Main 2SLS tables
# Subsamples: downstream only; downstream + colocated
# Outcomes:   _share_days (all / MCL / MR)
# Instrument: post95 * sulfur_unified
# Each outcome subset to: violation type > 0 OR no_violation == 1
################################################

# ── Variable label dictionary ────────────────────────────────────────────────
vio_dict <- c(
  nitrates_share_days                      = "Nitrates",
  arsenic_share_days                       = "Arsenic",
  inorganic_chemicals_share_days           = "Inorganic chemicals",
  radionuclides_share_days                 = "Radionuclides",
  nitrates_MCL_share_days                  = "Nitrates (MCL)",
  arsenic_MCL_share_days                   = "Arsenic (MCL)",
  inorganic_chemicals_MCL_share_days       = "Inorganic chemicals (MCL)",
  radionuclides_MCL_share_days             = "Radionuclides (MCL)",
  nitrates_MR_share_days                   = "Nitrates (MR)",
  arsenic_MR_share_days                    = "Arsenic (MR)",
  inorganic_chemicals_MR_share_days        = "Inorganic chemicals (MR)",
  radionuclides_MR_share_days              = "Radionuclides (MR)",
  total_coliform_share_days                = "Total coliform",
  surface_ground_water_rule_share_days     = "S/G water rule",
  voc_share_days                           = "VOCs",
  soc_share_days                           = "SOCs",
  total_coliform_MCL_share_days            = "Total coliform (MCL)",
  surface_ground_water_rule_MCL_share_days = "S/G water rule (MCL)",
  voc_MCL_share_days                       = "VOCs (MCL)",
  soc_MCL_share_days                       = "SOCs (MCL)",
  total_coliform_MR_share_days             = "Total coliform (MR)",
  surface_ground_water_rule_MR_share_days  = "S/G water rule (MR)",
  voc_MR_share_days                        = "VOCs (MR)",
  soc_MR_share_days                        = "SOCs (MR)"
)

# ── Post-processor: move notes outside the adjustbox ─────────────────────────
# etable places notes inside \begin{adjustbox}...\end{adjustbox}, which renders
# them squished inline. This function moves the \par \raggedright block to after
# \end{adjustbox} so it spans the full table width below.
# Uses fixed-string matching throughout to avoid regex backslash escaping issues.
move_notes_below_adjustbox <- function(x) {
  # fixest passes postprocess.tex a character vector (one element per line);
  # collapse to a single string for pattern matching then return as-is.
  x <- paste(x, collapse = "\n")

  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"

  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)

  # If either marker is absent, return unchanged
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)

  # Extract the note block: from \par \raggedright up to (not including) \end{adjustbox}
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)

  # Remove note block from inside the adjustbox
  x <- sub(note_block, "", x, fixed = TRUE)

  # Append note after \end{adjustbox} (trimmed to remove leading whitespace)
  x <- sub(end_adj,
           paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ", trimws(note_block), "}"),
           x, fixed = TRUE)
  x
}

# ── Regression function ───────────────────────────────────────────────────────
# Runs OLS, reduced form, and 2SLS for each outcome in varlist.
# dict and notes are passed through to etable.

tsls_reg_output_main <- function(dset, varlist, coalvar, regoutname, title, label,
                                  instr_str, dict = NULL, notes = NULL) {

  controls            <- c("num_facilities")
  drop_controls_exact <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe_str              <- "PWSID + STATE_CODE + year"
  controls_str        <- paste(controls, collapse = " + ")

  result <- list()

  for (y in varlist) {
    f_ols <- as.formula(
      paste0(y, " ~ ", paste(coalvar, collapse = "+"), " + ", controls_str,
             " | ", fe_str)
    )
    f_rf <- as.formula(
      paste0(y, " ~ ", instr_str, " + ", controls_str, " | ", fe_str)
    )
    f_iv <- as.formula(
      paste0(y, " ~ ", controls_str,
             " | ", fe_str,
             " | ", paste(coalvar, collapse = "+"), " ~ ", instr_str)
    )

    mods <- tryCatch({
      list(
        OLS = fixest::feols(f_ols, data = dset, cluster = ~ PWSID),
        RF  = fixest::feols(f_rf,  data = dset, cluster = ~ PWSID),
        IV  = fixest::feols(f_iv,  data = dset, cluster = ~ PWSID)
      )
    }, error = function(e) {
      cat("  Skipping", y, "—", conditionMessage(e), "\n")
      NULL
    })

    if (!is.null(mods)) result[[y]] <- mods
  }

  if (length(result) == 0) {
    cat("  No estimable outcomes for", regoutname, "— skipping etable.\n")
    return(invisible(NULL))
  }

  model_list <- unlist(
    lapply(names(result), function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )

  etable_args <- c(
    model_list,
    list(
      fitstat        = ~ . + ivf1,
      style.tex      = style.tex("aer", adjustbox = TRUE),
      tex            = TRUE,
      drop           = drop_controls_exact,
      title          = title,
      label          = label,
      postprocess.tex = move_notes_below_adjustbox,
      file           = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  )
  if (!is.null(dict))  etable_args$dict  <- dict
  if (!is.null(notes)) etable_args$notes <- notes

  do.call(etable, etable_args)
}

# ── Standard table note ───────────────────────────────────────────────────────
std_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is days out of the year in violation. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

# ── Parameter grid ────────────────────────────────────────────────────────────
# Load a fresh copy of the data without the balanced panel filter so that
# sample sizes match the existing regression tables (e.g. ~6,225 downstream).
# minehuc_upstream_of_mine is converted to character here to match line 252-253.
full_unbal <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full_unbal <- full_unbal[full_unbal$year < 2006 & full_unbal$year > 1984, ]
full_unbal <- full_unbal[full_unbal$PWSID != "WV3303401", ]
full_unbal$minehuc_upstream_of_mine[full_unbal$minehuc_upstream_of_mine == 1] <- "Upstream of mining"
full_unbal$minehuc_upstream_of_mine[full_unbal$minehuc_upstream_of_mine == 0] <- "Colocated/Downstream of mining"

sample_specs <- list(
  list(
    sample    = "dwnstrm",
    dset      = full_unbal[(full_unbal$minehuc_downstream_of_mine == 1) & (full_unbal$minehuc_mine == 0), ],
    coalvar   = "num_coal_mines_upstream",
    instr     = "post95*sulfur_unified",
    titlesamp = "downstream PWS's"
  ),
  list(
    sample    = "dwnstrmcolocate",
    dset      = full_unbal[full_unbal$minehuc_upstream_of_mine == "Colocated/Downstream of mining", ],
    coalvar   = "num_coal_mines_unified",
    instr     = "post95*sulfur_unified",
    titlesamp = "downstream and colocated PWS's"
  )
)

vio_specs <- list(
  list(
    name     = "minevio",
    allcat   = c("nitrates_share_days", "arsenic_share_days",
                 "inorganic_chemicals_share_days", "radionuclides_share_days"),
    mcl      = c("nitrates_MCL_share_days", "arsenic_MCL_share_days",
                 "inorganic_chemicals_MCL_share_days", "radionuclides_MCL_share_days"),
    mr       = c("nitrates_MR_share_days", "arsenic_MR_share_days",
                 "inorganic_chemicals_MR_share_days", "radionuclides_MR_share_days"),
    titlevio = "mining violations"
  ),
  list(
    name     = "nonminevio",
    allcat   = c("total_coliform_share_days", "surface_ground_water_rule_share_days",
                 "voc_share_days", "soc_share_days"),
    mcl      = c("total_coliform_MCL_share_days", "surface_ground_water_rule_MCL_share_days",
                 "voc_MCL_share_days", "soc_MCL_share_days"),
    mr       = c("total_coliform_MR_share_days", "surface_ground_water_rule_MR_share_days",
                 "voc_MR_share_days", "soc_MR_share_days"),
    titlevio = "non-mining violations"
  )
)

cat_specs <- list(
  list(name = "allcat", varkey = "allcat", titlecat = "any violation category"),
  list(name = "mcl",    varkey = "mcl",    titlecat = "MCL violations only"),
  list(name = "mr",     varkey = "mr",     titlecat = "MR violations only")
)

# ── Run all 12 tables ─────────────────────────────────────────────────────────
for (sp in sample_specs) {
  for (vp in vio_specs) {
    for (cp in cat_specs) {

      fname     <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name)
      tab_title <- paste0("Effect of coal mines on ", vp$titlevio,
                          " (", cp$titlecat, ", ", sp$titlesamp, ")")
      varlist   <- vp[[cp$varkey]]

      cat("Running:", fname, "\n")

      tsls_reg_output_main(
        dset       = sp$dset,
        varlist    = varlist,
        coalvar    = sp$coalvar,
        regoutname = fname,
        title      = tab_title,
        label      = fname,
        instr_str  = sp$instr,
        dict       = vio_dict,
        notes      = std_note
      )
    }
  }
}
