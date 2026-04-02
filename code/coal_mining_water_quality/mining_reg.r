.libPaths("Z:/ek559/RPackages")

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
#library(estimatr)

# story should be summary table of why mine and upstream cant be directly compared
# then why diff and diff doesnt work - have the mine story but also need to 
# show how the trends in violations changes within mine when you account for sulfur 
# ie plot mine violations low sulfur vs mine violations high sulfur
# Then show ddd parallel trends and results

full <- read.csv("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.csv")

### PRIOR TO 2006 and AFTER 1984
full <- full[full$year<2006 & full$year>1984,]

##############
# Data summary
##############

# HUC and PWS characteristiscs

full$pws_deactivated <- "N"
full$pws_deactivated[full$year_pws_deactivated<2006] <- "Y"

pwssum <- full

# pre event sum stats
pwssum <- pwssum[pwssum$year<1993,]

pwssum$minehuc_mine[pwssum$minehuc_mine=="0"] <- "Upstream"
pwssum$minehuc_mine[pwssum$minehuc_mine=="1"] <- "Mine"
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
pwssum$FILTRATION_STATUS_CODE_FIL[pwssum$FILTRATION_STATUS_CODE_FIL=="1"]<-"Y"
pwssum$FILTRATION_STATUS_CODE_FIL[pwssum$FILTRATION_STATUS_CODE_FIL=="0"]<-"N"
pwssum$FILTRATION_STATUS_CODE_MIF[pwssum$FILTRATION_STATUS_CODE_MIF=="1"]<-"Y"
pwssum$FILTRATION_STATUS_CODE_MIF[pwssum$FILTRATION_STATUS_CODE_MIF=="0"]<-"N"
pwssum$FILTRATION_STATUS_CODE_SAF[pwssum$FILTRATION_STATUS_CODE_SAF=="1"]<-"Y"
pwssum$FILTRATION_STATUS_CODE_SAF[pwssum$FILTRATION_STATUS_CODE_SAF=="0"]<-"N"
pwssum$SOURCE_WATER_PROTECTION_CODE_Y[pwssum$SOURCE_WATER_PROTECTION_CODE_Y=="1"]<-"Y"
pwssum$SOURCE_WATER_PROTECTION_CODE_Y[pwssum$SOURCE_WATER_PROTECTION_CODE_Y=="0"]<-"N"
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
         "HUC12 N coal mine"=num_coal_mines,
         "HUC12 coal tons"=production_short_tons_coal,
         "HUC12 avg coal BTU"=btu,
         "HUC12 avg coal sulfur"=sulfur,
         "Source protected"=SOURCE_WATER_PROTECTION_CODE_Y,
         "Source treated"=IS_SOURCE_TREATED_IND_Y,
         "Population served"=POPULATION_SERVED_COUNT,
         "PWS owner" = OWNER_TYPE_CODE,
         "PWS deactivated"=pws_deactivated,
         "Primary water source" = PRIMARY_SOURCE_CODE,
         "Grant eligible"=IS_GRANT_ELIGIBLE_IND)

# all pws huc characteristic summary
datasummary_balance(~minehuc_mine,
                    data = pwssum[,c("minehuc_mine",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Source protected",
                                     "water source use",
                                     "Need filtration",
                                     "Avoiding filtration", 
                                     "Filtration in place",
                                     "Source treated",
                                     "Primary water source", 
                                     "Wholesaler", 
                                     "Grant eligible", 
                                     "PWS N Source HUC12",
                                     "Population served",
                                     "HUC12 N coal mine",
                                     "HUC12 coal tons",
                                     "HUC12 avg coal BTU",
                                     "HUC12 avg coal sulfur",
                                     "num_violations")],
                    title = "PWS and HUC12 summary statistics ex ante",
                    notes = c("NA is missing data. Water source use refers to the upstream/mine HUC12 source use."))
# sum table 1 part 1
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1995,c("minehuc_mine",
                                     "PWS deactivated",
                                     "water source use",
                                     "Filtration in place",
                                     "Source treated",
                                     "Primary water source")],
                    title = "PWS source features summary statistics ex ante")

datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "PWS deactivated",
                                     "water source use",
                                     "Filtration in place",
                                     "Source treated",
                                     "Primary water source")],
                    title = "PWS source features summary statistics ex ante",
                    notes = c("NA is missing data. Water source use refers to the upstream/mine HUC12 source use."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pwssource_exante.tex", overwrite = TRUE)

# sum table 1 part 2
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine", 
                                     "HUC12 N coal mine",
                                     "HUC12 coal tons",
                                     "HUC12 avg coal BTU",
                                     "HUC12 avg coal sulfur")],
                    title = "PWS HUC12 source summary statistics ex ante",
                    notes = c("Upstream coal production is 0 by construction."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_hucfeatures_exante.tex", overwrite = TRUE)

# sum table 1 part 3
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Wholesaler", 
                                     "Grant eligible", 
                                     "PWS N Source HUC12",
                                     "Population served")])
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Wholesaler", 
                                     "Grant eligible", 
                                     "PWS N Source HUC12",
                                     "Population served")],
                    title = "PWS summary statistics ex ante",
                    notes = c("NA is missing data."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pws_exante.tex", overwrite = TRUE)

datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "PWS owner",
                                     "PWS deactivated",
                                     "Primary water source", 
                                     "PWS N Source HUC12",
                                     "Population served",
                                     "Filtration in place",
                                     "Source treated")],
                    title = "PWS summary statistics ex ante",
                    notes = c("NA is missing data."),
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_pws_key_exante.tex", overwrite = TRUE)

# Violation summary
pwssum$minehuc_mine[pwssum$minehuc_mine=="0"] <- "Upstream"
pwssum$minehuc_mine[pwssum$minehuc_mine=="1"] <- "Mine"

pwssum$VIOLATION_CATEGORY <- " No violation"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MCL==1] <- "MCL"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MON==1] <- "MON"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MR==1] <- "MR"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MRDLL==1] <- "MRDL"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_Other==1] <- "OTHER"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_RPT==1] <- "RPT"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_TT==1] <- "TT"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_MCL==1] <- "MCL"
pwssum$VIOLATION_CATEGORY[pwssum$VIOLATION_CATEGORY_CODE_nan==1] <- "NA"

pwssum$RULE_FAMILY <- " No violation"
pwssum$RULE_FAMILY[pwssum$rule_family_chemicals==1] <- "Chemicals"
pwssum$RULE_FAMILY[pwssum$rule_family_disinfectants_byproducts==1] <- "Disinfectant byproducts"
pwssum$RULE_FAMILY[pwssum$rule_family_microbials==1] <- "Microbials"
pwssum$RULE_FAMILY[pwssum$rule_family_other==1] <- "Other"
pwssum$RULE_FAMILY[pwssum$rule_family_nan==1] <- "NA"

pwssum$ENF_ACTION_CATEGORY[pwssum$ENF_ACTION_CATEGORY_Formal == 1] <- 'Formal'
pwssum$ENF_ACTION_CATEGORY[pwssum$ENF_ACTION_CATEGORY_Informal == 1] <- 'Informal'
pwssum$ENF_ACTION_CATEGORY[pwssum$ENF_ACTION_CATEGORY_Resolving == 1] <- 'Resolving'
pwssum$ENF_ACTION_CATEGORY[pwssum$ENF_ACTION_CATEGORY_nan==1] <- 'NA'
pwssum$ENF_ACTION_CATEGORY[pwssum$RULE_FAMILY == ' No violation'] <- ' No violation'

pwssum$ENF_ORIGINATOR[pwssum$ENF_ORIGINATOR_CODE_F==1]<-"Federal"
pwssum$ENF_ORIGINATOR[pwssum$ENF_ORIGINATOR_CODE_S==1]<-"State"
pwssum$ENF_ORIGINATOR[pwssum$ENF_ORIGINATOR_CODE_nan==1]<-"NA"
pwssum$ENF_ORIGINATOR[pwssum$RULE_FAMILY == " No violation"] <- " No violation"

pwssum$HEALTH_BASED_VIOL <- " No violation"
pwssum$HEALTH_BASED_VIOL[pwssum$IS_HEALTH_BASED_IND_Y==1]<-"Y"
pwssum$HEALTH_BASED_VIOL[pwssum$IS_HEALTH_BASED_IND_N==1]<-"N"

pwssum$MAJOR_VIOL <- "N"
pwssum$MAJOR_VIOL[pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"
pwssum$MAJOR_VIOL[pwssum$IS_MAJOR_VIOL_IND_Y==1]<-"Y"

datasummary_balance(~minehuc_mine,
                    data = pwssum[,c("minehuc_mine",
                                     "multi_year_viol",
                                     "VIOLATION_CATEGORY",
                                     "RULE_FAMILY",
                                     "ENF_ACTION_CATEGORY",
                                     "ENF_ORIGINATOR", 
                                     "HEALTH_BASED_VIOL",
                                     "MAJOR_VIOL")],
                    title = "Violation and Enforcement Summary")

# write the result of proportion testing across mine 
# and upstream with prop.test in the paper so you dont have to add a column

# sum table 2 part 1
pwssum <- pwssum %>% 
         rename("Enforcement category" = ENF_ACTION_CATEGORY,
                "Enforcement originator" = ENF_ORIGINATOR)
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993, pwssum$VIOLATION_CATEGORY!="No violation",
                                  c("minehuc_mine",
                                    "Enforcement category",
                                    "Enforcement originator")],
                    title = "Enforcement summary ex ante",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_genenf_exante.tex", overwrite = TRUE)

# sum table 2 part 2
pwssum <- pwssum %>%
             rename("Multi-year violation"=multi_year_viol,
                    "Rule family" = RULE_FAMILY,
                    "Health violation" = HEALTH_BASED_VIOL,
                    "Major violation" = MAJOR_VIOL,
                    "PWS yearly violations" = row_count,
                    "Violation category" = VIOLATION_CATEGORY)

datasummary_balance(~minehuc_mine,
                    data = pwssum[,c("minehuc_mine",
                                     "Multi-year violation",
                                     "PWS yearly violations",
                                     "Violation category",
                                     "Rule family",
                                     "Health violation",
                                     "Major violation")],
                    title = "Violation summary ex ante",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_genviol_exante.tex", overwrite = TRUE)

# specific violations

pwssum[["Consumer Confidence Rule"]] <- 'N'
pwssum[["Consumer Confidence Rule"]][pwssum$RULE_CODE_420.0==1] <- "Y"
pwssum[["Consumer Confidence Rule"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Miscellaneous"]] <- 'N'
pwssum[["Miscellaneous"]][pwssum$RULE_CODE_430.0==1] <- "Y"
pwssum[["Miscellaneous"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Total Coliform"]] <- 'N'
pwssum[["Total Coliform"]][pwssum$RULE_CODE_110.0==1 | pwssum$RULE_CODE_111.0==1] <- "Y"
pwssum[["Total Coliform"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Surface/Ground Water Treatment Rule"]] <- 'N'
pwssum[["Surface/Ground Water Treatment Rule"]][pwssum$RULE_CODE_121.0==1 | pwssum$RULE_CODE_140.0==1 | pwssum$RULE_CODE_122.0==1 | pwssum$RULE_CODE_123.0==1] <- "Y"
pwssum[["Surface/Ground Water Treatment Rule"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Disinfectants and Byproducts"]] <- 'N'
pwssum[["Disinfectants and Byproducts"]][pwssum$RULE_CODE_210.0==1 | pwssum$RULE_CODE_220.0==1 | pwssum$RULE_CODE_230.0==1] <- "Y"
pwssum[["Disinfectants and Byproducts"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Volatile Organic Chemicals"]] <- 'N'
pwssum[["Volatile Organic Chemicals"]][pwssum$RULE_CODE_310.0==1] <- "Y"
pwssum[["Volatile Organic Chemicals"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Synthetic Organic Chemicals"]] <- 'N'
pwssum[["Synthetic Organic Chemicals"]][pwssum$RULE_CODE_320.0==1] <- "Y"
pwssum[["Synthetic Organic Chemicals"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Nitrates"]] <- 'N'
pwssum[["Nitrates"]][pwssum$RULE_CODE_331.0==1] <- "Y"
pwssum[["Nitrates"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Arsenic"]] <- 'N'
pwssum[["Arsenic"]][pwssum$RULE_CODE_332.0==1] <- "Y"
pwssum[["Arsenic"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Inorganic Chemicals"]] <- 'N'
pwssum[["Inorganic Chemicals"]][pwssum$RULE_CODE_333.0==1] <- "Y"
pwssum[["Inorganic Chemicals"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Radionuclides"]] <- 'N'
pwssum[["Radionuclides"]][pwssum$RULE_CODE_340.0==1] <- "Y"
pwssum[["Radionuclides"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Lead and Copper Rule"]] <- 'N'
pwssum[["Lead and Copper Rule"]][pwssum$RULE_CODE_350.0==1] <- "Y"
pwssum[["Lead and Copper Rule"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

pwssum[["Public Notice Rule"]] <- 'N'
pwssum[["Public Notice Rule"]][pwssum$RULE_CODE_410.0==1] <- "Y"
pwssum[["Public Notice Rule"]][pwssum$HEALTH_BASED_VIOL == " No violation"] <- " No violation"

# non mining violation
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "Total Coliform",
                                     "Surface/Ground Water Treatment Rule",
                                     "Disinfectants and Byproducts",
                                     "Volatile Organic Chemicals",
                                     "Synthetic Organic Chemicals")])

datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "Total Coliform",
                                     "Surface/Ground Water Treatment Rule",
                                     "Disinfectants and Byproducts",
                                     "Volatile Organic Chemicals",
                                     "Synthetic Organic Chemicals")],
                    title = "Non-coal-mining violations ex ante",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_nonminingviol_exante.tex", overwrite = TRUE)

# mining violation
datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "Nitrates",
                                     "Arsenic",
                                     "Inorganic Chemicals",
                                     "Radionuclides",
                                     "Lead and Copper Rule")],
                    title = "Potential coal mining violations")

datasummary_balance(~minehuc_mine,
                    data = pwssum[pwssum$year<1993,c("minehuc_mine",
                                     "Nitrates",
                                     "Arsenic",
                                     "Inorganic Chemicals",
                                     "Radionuclides",
                                     "Lead and Copper Rule")],
                    title = "Potential coal mining violations ex ante",
                    output='tinytable') |>
format_tt(escape = TRUE) |>
theme_striped() |> 
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/sum/balance_sum_miningviol_exante.tex", overwrite = TRUE)

##############
# ARP on coal production 
##############

coal_data <- read.csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv")
coal_data$high_sulfur <- 0
coal_data$high_sulfur[coal_data$sulfur > 2] <- 1

# HUC12 sulfur histogram
coal_sulfur_hist <- coal_data %>% group_by(huc12) %>%
  summarise(sulfur = max(sulfur))

png("Z:/ek559/mining_wq/output/fig/sulfur_histogram.png")
hist(coal_sulfur_hist$sulfur, main = "HUC12 Mean Coal Sulfur % Histogram", xlab = "coal bed % sulfur", col = "lightblue", border = "black")
dev.off()

# plot coal prod by high sulfur
coal_prod_over_time <- coal_data[coal_data$year<2006,] %>% group_by(high_sulfur, year) %>%
  summarise(avg_huc_coal = mean(production_short_tons_coal),
            tot_sulf_coal = sum(production_short_tons_coal),
            mean_coal_mine = mean(num_coal_mines),
            .groups = "drop")

coal_prod_over_time$high_sulfur <- as.factor(coal_prod_over_time$high_sulfur)

# graphing coal production summary stats
plot1 = ggplot(coal_prod_over_time, aes(x = year, y = avg_huc_coal, color = high_sulfur)) +
    geom_line() +
    labs(title = "Mean HUC12 Coal Production", x = "Year", y = "Short tons") +
    scale_color_manual(values = c("0" = "blue", "1" = "red"),
                       labels = c("0" = "Low Sulfur", "1" = "High Sulfur")) +
    theme_minimal() +
    # Add vertical lines
    geom_vline(xintercept = 1993, linetype = "dashed", color = "black") +
    # Add labels near the lines
    annotate("text", x = 1993, y = max(coal_prod_over_time$avg_huc_coal, na.rm = TRUE),
             label = "Stage 1 permit", vjust = -0.5, hjust = 1, angle = 90, size = 2.3)

plot2 = ggplot(coal_prod_over_time, aes(x = year, y = tot_sulf_coal, color = high_sulfur)) +
    geom_line() +
    labs(title = "Total HUC12 Coal Production", x = "Year", y = "Short tons") +
    scale_color_manual(values = c("0" = "blue", "1" = "red"),
                       labels = c("0" = "Low Sulfur", "1" = "High Sulfur")) +
    theme_minimal()+
    # Add vertical lines
    geom_vline(xintercept = 1993, linetype = "dashed", color = "black") +
    # Add labels near the lines
    annotate("text", x = 1993, y = max(coal_prod_over_time$avg_huc_coal, na.rm = TRUE),
             label = "Stage 1 permit", vjust = -0.5, hjust = 0, angle = 90, size = 2.3)

plot3 = ggplot(coal_prod_over_time, aes(x = year, y = mean_coal_mine, color = high_sulfur)) +
    geom_line() +
    labs(title = "Mean Active HUC12 Coal Mines", x = "Year", y = "Number of mines") +
    scale_color_manual(values = c("0" = "blue", "1" = "red"),
                       labels = c("0" = "Low Sulfur", "1" = "High Sulfur")) +
    theme_minimal()

combined_plot <- wrap_plots(list(plot1, plot2, plot3), ncol = 1) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")  # or "right", "top", etc.

ggsave("Z:/ek559/mining_wq/output/fig/coal_summary_plot.png", combined_plot, height = 5, width = 5)

coal_data$post93 <- 0
coal_data$post93[coal_data$year>1992] <- 1

# Diff in diff coal prod 1990 to 1999
huccoal <- list(
    "Coal tons (1983-2005)" = feols(production_short_tons_coal ~ post93*high_sulfur | huc12 + year,
                             data = coal_data[coal_data$year<2006, ],
                             cluster = ~ huc12),
    "Active mines (1983-2005)" = feols(num_coal_mines ~ post93*high_sulfur | huc12 + year,
                             data = coal_data[coal_data$year<2006, ],
                             cluster = ~ huc12),
    "Coal tons (1985-2005)" = feols(production_short_tons_coal ~ post93*high_sulfur | huc12 + year,
                             data = coal_data[coal_data$year> 1985 & coal_data$year<2006, ],
                             cluster = ~ huc12),
    "Active mines (1985-2005)" = feols(num_coal_mines ~ post95*high_sulfur | huc12 + year,
                             data = coal_data[coal_data$year> 1985 & coal_data$year<2006, ],
                             cluster = ~ huc12)
)      
                        
modelsummary(
  huccoal,
  coef_rename = c("post93:sulfur" = "post93 x sulfur",
                  "post93:high_sulfur" = "post93 x HighSulfur"),
  output = "tinytable",
  stars = c('*' = .1, '**' = .05, '***' = .01),
  statistic = "conf.int",
  fmt = "%.3f",
  gof_omit = ".*",
  title = "Effect of ARP on HUC12 coal production",
  escape = TRUE,
  notes = c("All estimates use HUC12 and year fixed effects.",
            "Standard errors clustered at HUC12 level.",
            "Active mines is the number of active coal mines within HUC12.",
            "Coal tons is the total coal mined from HUC12.")
) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/coal_did_sulf.tex", overwrite = TRUE)

##########
# Violation outcome
##########

full$minehuc_mine[full$minehuc_mine==0]<-'Upstream'
full$minehuc_mine[full$minehuc_mine==1]<-'Mine'

### Diff in Diff ###
####################
### diff and diff sum plot
stackdidrawplot <- function(varlist, dset, title_list, plot_title, outname){
    # varlist must be a character vector
    # plot_title must be a character vector

    plotlist <-  list()

    for (i in seq_along(varlist)){
    df <- dset %>%
            group_by(minehuc_mine, year) %>%
            summarise(val = mean(.data[[varlist[i]]], na.rm = TRUE),
                      .groups="drop")

    plot = ggplot(df, aes(x = year, y = val, color = minehuc_mine)) +
    geom_line() +
    labs(title = title_list[i], x = "Year", y = "Share of PWSs") +
    theme_minimal()

    plotlist[[varlist[i]]] <- plot

    }
    # Combine the plots
    combined_plot <- (wrap_plots(plotlist, ncol = 1) +
                    plot_annotation(title = plot_title))
    ggsave(outname, combined_plot, height = 5, width = 5)
}

stackdidrawplot(c("VIOLATION_CATEGORY_CODE_MCL",
                  "VIOLATION_CATEGORY_CODE_MR",
                  "VIOLATION_CATEGORY_CODE_TT"),
                full,
                c("MCL", 
                  "MR",
                  "TT"),
                "PWS's with violations upstream and downstream",
                "Z:/ek559/mining_wq/output/fig/dd_gen_viol.png")

### Triple Differences ###
##########################

full$high_sulfur <- 0  # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- 1  # Set to 1 where condition is TRUE

# ratios should be one line of upstream with the sum of violations in low sulfur divided 
# by the sum of violations in high sulfur, and another line of mine with the sum of 
# violations in low sulfur divided by the sum of violations in high sulfur

### triple difference sum plot
stack3didrawplot <- function(var, dset, plot_title, outname){
    # var must be a string variable
    df <- dset %>%
            group_by(minehuc_mine, high_sulfur, year) %>%
            summarise(val = mean(.data[[var]], na.rm = TRUE),
                      val_sum = sum(.data[[var]], na.rm = TRUE),
                      .groups="drop")

    collapsed_df <- df %>%
        group_by(minehuc_mine, year) %>%
        summarise(ratio = val_sum[high_sulfur == 0]/val_sum[high_sulfur == 1],
                  groups = "drop")

    plot1 = ggplot(df[df$high_sulfur==0,], aes(x = year, y = val, color = minehuc_mine)) +
    geom_line() +
    labs(title = "Low sulfur HUC12", x = "Year", y = "Share of PWSs") +
    theme_minimal()

    plot2 = ggplot(df[df$high_sulfur==1,], aes(x = year, y = val, color = minehuc_mine)) +
    geom_line() +
    labs(title = "High sulfur HUC12", x = "Year", y = "Share of PWSs") +
    theme_minimal()

    plot3 = ggplot(collapsed_df, aes(x=year, y=ratio, color= minehuc_mine)) +
        geom_line() +
        labs(title = "Ratio", x = "Year", y = "low sulfur/high sulfur viol") +
    theme_minimal()
    plot1 / plot2 / plot3 + plot_annotation(title = plot_title)
    ggsave(outname, height=5, width=5)
}

# MCL 

stack3didrawplot("VIOLATION_CATEGORY_CODE_MCL", full, "MCL", "Z:/ek559/mining_wq/output/fig/mcl_viol_line.png")

# Monitoring 

stack3didrawplot("VIOLATION_CATEGORY_CODE_MR", full, "MR", "Z:/ek559/mining_wq/output/fig/mr_viol_line.png")

# Treatment technique 

stack3didrawplot("VIOLATION_CATEGORY_CODE_TT", full, "TT", "Z:/ek559/mining_wq/output/fig/tt_viol_line.png")

###
### DD and DDD
###

###
### general violations
###

full$minehuc_mine[full$minehuc_mine=='Upstream']<-0
full$minehuc_mine[full$minehuc_mine=='Mine']<-1

### diff in diff gen violation
gen_viol <- list(
    "MCL" = feols(VIOLATION_CATEGORY_CODE_MCL ~ post95*minehuc_mine | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "MR" = feols(VIOLATION_CATEGORY_CODE_MR ~ post95*minehuc_mine | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "TT" = feols(VIOLATION_CATEGORY_CODE_MCL ~ post95*minehuc_mine | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID)
)
modelsummary(gen_viol,
             title = "Difference in Difference of ARP on drinking water violation general categories",
             coef_rename = c("post95:minehuc_mine1" = "post95 x MiningHUC12"),
             escape = TRUE,
             stars = c('*' = .1, '**' = .05, '***' = .01),
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             notes = c("All estimations include PWS and year fixed effects. Standard errors clustered at PWS level.")) |>
format_tt(escape = TRUE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/dd_genviol.tex", overwrite = TRUE)


### triple diff reg type of violations 

gen_viol <- list(
    "MCL" = feols(VIOLATION_CATEGORY_CODE_MCL ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "MR" = feols(VIOLATION_CATEGORY_CODE_MR ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "TT" = feols(VIOLATION_CATEGORY_CODE_MCL ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID)
)
modelsummary(gen_viol,
             title = "Effect of ARP on drinking water violation general categories",
             coef_rename = c("minehuc_mine" = "MiningHUC12", "high_sulfur" = "High Sulfur"),
             escape = TRUE,
             stars = c('*' = .1, '**' = .05, '***' = .01),
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             notes = c("All estimations include PWS and year fixed effects. Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if intake HUC12 has mean sulfur greater than 2 percent.")) |>
format_tt(escape = TRUE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/triple_diff_genviol_discretesulf.tex", overwrite = TRUE)

###
### RULE_FAMILY_CODE
###

fam_viol <- list(
    "Chemicals" = feols(rule_family_chemicals ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "Disinfectants" = feols(rule_family_disinfectants_byproducts ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID),
    "Microbials" = feols(rule_family_microbials ~ post95*minehuc_mine*high_sulfur | PWSID + year,
                             data = full[full$year > 1989 & full$year < 2000, ],
                             cluster = ~ PWSID)
)
modelsummary(fam_viol,
             title = "Effect of ARP on drinking water violation family categories",
             coef_rename = c("minehuc_mine" = "MiningHUC12", "high_sulfur" = "High Sulfur"),
             stars = c('*' = .1, '**' = .05, '***' = .01),
             escape = TRUE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             notes = c("All estimations include PWS and year fixed effects. Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if intake HUC12 has mean sulfur greater than 2 percent.")) |>
format_tt(escape = TRUE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/triple_diff_famviol_discretesulf.tex", overwrite = TRUE)

#######################
### specific pollutants
#######################

full$HUC12[full$minehuc_mine==0]<-'Upstream'
full$HUC12[full$minehuc_mine==1]<-'Mine'

full$high_sulfur <- 0 # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- 1  # Set to 1 where condition is TRUE


####################
# Diff in Diff
####################

###
### diff in diff regression
###

full <- full %>%
  rename("CoalMineHUC12" = minehuc_mine,
         "HighSulfur" = high_sulfur)

full$CoalMineHUC12[full$CoalMineHUC12 =="Mine" ] <- 1
full$CoalMineHUC12[full$CoalMineHUC12 =="Upstream" ] <- 0

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

###
# parallel trends test
###

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
        scale_x_continuous(breaks = c(1985, 1990, 1993, 2000, 2005))

        plotlist[[varname]] <- plot

    }
    # Combine the plots

    combined_plot <- wrap_plots(plotlist, ncol = numcol) +
    plot_annotation(title = plot_title) +
    plot_layout(guides = "collect") & 
    theme(legend.position = "bottom")  # or "right", "top", etc.

    ggsave(outname, combined_plot, height = 5, width = 5)
}

full$CoalMineHUC12[full$CoalMineHUC12 ==1 ] <- "Mine"
full$CoalMineHUC12[full$CoalMineHUC12 ==0 ] <- "Upstream"

stackmineviobytreat(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides",
                        "lead_copper_rule"), 
                      full[full$year>1984 & full$year<2006,], 
                      c("Share of upstream and mine colocated PWSs in violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_mining_viol_raw_line1985to2005.png")

stackmineviobytreat(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"),
                      full[full$year>1984 & full$year<2006,], 
                      c("Share of upstream and mine colocated PWSs in violation"), 
                      c("Total coliforms",
                        "S/g water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/ddparalleltrend_nonmining_viol_raw_line1985to2005.png")

###
# diff in diff regression
###

# mining
mining_pollutants <- list(
    "Nitrates"= feols(nitrates ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Arsenic"=feols(arsenic ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Inorganic chemicals"=feols(inorganic_chemicals ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Radionuclides"=feols(radionuclides ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Lead and copper rule"=feols(lead_copper_rule ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID))

modelsummary(mining_pollutants,
             title = "Effect of ARP on drinking water violation associated with mining",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post95:CoalMineHUC12" = "post95 x CoalMineHUC12"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1990 to 2005.",
                       "Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if PWS intake HUC12 has coal production over sample period.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/diff_diff_miningviol_discretesulf.tex", overwrite = TRUE)

# non mining
non_mining_pollutants <- list(
    "Total coliform"= feols(total_coliform ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Surface/ground water rule"=feols(surface_ground_water_rule ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Volatile organic compounds"=feols(voc ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Synthetic organic compounds"=feols(soc ~ post95*CoalMineHUC12 | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID))

modelsummary(non_mining_pollutants,
             title = "Effect of ARP on drinking water violations not associated with mining",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post95:CoalMineHUC12" = "post95 x CoalMineHUC12", 
                             "post95:HighSulfur" = "post95 x HighSulfur"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1990 to 2005.",
                       "Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if PWS intake HUC12 has coal mining over sample period.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/diff_diff_nonminingviol_discretesulf.tex", overwrite = TRUE)


####################
# Triple diff
####################

###
### within mine high low sulfur violations
###

stackmineviobysulf <- function(varlist, dset, plot_title, vartitle, numcol, outname){
    # stacks a list of violations within minehucs but each line is low sulfur vs high

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        df <- dset %>%
                group_by(high_sulfur, year) %>%
                summarise(val = mean(.data[[varlist[i]]], na.rm = TRUE),
                        .groups="drop")

        plot = ggplot(df, aes(x=year, y=val, color= high_sulfur)) +
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

###
### triple diff parallel trends test
###

stackallvardddrawplot <- function(varlist, dset, plot_title, vartitle, numcol, outname){
    # stacks a list of low/high sulfur ratios from
    # a list of variables

    plotlist <- list()

    for (i in seq_along(varlist)){
        varname <- varlist[i]
        df <- dset %>%
                group_by(HUC12, high_sulfur, year) %>%
                summarise(val = mean(.data[[varlist[i]]], na.rm = TRUE),
                        val_sum = sum(.data[[varlist[i]]], na.rm = TRUE),
                        .groups="drop")
        collapsed_df <- df %>%
            group_by(HUC12, year) %>%
            summarise(ratio = val[high_sulfur == 0]/val[high_sulfur == 1],
                    groups = "drop")
        plot = ggplot(collapsed_df, aes(x=year, y=ratio, color= HUC12)) +
            geom_line() +
            labs(title = vartitle[i], x = "Year", y ="High S/low S") +
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

full$high_sulfur <- "Low sulfur" # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- "high sulfur"  # Set to 1 where condition is TRUE

stackmineviobysulf(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides",
                        "lead_copper_rule"), 
                      full[full$year>1989 & full$year<2006 & full$minehuc_mine==1,], 
                      c("Share of PWSs colocated with mines with mining violation"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/mining_viol_bysulf_raw_line1990to2005.png")

full$high_sulfur <- 0 # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- 1  # Set to 1 where condition is TRUE

stackallvardddrawplot(c("nitrates",
                        "arsenic",
                        "inorganic_chemicals",
                        "radionuclides",
                        "lead_copper_rule"), 
                      full[full$year>1989 & full$year<2006,], 
                      c("Share of PWSs with mining violations: high over low sulfur"), 
                      c("Nitrates",
                        "Arsenic",
                        "Inorg chem",
                        "Radionuclides",
                        "Lead and Copper"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/mining_viol_ratio_raw_line1990to2005.png")

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

full$high_sulfur <- "Low sulfur" # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- "high sulfur"  # Set to 1 where condition is TRUE

stackmineviobysulf(c("total_coliform",
                        "surface_ground_water_rule",
                        "dbpr",
                        "voc",
                        "soc"),
                      full[full$year>1989 & full$year<2006 & full$minehuc_mine==1,], 
                      c("Share PWSs colocated with mines with nonmining violations"), 
                      c("Total coliforms",
                        "S/g water rule",
                        "D+DBP rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/nonmining_viol_bysulf_raw_line1990to2005.png")

full$high_sulfur <- 0 # Initialize the column with 0s
full$high_sulfur[full$sulfur > 2] <- 1  # Set to 1 where condition is TRUE

stackallvardddrawplot(c("total_coliform",
                        "surface_ground_water_rule",
                        "voc",
                        "soc"), 
                      full[full$year>1989 & full$year<2006,], 
                      "Share of PWSs with mining violations: high over low sulfur", 
                      c("Total coliforms",
                        "S/G water rule",
                        "VOCs",
                        "SOCs"),
                      2,
                      "Z:/ek559/mining_wq/output/fig/nonmining_viol_ratio_raw_line1990to2005.png")

###
### triple differences regression
###

full <- full %>%
  rename("CoalMineHUC12" = minehuc_mine,
         "HighSulfur" = high_sulfur)

full$CoalMineHUC12[full$CoalMineHUC12 =="Mine" ] <- 1
full$CoalMineHUC12[full$CoalMineHUC12 =="Upstream" ] <- 0

# mining
mining_pollutants <- list(
    "Nitrates"= feols(nitrates ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Arsenic"=feols(arsenic ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Inorganic chemicals"=feols(inorganic_chemicals ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Radionuclides"=feols(radionuclides ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Lead and copper rule"=feols(lead_copper_rule ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID))

modelsummary(mining_pollutants,
             title = "Effect of ARP on drinking water violation associated with mining",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post95:CoalMineHUC12" = "post95 x CoalMineHUC12", 
                             "post95:HighSulfur" = "post95 x HighSulfur",
                             "post95:CoalMineHUC12:HighSulfur" = "post95 x CoalMineHUC12 x HighSulfur"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1990 to 2005.",
                       "Standard errors clustered at PWS level.", 
                       "MiningHUC12 = 1 if PWS intake HUC12 has coal mining over sample period.",
                       "HighSulfur = 1 if PWS intake HUC12 has mean sulfur greater than 2.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/triple_diff_miningviol_discretesulf.tex", overwrite = TRUE)

# non mining
non_mining_pollutants <- list(
    "Total coliform"= feols(total_coliform ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Surface/ground water rule"=feols(surface_ground_water_rule ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Volatile organic compounds"=feols(voc ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID),
    "Synthetic organic compounds"=feols(soc ~ post95*CoalMineHUC12*HighSulfur | PWSID + year,
                             data = full[full$year>1989 & full$year<2006, ],
                             cluster = ~ PWSID))

modelsummary(non_mining_pollutants,
             title = "Effect of ARP on drinking water violations not associated with mining",
             stars = c('*' = .1, '**' = .05, '***' = .01),
             coef_rename = c("post95:CoalMineHUC12" = "post95 x CoalMineHUC12", 
                             "post95:HighSulfur" = "post95 x HighSulfur",
                             "post95:CoalMineHUC12:HighSulfur" = "post95 x CoalMineHUC12 x HighSulfur"),
             escape = FALSE,
             statistic = "conf.int",
             fmt = "%.3f",
             gof_omit = ".*",
             shape = model + statistic ~ term,
             notes = c("All estimations include PWS and year fixed effects.", 
                       "Data is from 1990 to 2005.",
                       "Standard errors clustered at PWS level.", 
                        "MiningHUC12 = 1 if PWS intake HUC12 has coal mining over sample period.",
                       "HighSulfur = 1 if PWS intake HUC12 has mean sulfur greater than 2.",
                       "Coefficients names are displayed in column headers and dependent variable names in the first column.")) |>
format_tt(escape = FALSE) |>
theme_latex(resize_width= 1, resize_direction="down") |>
save_tt("Z:/ek559/mining_wq/output/reg/triple_diff_nonminingviol_discretesulf.tex", overwrite = TRUE)


