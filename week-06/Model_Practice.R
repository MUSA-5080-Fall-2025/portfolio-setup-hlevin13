# Load packages and data
library(tidyverse)
library(sf)
library(here)

boston <- read_csv(here("data/boston.csv"))
crime <- read_csv(here("data/bostonCrimes.csv"))

boston.sf <- boston %>%
  st_as_sf(coords = c("Longitude", "Latitude"), crs = 4326) %>%
  st_transform('ESRI:102286')  # MA State Plane (feet)


#simple model/structural
baseline_model <- lm(SalePrice ~ LivingArea, data = boston)
summary(baseline_model)

#practice best model
best_model <- lm(SalePrice ~ Living Area * wealthy_neighborhood + name_cv, data*boston.sf) 
summary (best_model)



