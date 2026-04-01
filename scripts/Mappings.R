library(tidyverse)
library(sf) # for spatial objects
library(ggplot2)

# Read data
birds <- read_csv("data/exp_raw/ABC_2000_2022.csv",
  col_types = cols_only(
    Species = col_guess(),
    Date = col_guess(),
    Gridref = col_guess(),
    Place = col_guess(),
    Count = col_guess()
  )
)

# --- Helread_csv2()# --- Helper: parse OS grid ref to full easting/northing (OSGB36) ---
os_to_en <- function(gridref) {
  # 100km square letter codes (origin at false origin SW of Scilly Isles)
  squares <- list(
    S = c(0, 0), T = c(5, 0),
    N = c(0, 5), O = c(5, 5), P = c(10, 5),
    H = c(0, 10), J = c(5, 10),
    SV = c(0, 0), SW = c(1, 0), SX = c(2, 0), SY = c(3, 0), SZ = c(4, 0),
    TV = c(5, 0), TW = c(6, 0),
    SR = c(1, 1), SS = c(2, 1), ST = c(3, 1), SU = c(4, 1), TQ = c(5, 1), TR = c(6, 1),
    SM = c(1, 2), SN = c(2, 2), SO = c(3, 2), SP = c(4, 2), TL = c(5, 2), TM = c(6, 2),
    SH = c(1, 3), SJ = c(2, 3), SK = c(3, 3), TF = c(5, 3), TG = c(6, 3),
    SC = c(1, 4), SD = c(2, 4), SE = c(3, 4), TA = c(5, 4),
    NW = c(1, 6), NX = c(2, 6), NY = c(3, 6), NZ = c(4, 6), OV = c(5, 6),
    NR = c(2, 7), NS = c(3, 7), NT = c(4, 7), NU = c(5, 7),
    NL = c(1, 8), NM = c(2, 8), NN = c(3, 8), NO = c(4, 8),
    NF = c(1, 9), NG = c(2, 9), NH = c(3, 9), NJ = c(4, 9), NK = c(5, 9),
    NB = c(2, 10), NC = c(3, 10), ND = c(4, 10),
    HW = c(2, 11), HX = c(3, 11), HY = c(4, 11), HZ = c(5, 11),
    HT = c(3, 12), HU = c(4, 12),
    HP = c(4, 13)
  )

  sq <- substr(gridref, 1, 2)
  num <- substr(gridref, 3, nchar(gridref))
  digits_each <- nchar(num) / 2

  en <- squares[[sq]]
  e_100km <- en[1] * 100000
  n_100km <- en[2] * 100000

  # For a 4-digit ref (2+2), each digit = 1km; centre = +500m
  e <- e_100km + as.numeric(substr(num, 1, digits_each)) * 10^(5 - digits_each) +
    10^(5 - digits_each) / 2
  n <- n_100km + as.numeric(substr(num, digits_each + 1, nchar(num))) * 10^(5 - digits_each) +
    10^(5 - digits_each) / 2

  c(easting = e, northing = n)
}

# --- Convert a vector of grid refs to WGS84 ---
gridrefs_to_wgs84 <- function(refs) {
  coords <- t(sapply(refs, os_to_en))

  pts <- st_as_sf(
    data.frame(easting = coords[, "easting"], northing = coords[, "northing"]),
    coords = c("easting", "northing"),
    crs = 27700 # OSGB36 / British National Grid (EPSG:27700)
  )

  pts_wgs84 <- st_transform(pts, crs = 4326) # WGS84
  coords_wgs84 <- st_coordinates(pts_wgs84)

  data.frame(
    gridref   = refs,
    longitude = coords_wgs84[, "X"],
    latitude  = coords_wgs84[, "Y"]
  )
}
drop_na(birds, Gridref)

birds <- cbind(birds, gridrefs_to_wgs84(birds$Gridref)[, c("latitude", "longitude")])
