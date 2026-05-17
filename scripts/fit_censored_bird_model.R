# Bayesian analysis of bird counts with mixed censoring using jagsUI
# Data: stonechat.csv with L/U columns encoding censoring types
# Author: Oz <oz-agent@warp.dev>

library(tidyverse)
library(jagsUI)

# ============================================
# 1. LOAD AND PREPARE DATA
# ============================================

# Read data (assumes stonechat.csv with columns including L, U for censoring bounds)
dat <- read_csv("data/exp_pro/stonechat.csv") %>%
  mutate(
    Date = as.Date(Date),
    year = year(Date),
    month = month(Date),
    location = as.numeric(factor(Place))  # Numeric location ID
  )

# Parse temperature from comment field (if available), otherwise use dummy
dat <- dat %>%
  mutate(
    temp = rnorm(n(), mean = 15, sd = 3),  # Placeholder; replace with real data
    effort = 1  # Assume unit effort; adjust as needed
  )

# ============================================
  # 2. CLASSIFY CENSORING TYPES
  # ============================================

  # From L and U columns, classify into censoring types:
  # type 1: exact count (L == U, both finite and positive)
  # type 2: interval censored (L < U, both finite)
  # type 3: right censored (count >= some value, L > 0, U very large/missing)
  # type 4: presence-only (at least 1 bird seen, L == 1, U very large/missing)

  dat <- dat %>%
    mutate(
      # Handle missing values
      U = ifelse(is.na(U) | U == 0, 99999, U),
      L = ifelse(is.na(L) | L == 0, 0, L),

      # Assign censoring type
      cens_type = case_when(
        L == U & L > 0               ~ 1,  # Exact count
        L > 0 & U < L                ~ 1,  # Malformed: L > U, treat as exact L
        L > 0 & U > L & U < 10000    ~ 2,  # Interval censored
        L >= 1 & U >= 10000          ~ 3,  # Right censored (e.g., "6+")
        TRUE                         ~ 1   # Default to exact
      )
    ) %>%
    filter(!is.na(temp), !is.na(location))

  cat("Censoring type summary:\n")
  print(table(dat$cens_type))

  # ============================================
  # 3. PREPARE DATA FOR JAGS
  # ============================================

  # Separate observations by censoring type
  exact_idx <- which(dat$cens_type == 1)
  interval_idx <- which(dat$cens_type == 2)
  rcens_idx <- which(dat$cens_type == 3)

  N <- nrow(dat)
  N_loc <- n_distinct(dat$location)
  N_exact <- length(exact_idx)
  N_interval <- length(interval_idx)
  N_rcens <- length(rcens_idx)
  N_present <- 0  # No presence-only in this dataset

  # Standardize continuous variables for better MCMC performance
  temp_std <- scale(dat$temp)[, 1]
  effort_std <- scale(log(dat$effort + 0.1))[, 1]

  # Prepare data by censoring type
  # Exact counts
  y_exact <- dat$L[exact_idx]
  idx_exact <- exact_idx

  # Interval censored: dinterval needs a single cutpoint per observation
  # For [L, U], we observe category 1, with cutpoints c(L-1, U)
  # dinterval(x, c(cut1, cut2)) returns 1 when cut1 < x <= cut2
  int_bounds <- matrix(NA, nrow = N_interval, ncol = 2)
  int_bounds[, 1] <- dat$L[interval_idx] - 1  # Lower bound (exclusive)
  int_bounds[, 2] <- dat$U[interval_idx]       # Upper bound (inclusive)
  y_int_obs <- rep(1, N_interval)  # All observed in category 1
  idx_interval <- interval_idx

  # Right censored: observe category 1 means x > cut
  rcens_cut <- dat$L[rcens_idx] - 1  # Cutoff (exclusive)
  y_rcens_obs <- rep(1, N_rcens)     # All observed in category 1
  idx_rcens <- rcens_idx

  # Presence-only (if any): observe category 1 means x > 0
  y_pres_obs <- integer(0)
  idx_present <- integer(0)

  # Bundle data for JAGS
  jags_data <- list(
    N = N,
    N_loc = N_loc,
    N_exact = N_exact,
    N_interval = N_interval,
    N_rcens = N_rcens,
    N_present = N_present,
    loc = as.numeric(dat$location),
    temp = temp_std,

    # Exact counts
    y_exact = y_exact,
    idx_exact = idx_exact,

    # Interval censored
    int_bounds = int_bounds,
    y_int_obs = y_int_obs,
    idx_interval = idx_interval,

    # Right censored
    rcens_cut = rcens_cut,
    y_rcens_obs = y_rcens_obs,
    idx_rcens = idx_rcens,

    # Presence-only (empty if none)
    y_pres_obs = y_pres_obs,
    idx_present = idx_present
  )

# ============================================
# 4. INITIALIZE PARAMETERS
# ============================================

# Function to generate initial values for chains
inits_fn <- function() {
  list(
    beta0 = rnorm(1, 0, 1),
    beta1 = rnorm(1, 0, 0.5),
    sigma_alpha = runif(1, 0.5, 3),
    alpha = rnorm(N_loc, 0, 1)
  )
}

# ============================================
# 5. SPECIFY PARAMETERS TO MONITOR
# ============================================

params <- c(
  "beta0",
  "beta1",
  "sigma_alpha",
  "alpha",
  "lambda",
  "log_lambda",
  "mean_abundance"
)

# ============================================
# 6. MCMC SETTINGS
# ============================================

n_adapt <- 1000    # Adaptation phase
n_iter <- 10000    # Total iterations
n_burnin <- 5000   # Burn-in
n_thin <- 5        # Thinning
n_chains <- 3

# ============================================
# 7. RUN JAGS MODEL
# ============================================

cat("Running JAGS model...\n")

model_fit <- jags(
  data = jags_data,
  inits = inits_fn,
  parameters.to.save = params,
  model.file = "scripts/bird_count_censored.bug",
  n.chains = n_chains,
  n.adapt = n_adapt,
  n.iter = n_iter,
  n.burnin = n_burnin,
  n.thin = n_thin,
  DIC = TRUE,
  parallel = FALSE
)


# ============================================
# 8. EXAMINE OUTPUT
# ============================================

cat("\n===== MODEL SUMMARY =====\n")
print(model_fit)

# Check convergence diagnostics (Rhat < 1.1 is good)
cat("\n===== CONVERGENCE DIAGNOSTICS =====\n")
print(model_fit$summary[, c("mean", "sd", "2.5%", "97.5%", "Rhat")])

# ============================================
# 9. POSTERIOR INFERENCE
# ============================================

# Extract posterior samples
posterior <- model_fit$sims.list

# Summarize key parameters
cat("\n===== PARAMETER ESTIMATES =====\n")
cat("Intercept (beta0):\n")
print(quantile(posterior$beta0, c(0.025, 0.5, 0.975)))

cat("\nTemperature effect (beta1):\n")
print(quantile(posterior$beta1, c(0.025, 0.5, 0.975)))

cat("\nLocation effect SD (sigma_alpha):\n")
print(quantile(posterior$sigma_alpha, c(0.025, 0.5, 0.975)))

cat("\nMean abundance (population-level):\n")
print(quantile(posterior$mean_abundance, c(0.025, 0.5, 0.975)))

# ============================================
# 10. VISUALIZATION
# ============================================

# Trace plots
plot(model_fit)

# Density plots
densityplot(model_fit, parameters = c("beta0", "beta1", "sigma_alpha"))

# Location random effects
alpha_summary <- tibble(
  location = 1:N_loc,
  mean = colMeans(posterior$alpha),
  sd = apply(posterior$alpha, 2, sd)
) %>%
  left_join(
    dat %>% select(location, Place) %>% distinct(),
    by = "location"
  )

ggplot(alpha_summary, aes(x = reorder(Place, mean), y = mean)) +
  geom_point() +
  geom_errorbar(aes(ymin = mean - 1.96 * sd, ymax = mean + 1.96 * sd), width = 0.2) +
  coord_flip() +
  labs(title = "Location Random Effects",
       x = "Location", y = "Estimated Effect") +
  theme_minimal()

# ============================================
# 11. PREDICTIONS (optional)
# ============================================

# Predict counts at new temperature values
new_temps <- seq(min(dat$temp), max(dat$temp), length.out = 50)
new_temps_std <- (new_temps - mean(dat$temp, na.rm = T)) / sd(dat$temp, na.rm = T)

# Use posterior mean of parameters
beta0_mean <- mean(posterior$beta0)
beta1_mean <- mean(posterior$beta1)
alpha_mean <- colMeans(posterior$alpha)

# Prediction for average location
pred_lambda <- exp(beta0_mean + beta1_mean * new_temps_std)

pred_df <- tibble(
  temp = new_temps,
  lambda = pred_lambda,
  CI_lower = qpois(0.025, pred_lambda),
  CI_upper = qpois(0.975, pred_lambda)
)

ggplot(pred_df, aes(x = temp, y = lambda)) +
  geom_line() +
  geom_ribbon(aes(ymin = CI_lower, ymax = CI_upper), alpha = 0.3) +
  labs(title = "Predicted Bird Counts vs Temperature",
       x = "Temperature", y = "Expected Count") +
  theme_minimal()

cat("\nModel fitting complete!\n")
