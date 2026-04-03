# spatial kriging

.libPaths("Z:/ek559/RPackages")

install.packages("sf")
install.packages("gstat")
install.packages("tidyverse")
install.packages("tmap")
install.packages("dismo")
install.packages("terra")

library(sf)
library(gstat)
library(tidyverse)
library(tmap)
library(dismo)
library(terra)
library(arrow)
library(readr)
library(dplyr)
library(stringr)

# Coal fields
coal_fields <- st_read("Z:/ek559/mining_wq/raw_data/ncra_coal/GIS/Updated Coal Fields/Coal_Fields.shp")

# convex hull of appalachian region
appalachia <- coal_fields[coal_fields$NAME == "Appalachian Region", ]
#appalachia <- st_union(coal_fields[coal_fields$NAME == "Appalachian Region", ]) 
#appalachia <- st_convex_hull(appalachia)
appalachia <- st_transform(appalachia, crs = 5070)

# create shapefiles from coal qual borehole samples
sample <- read_csv("Z:/ek559/mining_wq/raw_data/coal_qual/CQ2025101314323_sampledetails.CSV", 
                   show_col_types = FALSE)

names(sample) <- str_replace_all(names(sample), " ", "")
names(sample) <- tolower(names(sample))

sample <- sample %>%
  filter(!str_detect(as.character(latitude), "California"))

ult <- read_csv("Z:/ek559/mining_wq/raw_data/coal_qual/CQ20251013152532_proximateultimate.CSV", 
                show_col_types = FALSE)

names(ult) <- str_replace_all(names(ult), " ", "")
names(ult) <- tolower(names(ult))

ult <- ult %>%
  filter(!str_detect(as.character(sulfur), "Maine"),
         !str_detect(as.character(btu), "Michigan"))

samplelocation <- inner_join(ult, sample, by = "sampleid")
samplelocation <- samplelocation %>% filter(!is.na(sulfur))

samplelocation <- st_as_sf(samplelocation, coords = c("longitude", "latitude"), crs = 4326)
samplelocation <- st_transform(samplelocation, crs = 5070)

# which points are within the polygon
intersections <- st_intersects(samplelocation, appalachia)

# Convert to a logical vector: TRUE if the point intersects any polygon
intersects_logical <- lengths(intersections) > 0

# Subset the points
points_in_appalachia <- samplelocation[intersects_logical, ]

# Extract coordinates as a matrix
coords <- st_coordinates(points_in_appalachia)
points_in_appalachia$x <- coords[, "X"]
points_in_appalachia$y <- coords[, "Y"]
# make sure variables are numeric
points_in_appalachia$sulfur <- as.numeric(points_in_appalachia$sulfur)
points_in_appalachia$x <- as.numeric(points_in_appalachia$x)
points_in_appalachia$y <- as.numeric(points_in_appalachia$y)

# Kriging
ggplot(data = appalachia) +
  geom_sf() +
  geom_sf(data = points_in_appalachia, color = "red")

x <- points_in_appalachia %>% 
  st_drop_geometry()

class(x)

# coerce polygon to raster
r <- rast(appalachia)
res(r) <- 100000 # resolution is 10 km since CRS's units are in m

### Linear trend
reg.ols <- glm(sulfur~x + y, 
               data=points_in_appalachia)
summary(reg.ols)

lm.1 <- gstat(formula=sulfur~1, 
              locations=~x+y, 
              degree=1, 
              data=x)
r.m  <- interpolate(r, lm.1, debug.level=0)
r.m <- mask(r.m, appalachia)
plot(r.m, 1)

ggplot(as.data.frame(r.m, xy = TRUE)) +
  geom_raster(aes(x = x, y = y, fill = var1.pred)) +
    labs(fill = "Predicted sulfur") +
    scale_fill_gradient(low= "white", high = "red", na.value ="gray") 

### Kriging 
# variogram
# A variogram cloud characterizes the spatial autocorrelation across a surface 
# that we have sampled at a set of control points. The variogram cloud is obtained 
# by plotting all possible squared differences of observation pairs against their 
# separation distance. As any point in the variogram cloud refers to a pair of 
# points in the data set, the variogram cloud is used to point us to areas with 
# unusual high or low variability. We use the variogram() function, which 
#calculates the sample variogram. Here, we set the lag h to be 20 km through the width argument.

#vcloud <- variogram(sulfur~1, locations=samplelocation, width=20000, cloud = TRUE)
v.o <- variogram(sulfur~1, locations=points_in_appalachia, width=20000, cressie=TRUE)
# plot sample variagram to find the sill, range, and nugget
plot(v.o)
#To generate a model variogram, we need to estimate the following components
#Sill - The sill is the y-value where there is no more spatial correlation, 
# the point on the graph where y-values level off, around 3.5.
#Range - The range is the x-value where the variogram reaches the sill 1000000.
#Nugget- The nugget can be thought of as the y-axis intercept, which occurs at an approximate value of 1.8.

# fitting the variogram theoretical function that determines the influence of near and far locations on the estimation.
# wave converges but doesnt perfectly fit the shape of v.o but matches the upward trend of the data
fve.o <- fit.variogram(v.o, model = vgm(psill = 4.5, model = "Wav", range = 300000, nugget = 2))

plot(variogramLine(fve.o,500000), type='l', ylim=c(0,6), col='blue', main = 'Wave variogram model')
points(v.o[,2:3], pch=20, col='red')

# Interpolate
k.o <- gstat(formula = sulfur~1, 
             locations = ~x+y, 
             data = x, 
             model=fve.o)

kp.o  <- interpolate(r, k.o, debug.level=2)
ok.o <- mask(kp.o, appalachia)
plot(ok.o, 1)

#kp.o  <- interpolate(r, k.o, debug.level=2, cores= 14, cpkgs="gstat")
