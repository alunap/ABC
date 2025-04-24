data {
  int<lower=0> N_precise;  // Number of precise counts
  int<lower=0> N_range;    // Number of range observations
  int<lower=0> N_present;  // Number of "present" observations
  int<lower=0> Y_precise[N_precise];  // Precise count data
  int<lower=0> L_range[N_range];      // Lower bounds for ranges
  int<lower=0> U_range[N_range];      // Upper bounds for ranges
  vector[N_precise + N_range + N_present] temp;  // Temperature covariate
  int<lower=0> N_loc;  // Number of locations
  int<lower=1> loc[N_precise + N_range + N_present];  // Location index
}
parameters {
  real beta0;              // Intercept
  real beta1;              // Temperature effect
  vector[N_loc] alpha;     // Location effects
  real<lower=0> sigma_alpha;  // SD of location effects
  int<lower=0> N_latent[N_range + N_present];  // Latent counts for ranges and present
  vector[N_precise + N_range + N_present] log_effort;  // Latent log-effort
  real mu_E;           // Mean log-effort
  real<lower=0> sigma_E;  // SD of log-effort
}
model {
  mu_E ~ normal(0, 1);      // Prior on mean effort
  sigma_E ~ cauchy(0, 2);   // Prior on effort variation
  log_effort ~ normal(mu_E, sigma_E);  // Random effect for effort
  for (i in 1:(N_precise + N_range + N_present)) {
    log_lambda[i] = beta0 + beta1 * temp[i] + alpha[loc[i]] + log_effort[i];
  }
  Y_precise ~ poisson_log(log_lambda[1:N_precise]);
  // Priors
  beta0 ~ normal(0, 10);
  beta1 ~ normal(0, 10);
  sigma_alpha ~ cauchy(0, 5);
  alpha ~ normal(0, sigma_alpha);

  // Latent rates
  vector[N_precise + N_range + N_present] log_lambda;
  for (i in 1:(N_precise + N_range + N_present)) {
    log_lambda[i] = beta0 + beta1 * temp[i] + alpha[loc[i]];
  }

  // Likelihoods
  Y_precise ~ poisson_log(log_lambda[1:N_precise]);  // Precise counts
  for (i in 1:N_range) {  // Range data
    target += poisson_log_lpmf(N_latent[i] | log_lambda[N_precise + i]);
    N_latent[i] ~ uniform(L_range[i], U_range[i]);  // Constrain within range
  }
  for (i in 1:N_present) {  // "Present" data
    target += poisson_log_lccdf(0 | log_lambda[N_precise + N_range + i]);  // P(N >= 1)
  }
}