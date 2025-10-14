# Load packages and data
library(tidyverse)
library(sf)
library(here)

# Load Boston housing data
boston <- read_csv(here("data/boston.csv"))
crime <- read_csv(here("data/bostonCrimes.csv"))

crime.sf <- crime %>%
  st_as_sf(coords = c("Longitude", "Latitude"), crs = 4326) %>%
  st_transform('ESRI:102286')  # MA State Plane (feet)

# Quick look at the data
glimpse(boston)

# Simple model: Predict price from living area
baseline_model <- lm(SalePrice ~ LivingArea, data = boston)
summary(baseline_model)

# Add number of bathrooms
better_model <- lm(SalePrice ~ LivingArea + R_FULL_BTH, data = boston)
summary(better_model)

# Compare models
cat("Baseline R²:", summary(baseline_model)$r.squared, "\n")

cat("With bathrooms R²:", summary(better_model)$r.squared, "\n")

library(sf)

# Convert boston data to sf object
boston.sf <- boston %>%
  st_as_sf(coords = c("Longitude", "Latitude"), crs = 4326) %>%
  st_transform('ESRI:102286')  # MA State Plane (feet)

# Check it worked
head(boston.sf)

class(boston.sf)  # Should show "sf" and "data.frame"

# Load neighborhood boundaries
nhoods <- read_sf(here("data/BPDA_Neighborhood_Boundaries.geojson")) %>%
  st_transform('ESRI:102286')  # Match CRS!

# Check the neighborhoods
head(nhoods)

nrow(nhoods)  # How many neighborhoods?

# Spatial join: Assign each house to its neighborhood
boston.sf <- boston.sf %>%
  st_join(nhoods, join = st_intersects)

# Check results
boston.sf %>%
  st_drop_geometry() %>%
  count(name) %>%
  arrange(desc(n))

# Which neighborhoods are most expensive?
price_by_nhood %>%
  arrange(desc(median_price)) %>%
  head(5)

# Which have most sales?
price_by_nhood %>%
  arrange(desc(n_sales)) %>%
  head(5)

# Ensure name is a factor
boston.sf <- boston.sf %>%
  mutate(name = as.factor(name))

# Check which is reference (first alphabetically)
levels(boston.sf$name)[1]

# Fit model with neighborhood fixed effects
model_neighborhoods <- lm(SalePrice ~ LivingArea + name, 
                          data = boston.sf)

# Show just first 10 coefficients
summary(model_neighborhoods)$coef[1:10, ]

# Define wealthy neighborhoods based on median prices
wealthy_hoods <- c("Back Bay", "Beacon Hill", "South End", "Bay Village")

# Create binary indicator
boston.sf <- boston.sf %>%
  mutate(
    wealthy_neighborhood = ifelse(name %in% wealthy_hoods, "Wealthy", "Not Wealthy"),
    wealthy_neighborhood = as.factor(wealthy_neighborhood)
  )

# Check the split
boston.sf %>%
  st_drop_geometry() %>%
  count(wealthy_neighborhood)

# Model assumes same slope everywhere
model_no_interact <- lm(SalePrice ~ LivingArea + wealthy_neighborhood, 
                        data = boston.sf)

summary(model_no_interact)$coef

# Model allows different slopes
model_interact <- lm(SalePrice ~ LivingArea * wealthy_neighborhood, 
                     data = boston.sf)

summary(model_interact)$coef

# Compare R-squared
cat("Model WITHOUT interaction R²:", round(summary(model_no_interact)$r.squared, 4), "\n")
cat("Model WITH interaction R²:", round(summary(model_interact)$r.squared, 4), "\n")
cat("Improvement:", round(summary(model_interact)$r.squared - summary(model_no_interact)$r.squared, 4), "\n")

# Calculate age from year built
boston.sf <- boston.sf %>%
  mutate(Age = 2025 - YR_BUILT)%>% filter(Age <2000)


# Check the distribution of age
summary(boston.sf$Age)

# Visualize age distribution
ggplot(boston.sf, aes(x = Age)) +
  geom_histogram(bins = 30, fill = "steelblue", alpha = 0.7) +
  labs(title = "Distribution of House Age in Boston",
       x = "Age (years)",
       y = "Count") +
  theme_minimal()

# Simple linear relationship
model_age_linear <- lm(SalePrice ~ Age + LivingArea, data = boston.sf)

summary(model_age_linear)$coef

# Quadratic model (Age²)
model_age_quad <- lm(SalePrice ~ Age + I(Age^2) + LivingArea, data = boston.sf)

summary(model_age_quad)$coef

# R-squared comparison
r2_linear <- summary(model_age_linear)$r.squared
r2_quad <- summary(model_age_quad)$r.squared

cat("Linear model R²:", round(r2_linear, 4), "\n")
cat("Quadratic model R²:", round(r2_quad, 4), "\n")
cat("Improvement:", round(r2_quad - r2_linear, 4), "\n\n")

# F-test: Is the Age² term significant?
anova(model_age_linear, model_age_quad)

# Compare residual plots
par(mfrow = c(1, 2))

# Linear model residuals
plot(fitted(model_age_linear), residuals(model_age_linear),
     main = "Linear Model Residuals",
     xlab = "Fitted Values", ylab = "Residuals")
abline(h = 0, col = "red", lty = 2)

# Quadratic model residuals  
plot(fitted(model_age_quad), residuals(model_age_quad),
     main = "Quadratic Model Residuals",
     xlab = "Fitted Values", ylab = "Residuals")
abline(h = 0, col = "red", lty = 2)

# Create buffer features - these will work now that CRS is correct
boston.sf <- boston.sf %>%
  mutate(
    crimes.Buffer = lengths(st_intersects(
      st_buffer(geometry, 660),
      crimes.sf
    )),
    crimes_500ft = lengths(st_intersects(
      st_buffer(geometry, 500),
      crimes.sf
    ))
  )

# Check it worked
#summary(boston.sf$crimes.Buffer)


# Calculate distance matrix (houses to crimes)
dist_matrix <- st_distance(boston.sf, crimes.sf)

# Function to get mean distance to k nearest neighbors
get_knn_distance <- function(dist_matrix, k) {
  apply(dist_matrix, 1, function(distances) {
    # Sort and take first k, then average
    mean(as.numeric(sort(distances)[1:k]))
  })
}

# Create multiple kNN features
boston.sf <- boston.sf %>%
  mutate(
    crime_nn1 = get_knn_distance(dist_matrix, k = 1),
    crime_nn3 = get_knn_distance(dist_matrix, k = 3),
    crime_nn5 = get_knn_distance(dist_matrix, k = 5)
  )

# Check results
summary(boston.sf %>% st_drop_geometry() %>% select(starts_with("crime_nn")))

# Which k value correlates most with price?
boston.sf %>%
  st_drop_geometry() %>%
  select(SalePrice, crime_nn1, crime_nn3, crime_nn5) %>%
  cor(use = "complete.obs") %>%
  as.data.frame() %>%
  select(SalePrice)

# Define downtown Boston (Boston Common: 42.3551° N, 71.0656° W)
downtown <- st_sfc(st_point(c(-71.0656, 42.3551)), crs = "EPSG:4326") %>%
  st_transform('ESRI:102286')

# Calculate distance from each house to downtown
boston.sf <- boston.sf %>%
  mutate(
    dist_downtown_ft = as.numeric(st_distance(geometry, downtown)),
    dist_downtown_mi = dist_downtown_ft / 5280
  )

# Summary
summary(boston.sf$dist_downtown_mi)

# Summary of all spatial features created
spatial_summary <- boston.sf %>%
  st_drop_geometry() %>%
  select(crimes.Buffer, crimes_500ft, crime_nn3, dist_downtown_mi) %>%
  summary()

spatial_summary

boston.sf <- boston.sf %>%
  mutate(Age = 2015 - YR_BUILT)  

# Model 1: Structural only
model_structural <- lm(SalePrice ~ LivingArea + R_BDRMS + Age, 
                       data = boston.sf)

# Model 2: Add spatial features
model_spatial <- lm(SalePrice ~ LivingArea + R_BDRMS + Age +
                      crimes_500ft + crime_nn3 + dist_downtown_mi,
                    data = boston.sf)

# Compare
cat("Structural R²:", round(summary(model_structural)$r.squared, 4), "\n")
cat("With spatial R²:", round(summary(model_spatial)$r.squared, 4), "\n")
cat("Improvement:", round(summary(model_spatial)$r.squared - 
                            summary(model_structural)$r.squared, 4), "\n")