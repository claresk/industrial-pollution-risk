# Modeling

# This script reads in the census data pulled in part one and joins it with the air pollution data. 
# It then generates and plots a correlation matrix relating air pollution to census demographic 
# variables, then creates a spatial model relating that data. It then reads in the school proximity 
# group data, runs a series of t-tests relating it to census demographic variables, and creates a 
# log model of the data. Next, it reads in the full school proximity data, creates a correlation 
# matrix relating it to census demographic variables, and creates another spatial model. Finally, 
# the script reads in the historical neighborhood grade data and conducts an ANOVA test relating 
# it to school-to-facility proximity.





# loading packages and installing as needed
safe_library <- function(package_name) {
  if (!require(package_name, character.only = TRUE)) {
    install.packages(package_name)
    library(package_name, character.only = TRUE)
  }
}
safe_library("dplyr")
safe_library("stringr")
safe_library("tidyr")
safe_library("here")
here::i_am("5_modeling.Rmd")
safe_library("sf")
safe_library("spdep")
safe_library("spatialreg")
safe_library("corrplot")



# Reading in census and EPA data

### reading census data file (pulled in R)
cens_cl <- read_sf("cens_demg_R/cens_demg_R.shp")

### reading epa rsei data (pulled in python) and cleaning GEOID field for merge with census data
rsei <- read.csv("rsei_cens.csv") %>%
  rename("GEOID" = "GeoID") %>%
  mutate(GEOID = as.character(GEOID))
rsei$GEOID <- str_pad(rsei$GEOID, width=11, side="left", pad="0")

### merging census data with epa rsei data
rsei_demg <- merge(cens_cl, rsei, all=TRUE)



# Relating toxicity concentration & demographics


## Correlation matrix

### cleaning merged file to only show variables for correlations
rsei_demg_num <- st_drop_geometry(rsei_demg) %>%
  select(
    Bch_pct, 
    HHIncm_, 
    Unmply_,
    Bl150PL, 
    Mnf_pct, 
    Asn_pct, 
    Blck_pc, 
    Hspnc_p, 
    Wht_pct, 
    MedinAg, 
    MdnHmVl, 
    MdnIncm, 
    Ppltn_s, 
    NumFacs, 
    NumReleases, 
    NumChems, 
    ToxConc 
  ) %>%
  rename(
    "% Bachelor's degree or higher" = Bch_pct,
    "Household income" = HHIncm_,
    "% Unemployment" = Unmply_,
    "% Below 150% of the poverty line" = Bl150PL,
    "% Manufacturing workers" = Mnf_pct,
    "% Asian" = Asn_pct,
    "% Black" = Blck_pc,
    "% Hispanic" = Hspnc_p,
    "% White" = Wht_pct,
    "Median age" = MedinAg,
    "Median home value" = MdnHmVl,
    "Median income" = MdnIncm,
    "Population size" = Ppltn_s,
    "Number of nearby facilities" = NumFacs,
    "Number of chemical releases" = NumReleases,
    "Number of chemicals" = NumChems,
    "Toxicity concentration" = ToxConc
  )  %>%
  drop_na()

cplt1 <- corrplot(
  cor(rsei_demg_num), 
  type = "upper", 
  tl.col = "black", 
  tl.srt = 45, 
  method = 'ellipse', 
  addCoef.col = 'black', 
  number.cex = 0.5, 
  tl.cex = 0.8, 
  cl.pos = 'n'
)


## Spatial model of toxicity concentration

### selecting relevant variables for model and dropping nulls
rsei_demgS <- rsei_demg %>% 
  select(
    ToxConc, 
    Wht_pct, 
    MedinAg, 
    MdnIncm, 
    Ppltn_s, 
    MdnHmVl, 
    Mnf_pct
  ) %>%
  drop_na()

### removing rows where there is no spatial data   
rsei_demgS <- rsei_demgS[!st_is_empty(rsei_demgS),]

### creating spatial weights
neighbors <- poly2nb(
  pl = rsei_demgS,
  queen = TRUE)

listweights <- nb2listw(
  neighbours = neighbors,
  style = "W",
  zero.policy = TRUE)

### calculating global moran's I (spatial auto-correlation)
global_moran <- moran.test(
  x = rsei_demgS$ToxConc, 
  listw = listweights, 
  randomisation = TRUE,
  alternative = "greater",
  na.action = na.omit,
  zero.policy = TRUE)

### printing results and plotting autocorrelation chart
print(global_moran)
moran.plot(x = rsei_demgS$ToxConc, 
           listw = listweights,
           zero.policy = FALSE)

### The Moran's I test calculates a value of 0.4, meaning there is modest spatial 
### autocorrelation in the data.

### formula for spatial model
formula <- as.formula(
  ToxConc ~ Wht_pct + MedinAg + MdnIncm + Ppltn_s + MdnHmVl + Mnf_pct)

### conventional OLS model
ols_model <- lm(formula = formula, data = rsei_demgS)
summary(ols_model)

### spatial lag model
spatial_model <- lagsarlm(
  formula = formula, 
  data = rsei_demgS, 
  listw = listweights, 
  zero.policy = TRUE, 
  na.action = na.omit,
  method = "Matrix")
summary(spatial_model)

### Predictably, the spatial model improves the OLS model slightly (smaller AIC), 
### and the coefficients all have statistically significant contributions. However, 
### the R^2 value is quite small (0.004), meaning that the model does not explain 
### the vast majority of the variance in the data.



# Relating school-to-facility proximity & demographics


## Proximity groups (5 km)

### Reading in proximity group data processed with ArcGIS.
### This data has been spatially joined with underlying census data and separated 
### into proximty groups using a 5 km cutoff.

### reading in school data from gdb
SCH_5km <- sf::st_read("industrial-pollution-risk.gdb", layer = "SCH_5km")
SCH_over5km <- sf::st_read("industrial-pollution-risk.gdb", layer = "SCH_over5km")

### labeling schools as <5 km or >5 km from an industrial facility
SCH_5km$prox <- "<5km"
SCH_over5km$prox <- ">5km"
SCH_prox <- bind_rows(SCH_5km, SCH_over5km) 

### Testing differences in means between proximity groups.
### I would like to conduct a test comparing mean demographic characteristics 
### between proximity groups, so I need to check the assumptions for a test like
### ANOVA, which presupposes a normal distribution and equal variances.

### function to check for normal distribution
check_norm <- function(variable) {
  hist(SCH_prox[[variable]], main=variable)
}

### testing normality on variables to check assumptions for ANOVA
check_norm("Bl150PL") # not normal
check_norm("Bch_pct") # approximately normal
check_norm("Wht_pct") # not normal
check_norm("Blck_pc") # not normal
check_norm("Unmply_") # not normal
check_norm("Mnf_pct") # approximately normal
check_norm("MedinAg") # normal
check_norm("MdnHmVl") # approximately normal
check_norm("MdnIncm") # normal
check_norm("Ppltn_s") # approximately normal

### testing equality of variance on variables to check assumpations for ANOVA
bartlett.test(Bl150PL ~ prox, data=SCH_prox) # not equal
bartlett.test(Bch_pct ~ prox, data=SCH_prox) # not equal
bartlett.test(Wht_pct ~ prox, data=SCH_prox) # not equal
bartlett.test(Blck_pc ~ prox, data=SCH_prox) # not equal
bartlett.test(Unmply_ ~ prox, data=SCH_prox) # not equal
bartlett.test(Mnf_pct ~ prox, data=SCH_prox) # not equal
bartlett.test(MedinAg ~ prox, data=SCH_prox) # not equal
bartlett.test(MdnHmVl ~ prox, data=SCH_prox) # not equal
bartlett.test(MdnIncm ~ prox, data=SCH_prox) # not equal
bartlett.test(Ppltn_s ~ prox, data=SCH_prox) # not equal

### checking sample sizes
nrow(SCH_5km)      # 59955
nrow(SCH_over5km)  # 42223

### Since the variances of the variables are generally not equal, I'm going to 
### do a t-test, where I can specify differing variances. 

### running welch's t-test
run_ttest <- function(variable){
  x <- st_drop_geometry(
    SCH_prox %>%
      filter(prox=="<5km") %>%
      select(all_of(variable)))
  
  y <- st_drop_geometry(
    SCH_prox %>%
      filter(prox==">5km") %>%
      select(all_of(variable)))
  
  t.test(x, y, var.equal = FALSE)
}

### variables to run t-tests on 
variables <- c("MedinAg", "MdnIncm", "MdnHmVl", "Blck_pc", "Wht_pct", "Bch_pct", "Mnf_pct", "Unmply_", "Bl150PL", "Ppltn_s")

### setting up table to hold t-test results
ttests <- data.frame(matrix(nrow = length(variables), ncol = 4))
colnames(ttests) <- c("<5 km", ">5 km", "p-value", "confidence int.")
rownames(ttests) <- variables

### running t-tests on variables and storing results in table
for (variable in variables){
  tt <- run_ttest(variable)
  ttests[variable, "<5 km"] <- tt$estimate['mean of x']
  ttests[variable, ">5 km"] <- tt$estimate['mean of y']
  ttests[variable, "p-value"] <- tt$p.value
  ttests[variable, "confidence int."] <- paste(round(tt$conf.int[1], 2),round(tt$conf.int[2], 2),sep=", ")
}

print(ttests)

### The t-tests show modest statistically significant differences in means 
### between proximity groups in all demographic categories.


### Logistic model of proximity groups
### Given the results of the t-test, I decided to build a logistic model 
### relating proximity group to demographic variables.

### creating binary factor variable for 5 km proximity cutoff
SCH_prox$prox_b <- ifelse(SCH_prox$prox == "<5km", 1, 0)
SCH_prox <- SCH_prox %>%
  mutate(prox_b = haven::as_factor(prox_b))

### formula for log model
formula <- as.formula(
  prox_b ~ MedinAg + MdnIncm + MdnHmVl + Blck_pc + Wht_pct + Bch_pct + Mnf_pct + Unmply_ + Bl150PL + Ppltn_s)

### log model
log_model <- glm(formula, data=SCH_prox, family=binomial("logit"))

### results of log model
print(summary(log_model))
print(exp(coefficients(log_model)))

### The log model results in statistically significant coefficient values for 
### all variables. 


## Proximity values

### reading in school data from gdb
### proximity to the nearest industrial facility has been calculated
SCH <- st_drop_geometry(sf::st_read("industrial-pollution-risk.gdb", layer = "SCH"))[c("NCESSCH", "NEAR_DIST")]

### merging with underlying census data
SCH_prox <- merge(SCH_prox, SCH)

### Correlation matrix
SCH_prox_num <- st_drop_geometry(SCH_prox) %>%
  select(
    Bch_pct, 
    HHIncm_, 
    Unmply_,
    Bl150PL, 
    Mnf_pct, 
    Asn_pct, 
    Blck_pc, 
    Hspnc_p, 
    Wht_pct, 
    MedinAg, 
    MdnHmVl, 
    MdnIncm, 
    Ppltn_s, 
    NEAR_DIST
  ) %>%
  rename(
    "% Bachelor's degree or higher" = Bch_pct,
    "Household Income" = HHIncm_,
    "% Unemployment" = Unmply_,
    "% Below 150% of the poverty line" = Bl150PL,
    "% of workforce in manufacturing" = Mnf_pct,
    "% Asian" = Asn_pct,
    "% Black" = Blck_pc,
    "% Hispanic" = Hspnc_p,
    "% White" = Wht_pct,
    "Median Age" = MedinAg,
    "Median Home Value" = MdnHmVl,
    "Median Income" = MdnIncm,
    "Population Size" = Ppltn_s,
    "Distance to nearest facility" = NEAR_DIST
  ) %>%
  drop_na()

cplt2 <- corrplot(
  cor(SCH_prox_num), 
  type = "upper", 
  tl.col = "black", 
  tl.srt = 45, 
  method = 'ellipse', 
  addCoef.col = 'black', 
  number.cex = 0.5, 
  tl.cex = 0.8, 
  cl.pos = 'n'
)


### Spatial model of school-to-facility proximity values

### selecting relevant variables for model and dropping nulls
SCH_prox_S <- SCH_prox %>% 
  select(
    NEAR_DIST, 
    Bch_pct, 
    Unmply_,
    Bl150PL,
    Mnf_pct, 
    Blck_pc, 
    Wht_pct, 
    MedinAg, 
    MdnIncm, 
    MdnHmVl,
    Ppltn_s
  ) %>%
  drop_na()

### removing rows where there is no spatial data
SCH_prox_S <- SCH_prox_S[!st_is_empty(SCH_prox_S),]

### creating spatial weights (distance band of 50 km)
neighbors <- dnearneigh(SCH_prox_S, d1 = 0, d2 = 50)
listweights <- nb2listw(neighbors, zero.policy = TRUE)

### calculating global moran's I (spatial auto-correlation)
global_moran <- moran.test(
  x = SCH_prox_S$NEAR_DIST, 
  listw = listweights, 
  randomisation = TRUE,
  alternative = "greater",
  na.action = na.omit,
  zero.policy = TRUE)

### printing results and plotting autocorrelation chart
print(global_moran)
moran.plot(x = SCH_prox_S$NEAR_DIST, 
           listw = listweights,
           zero.policy = FALSE)

### The Moran's I test calculates a value of 0.3, meaning there is modest 
### spatial autocorrelation in the data.

### formula for spatial model
formula <- as.formula(
  NEAR_DIST ~ Bch_pct + Unmply_ + Bl150PL + Mnf_pct + Blck_pc + Wht_pct + MdnHmVl + Ppltn_s)

### conventional OLS model
ols_model <- lm(formula = formula, data = SCH_prox_S)
summary(ols_model)

### spatial lag model
spatial_model <- lagsarlm(
  formula = formula, 
  data = SCH_prox_S, 
  listw = listweights, 
  zero.policy = TRUE, 
  na.action = na.omit,
  method="Matrix")
summary(spatial_model)

### Again, the spatial model improves the OLS model slightly (smaller AIC), and 
### the coefficients all have statistically significant contributions. The R^2 
### value is again quite small (0.11), meaning that this model also does not 
### explain the majority of the variance in the data.


### Relating school-to-facility proximity values to historical HOLC grades
### The school proximity data here has been combined with underlying HOLC grades 
### in ArcGIS. The historical HOLC data only exists for cities, so the full 
### dataset has been cut down to a smaller number of schools.

### reading in from gdb
SCH_HOLC <- st_drop_geometry(sf::st_read("industrial-pollution-risk.gdb", layer = "SCH_HOLC"))

### cleaning grades to remove E & F (very few instances) and to include "industrial"
SCH_HOLC <- SCH_HOLC %>%
  mutate(grade = ifelse(industrial == 1, "industrial", grade)) %>%
  mutate(grade = str_replace_all(grade, " ", "")) %>%
  filter((!grade %in% c("", "E", "F")))

### checking for normality
hist(SCH_HOLC$NEAR_DIST) # not really normal

### checking for equal variances
bartlett.test(NEAR_DIST ~ grade, data=SCH_HOLC) # not equal variances

### run anova
anova <- aov(NEAR_DIST ~ grade, data=SCH_HOLC)
print(summary(anova))
print(model.tables(anova))

### calculating effect size
(1368) / (1368 + 35695)

### The data do not satisfy the ANOVA requirements, but the test can be somewhat 
### robust to this if the sample sizes between groups are similar. With that 
### caveat, the ANOVA shows statistically significant differences in means 
### between grades, although the effect size is quite small (eta^2=0.04). 
### Generally, better historical grades for a school’s location are associated 
### with higher average distances from polluting facilities.
