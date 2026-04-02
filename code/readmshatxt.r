# read msha mine data in txt and save in parquet
.libPaths("Z:/ek559/RPackages")
install.packages('arrow')
library(arrow)

# quarterly production
minesprod <- read.delim("Z:/ek559/mining_wq/msha_data/MinesProdQuarterly.txt", sep = "|", quote = "\"", stringsAsFactors = FALSE)
colnames(minesprod) <- tolower(colnames(minesprod))
write_parquet(minesprod, "Z:/ek559/mining_wq/msha_data/minesprodquarterly.parquet")
write.csv(minesprod, "Z:/ek559/mining_wq/msha_data/minesprodquarterly.csv", row.names = FALSE)

# mines
mines <- read.delim("Z:/ek559/mining_wq/msha_data/Mines.txt", sep = "|", quote = "\"", stringsAsFactors = FALSE)
mines$DIRECTIONS_TO_MINE <- NULL
colnames(mines) <- tolower(colnames(mines))
write_parquet(mines, "Z:/ek559/mining_wq/msha_data/mines.parquet")
write.csv(mines, "Z:/ek559/mining_wq/msha_data/mines.csv", row.names = FALSE)

# waterquality
watsys <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv")

viol <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv")
