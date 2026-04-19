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
# Restrict to mine HUC12s co-located or upstream of CWSs (prod_sulfur.csv is CWS-matched)
huccoal <- read.csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv")
huccoal <- huccoal[huccoal$minehuc == "mine" & huccoal$year < 2006 & huccoal$year > 1984, ]
huccoal$HighSulfur <- ifelse(huccoal$sulfur_colocated > 1.5, "High sulfur (>1.5%)", "Low sulfur (<=1.5%)")

# Define shared color scale
color_values <- c("High sulfur (>1.5%)" = "blue", "Low sulfur (<=1.5%)" = "red")

# Left plot: before 1995
p_before <- huccoal %>%
  filter(year < 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated,
             y = sulfur_colocated,
             color = HighSulfur)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_smooth(method = "lm", se = FALSE, linewidth = 0.9) +
  scale_color_manual(values = color_values, name = "Sulfur category") +
  labs(
    title = "Before 1995",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw() +
  theme(legend.position = "bottom")

# Right plot: 1995 and after
p_after <- huccoal %>%
  filter(year >= 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated,
             y = sulfur_colocated,
             color = HighSulfur)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_smooth(method = "lm", se = FALSE, linewidth = 0.9) +
  scale_color_manual(values = color_values, name = "Sulfur category") +
  labs(
    title = "1995 and After",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw() +
  theme(legend.position = "bottom")

# Combine with a shared legend
(p_before + p_after) +
  plot_layout(guides = "collect") &
  plot_annotation(title = "HUC12 sulfur (%) and number of coal mines: mine HUC12s co-located or upstream of CWSs") &
  theme(legend.position = "bottom")

ggsave("Z:/ek559/mining_wq/output/fig/scatterhuccoalsulfur.png", width = 8, height = 6, dpi = 500)


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

