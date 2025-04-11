# Clean data and explore it
library(tidyverse)
data <- read.csv("data/exp_raw/ABC_2000_2022.csv")
summary(data)
ggplot(data, aes(x = year, y = bird_count, color = location)) + geom_line()

library(rstanarm)
model <- stan_glmer(bird_count ~ temperature + (1 | location) + (1 | year),
                    family = poisson(link = "log"),
                    data = data,
                    prior = normal(0, 10),
                    prior_intercept = normal(0, 10))
summary(model)

posterior <- as.data.frame(model)
mean_beta1 <- mean(posterior$temperature)
ci_beta1 <- quantile(posterior$temperature, c(0.025, 0.975))
cat("Temperature effect:", mean_beta1, "95% CI:", ci_beta1)

library(dagitty)
dag <- dagitty("dag { Temperature -> BirdCount; Habitat -> BirdCount; Temperature -> Habitat }")
adjustmentSets(dag, "Temperature", "BirdCount")  # Might suggest adjusting for Habitat

model_causal <- stan_glmer(bird_count ~ temperature + habitat + (1 | location) + (1 | year),
                           family = poisson(link = "log"),
                           data = data)

# If you have an intervention at certain locations, eg conservation policy
model_did <- stan_glmer(bird_count ~ temperature + treated * post + (1 | location) + (1 | year),
                        family = poisson(link = "log"),
                        data = data)

pp_check(model)  # Compare observed vs. predicted counts

