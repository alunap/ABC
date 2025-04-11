# Load necessary libraries
library(tidyverse)

# Set seed for reproducibility
set.seed(123)

# Simulate data structure (fake covariates for illustration)
n_obs <- 100  # Number of observations
n_locations <- 5  # Number of unique locations
data <- data.frame(
  location = sample(1:n_locations, n_obs, replace = TRUE),
  temperature = rnorm(n_obs, mean = 20, sd = 5),  # Temp in Celsius
  effort = rexp(n_obs, rate = 0.5)  # Effort (e.g., visits, exponential for skew)
)

# Function to generate prior predictive samples
prior_predictive <- function(n_samples, data) {
  # Sample parameters from priors
  beta0 <- rnorm(n_samples, mean = 2, sd = 1)  # Intercept
  beta1 <- rnorm(n_samples, mean = 0, sd = 0.5)  # Temp effect
  beta2 <- rnorm(n_samples, mean = 1, sd = 0.5)  # Effort effect
  sigma_alpha <- abs(rcauchy(n_samples, scale = 1))  # Location variability
  
  # Sample location effects for each unique location
  alpha <- matrix(nrow = n_samples, ncol = n_locations)
  for (j in 1:n_samples) {
    alpha[j, ] <- rnorm(n_locations, mean = 0, sd = sigma_alpha[j])
  }
  
  # Generate prior predictive counts
  counts <- matrix(nrow = n_samples, ncol = nrow(data))
  for (i in 1:n_samples) {
    log_lambda <- beta0[i] + 
      beta1[i] * data$temperature + 
      beta2[i] * log(data$effort) +  # Log effort for positivity
      alpha[i, data$location]
    lambda <- exp(log_lambda)
    counts[i, ] <- rpois(nrow(data), lambda)
  }
  
  return(counts)
}

# Generate 1000 prior predictive samples
n_samples <- 1000
prior_counts <- prior_predictive(n_samples, data)

# Summarize results
prior_summary <- data.frame(
  observation = rep(1:nrow(data), each = n_samples),
  count = as.vector(prior_counts)
) %>%
  group_by(observation) %>%
  summarise(
    mean_count = mean(count),
    lower_95 = quantile(count, 0.025),
    upper_95 = quantile(count, 0.975)
  )

# Add original covariates for context
prior_summary <- bind_cols(prior_summary, data)

# Plot prior predictive distribution
ggplot(prior_summary, aes(x = observation, y = mean_count)) +
  geom_point() +
  geom_errorbar(aes(ymin = lower_95, ymax = upper_95), width = 0.2) +
  labs(title = "Prior Predictive Distribution of Bird Counts",
       y = "Predicted Count (95% Interval)", x = "Observation Index") +
  theme_minimal()

# Histogram of all counts
ggplot(data.frame(count = as.vector(prior_counts)), aes(x = count)) +
  geom_histogram(bins = 10, fill = "skyblue", color = "black") +
  labs(title = "Histogram of Prior Predictive Counts", x = "Bird Count") +
  theme_minimal()
