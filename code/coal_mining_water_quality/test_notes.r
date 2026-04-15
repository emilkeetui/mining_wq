.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 1] <- "Upstream of mining"
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 0] <- "Colocated/Downstream of mining"
full <- full %>% group_by(PWSID) %>% mutate(total_pwsid_obs = n())
full <- full[full$total_pwsid_obs == 21, ]

move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")

  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"

  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)

  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)

  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   ", trimws(note_block)), x, fixed = TRUE)
  x
}

dset  <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]
y     <- "nitrates_share_days"
dat_y <- dset[(dset[[y]] > 0) | (dset$no_violation == 1), ]

mod_ols <- feols(as.formula(paste0(y, " ~ num_coal_mines_upstream + num_facilities | PWSID + STATE_CODE + year")), data = dat_y, cluster = ~PWSID)
mod_rf  <- feols(as.formula(paste0(y, " ~ post95*sulfur_unified + num_facilities | PWSID + STATE_CODE + year")), data = dat_y, cluster = ~PWSID)
mod_iv  <- feols(as.formula(paste0(y, " ~ num_facilities | PWSID + STATE_CODE + year | num_coal_mines_upstream ~ post95*sulfur_unified")), data = dat_y, cluster = ~PWSID)

etable(mod_ols, mod_rf, mod_iv,
       fitstat         = ~ . + ivf1,
       style.tex       = style.tex("aer", adjustbox = TRUE),
       tex             = TRUE,
       drop            = "^(num_facilities)$",
       title           = "Test table",
       label           = "test",
       notes           = "This note should appear at the bottom below the adjustbox.",
       postprocess.tex = move_notes_below_adjustbox,
       file            = "Z:/ek559/mining_wq/output/reg/test_notes.tex")

cat(readLines("Z:/ek559/mining_wq/output/reg/test_notes.tex"), sep = "\n")
