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

########################
# CWS data and analysis
########################
full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")

### PRIOR TO 2006 and AFTER 1985
full <- full[full$year<2006 & full$year>1984,]
full <- full[full$PWSID!="WV3303401",]
full <- full[full$PWSID!="WV3303401",]

# Balance panel: keep only PWSIDs with all 21 observations (1985-2005)
# Balance panel
# 16 rows between 1985 and 2005
full <- full %>%
  group_by(PWSID) %>%
  mutate(total_pwsid_obs = n())
full <- full[full$total_pwsid_obs==21,]

# Binary violation variables
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
