![headerimage](https://github.com/claresk/industrial-pollution-risk/blob/e94c50300f6bb08eb5ea2f737d9212ac26985c26/header.png)

# Industrial Pollution Risk

This is a repository of code related to a project investigating patterns in the spatial relationship between public schools, demographic characteristics, and industrial pollution in the United States. 

Exposure to toxic chemicals and particulate matter produced by activities like manufacturing, waste management, chemical production, and gas processing has been shown to increase the risk of cardiovascular, respiratory, and other diseases, including cancer. These
impacts are especially pronounced among vulnerable populations like children and the elderly. While zoning laws in most of the U.S. restrict industrial facilities to designated areas, these areas are often still located in close proximity to residential neighborhoods, schools, or hospitals. Economically and racially marginalized communities are disproportionately affected by this phenomenon, compounding existing health inequities. Despite some environmental regulations in the United States, industry continues to profit while exposing vulnerable groups to hazardous pollution.

## Data Sources
-  For data on **schools**, I used the 2021–2022 National Center for Education Statistics’ [Public Schools](https://nces.ed.gov/programs/edge/Geographic/SchoolLocations) dataset, which lists the locations of all US public schools.

-  For data on **industrial pollution sites**, I used the 2022 EPA [Toxics Release Inventory](https://www.epa.gov/toxics-release-inventory-tri-program/what-toxics-release-inventory) (TRI), which lists all industrial sites and their reported emissions. This is the most recent release of the data in this format. This dataset splits emissions (reported in pounds) by chemical; I summed by site to get a total on-site emissions value for each location. The coordinates provided in the TRI dataset are estimated in some cases, so I also pulled in geographic data from the EPA [Facility Registry Service](https://www.epa.gov/frs) (FRS), which is a more robust dataset.

-  For data on **pollution concentrations**, I used the 2022 EPA [Risk-Screening Environmental Indicator](https://www.epa.gov/rsei/learn-about-rsei) (RSEI) model, which is a raster dataset showing modeled pollution exposure across the entire country, based on TRI data. I used the census tract-level version of the RSEI data so that it could be compared directly to census data. I used the Toxicity Concentration value from this dataset, which sums pollutant concentration by inhalation toxicity weight for all chemicals. This value does not reflect exact physical units and can be arbitrarily large based on emissions values.

-  For data on **community demographics**, I pulled tract-level demographic data from the 2021 [American Community Survey](https://www.census.gov/programs-surveys/acs.html) (ACS) using the Census API via `tidycensus` in R.

-  For data on **historical neighborhood grades** from the Home Owners’ Loan Corporation (HOLC), I used maps from [Mapping Inequality](https://dsl.richmond.edu/panorama/redlining/), a project at the University of Richmond.


## How to run this code
There are five numbered code files written in R and Python that pull, process, and analyze all data used in this project. Run them in numerical order to replicate the analysis. You will need to obtain a [Census API key](https://api.census.gov/data/key_signup.html) and input it into the first file; you will also need to be logged into a licensed [ArcGIS](https://www.esri.com/software/arcgis) account to run the code in Python, since it uses the `arcpy` package.
 
### 1_censusdata.R
This script pulls ACS data from the Census API using the `tidycensus` package, then saves the data.
### 2_allotherdata.ipynb
This notebook creates a geodatabase, then pulls and imports datasets on schools (NCES), industrial sites (EPA TRI & FRS), and air pollution (EPA RSEI) into that geodatabase. The RSEI data is joined with census shapefiles so it can be plotted and analyzed spatially. The ACS data pulled in the first script is also imported into the geodatabase. Historical neighborhood grading data is also imported from ArcGIS Online.
### 3_geoprocessing.ipynb
This notebook projects the school and industrial facility datasets into a projected coordinate system for calculating accurate geodesic distances. It then joins the census and air pollution data, then joins the school dataset with the underlying census and pollution data. The distance from each school to the nearest industrial facility is calculated, then the dataset of schools is then separated into proximity groups (<5km or >5km) using buffers and the Clip/Erase tools. The school proximity data is also joined with the historical neighborhood grading data.
### 4_rankings.ipynb
This notebook pulls in the dataset of schools joined with underlying pollution data and sorts to determine the 10 schools with the highest underlying air pollution. It also pulls in the dataset of industrial facilities sited within 5 km of a school and ranks these facilities by total emissions to determine the top 10 polluters near schools. It also groups this dataset by parent company to determine the top 10 owners of industrial facilities near schools.
### 5_modeling.R
This script reads in the census data pulled in part one and joins it with the air pollution data. It then generates and plots a correlation matrix relating air pollution to census demographic variables, then creates a spatial model relating that data. It then reads in the school proximity group data, runs a series of t-tests relating it to census demographic variables, and creates a log model of the data. Next, it reads in the full school proximity data, creates a correlation matrix relating it to census demographic variables, and creates another spatial model. Finally, the script reads in the historical neighborhood grade data and conducts an ANOVA test relating it to school-to-facility proximity.
