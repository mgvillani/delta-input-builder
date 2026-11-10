# Usage example. HERE, AND ONLY HERE, all the parameters are set: the functions in R/
# have no hidden default values for file names, folders, time zones or tables.
# Adapt the values to your run (the data are not included in the repository).
#
# Run the script from the main folder of the project (the one containing R/).
if (!file.exists("R/build.R")) {
  stop("Run the script from the main folder of the project (the one containing ",
       "the R/ folder and this file). Current folder: ", getwd())
}
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

## ============================== PARAMETERS ===================================

## --- EEA observations
obs_dir     <- "data/eea_parquet"            # one file per sampling point
obs_pattern <- "\\.parquet$"                 # regex on the observation file names
meta_csv    <- "data/DataExtract.csv"        # EEA station metadata

## --- Model (concentration files)
model_dir     <- "data/farm"                 # folder of the NetCDF files
model_pattern <- "^conc_.*\\.nc$"            # regex on the file names to read (FARM: "^FARM_conc_.*\\.nc$")
model_version <- NULL                        # e.g. "g2": text the name must contain; NULL = no filter
# Model grid: "utm" (x,y in UTM km, as FARM) or "lonlat" (degrees)
model_grid     <- "lonlat"
model_x_dim    <- "lon"                      # name of the x dimension in the NetCDF files ("x" for FARM UTM)
model_y_dim    <- "lat"                      # name of the y dimension ("y" for FARM UTM)
model_time_dim <- "time"
model_interp   <- "bilinear"                 # from model to station: "nearest" = nearest cell; "bilinear" = bilinear
                                             # interpolation among the 4 surrounding cells (as raster::extract(method = "bilinear"))
utm_lon0       <- 9                          # only model_grid = "utm": central meridian (9 for FARM)

## --- ISTAT administrative boundaries (REQUIRED): one zip per year in the same folder
istat_dir        <- "data/istat"
istat_year       <- NULL                     # NULL = use the edition of `year`
istat_max_dist_m <- 2000                     # stations outside the municipalities: within this distance (m) or dropped
comune_col       <- "COMUNE"                 # ISTAT column with the municipality name
region_col       <- "DEN_REG"                # ISTAT column with the region name
province_col      <- "DEN_UTS"               # ProvCM* layer: province name (old editions: "DEN_PROV"); only for the discarded-stations report
province_abbr_col <- "SIGLA"                 # ProvCM* layer: province abbreviation

## --- Pollutants: ONE ROW PER SPECIES, all the ones you may want to prepare
##   delta  name written in the startup and in the CSV files (letters and digits only; no spaces, '_', ';', '*', '.')
##   eea    name in the "Air Pollutant" column of DataExtract.csv (list_eea_pollutants(meta_csv) lists them)
##   farm   name of the variable in the model NetCDF (list_model_variables(...) lists them with their units)
##   type   GAS or PM
##   unit   OUTPUT unit (the one in the startup); observations and model are converted to it
##   obs_factor, model_factor  (optional) manual factor; NA = automatic conversion from the units
##                  ("Unit" of the EEA parquet files, "units" attribute of the NetCDF). Needed for ppb, mol/mol, ...
## Species below: SO2, CO, NOX, NO2, O3, PM10, PM2.5, Pb, As, BaP, Cd, Ni, C6H6.
## TO CHECK: the `farm` column (variable names in your NetCDF files: list_model_variables(...)),
## the output units (CO in mg/m3 and As/BaP/Cd in ng/m3 are a choice made here) and the GAS/PM type of the metals.
pollutants <- data.frame(
  delta = c("SO2",   "CO",    "NOX",        "NO2",   "O3",   "PM10",  "PM25",  "Pb",          "As",          "BaP",          "Cd",          "Ni",          "C6H6"),
  eea   = c("SO2",   "CO",    "NOX as NO2", "NO2",   "O3",   "PM10",  "PM2.5", "Pb in PM10",  "As in PM10",  "BaP in PM10",  "Cd in PM10",  "Ni in PM10",  "C6H6"),
  farm  = c("SO2",   "CO",    "NOX",        "NO2",   "O3",   "PM10",  "PM25",  "Pb",          "As",          "BaP",          "Cd",          "Ni",          "C6H6"),
  type  = c("GAS",   "GAS",   "GAS",        "GAS",   "GAS",  "PM",    "PM",    "PM",          "PM",          "PM",           "PM",          "PM",          "GAS"),
  unit  = c("ugm-3", "mgm-3", "ugm-3",      "ugm-3", "ugm-3", "ugm-3", "ugm-3", "ugm-3",       "ngm-3",       "ngm-3",        "ngm-3",       "ugm-3",       "ugm-3"),
  obs_factor   = NA_real_,
  model_factor = NA_real_,
  stringsAsFactors = FALSE
)

## Selection: which species of the table to prepare in this run (names of the `delta` column).
## NULL = all. NOX is in the table but DELTA online does NOT recognise it (KeyError 'NOX' on upload),
## so for the DELTA input it must be excluded with this selection.
species <- c("SO2", "CO", "NO2", "O3", "PM10", "PM25", "Pb", "As", "BaP", "Cd", "Ni", "C6H6")

## --- Output and period
out_dir      <- "output"                     # base folder
out_label    <- NULL                         # subfolder: NULL = "<year>[_<model_version>][_<species>][_<period>]"; "" = write in out_dir
                                             # startup.ini, obs/ and mod/ end up in out_dir/out_label/
startup_name <- "startup.ini"
discarded_name <- "discarded_stations.csv"   # report of the discarded stations (EoI, municipality, province, reason)
warnings_name  <- "warnings.txt"             # all the warnings, in full
year         <- 2023
# period     <- NULL                         # NULL = whole year
period       <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),    # quick test on 2 days
                  as.POSIXct("2023-01-02 23:00", tz = "UTC"))
scale        <- "urban"                      # [MODEL] Scale in the startup
valid_codes  <- c(1L)                        # accepted EEA "Validity" codes: 1 = valid only; c(1L, 2L, 3L) also includes
                                             # data valid below the detection limit (2 and 3)
min_coverage <- 0.75                         # minimum coverage: fraction of valid hours in the period for each
                                             # sampling point (station + pollutant); below the threshold it is dropped
eol          <- "\n"                         # line ending of the written files

## --- Time zones (hours from UTC: 1 = UTC+1, 0 = UTC)
tz_offset       <- 1                         # time zone of ALL the output files
obs_tz_offset   <- NULL                      # NULL = from the Timezone column of the EEA metadata
model_tz_offset <- 1                         # time zone of the times in the model NetCDF files
gmt_lag         <- NULL                      # NULL = "UTC" if tz_offset = 0, otherwise "UTC+1", ...
obs_hour_label  <- "end"                     # hour to which an hourly observation goes: "start" = start of the hour (PMSS);
                                             # "end" = end of the hour (FARM: times = end-of-hour instants). Obs and model must use the same convention
model_shift_h   <- 0                         # hours added to the grid time (hour convention)

## =============================== EXECUTION ===================================

res <- build_delta_inputs(
  obs_dir = obs_dir, obs_pattern = obs_pattern, meta_csv = meta_csv,
  model_dir = model_dir, model_pattern = model_pattern, model_version = model_version,
  istat_dir = istat_dir, istat_year = istat_year, istat_max_dist_m = istat_max_dist_m,
  comune_col = comune_col, region_col = region_col,
  province_col = province_col, province_abbr_col = province_abbr_col,
  pollutants = pollutants, species = species,
  out_dir = out_dir, out_label = out_label, startup_name = startup_name, discarded_name = discarded_name,
  warnings_name = warnings_name, year = year, period = period,
  scale = scale, valid_codes = valid_codes, min_coverage = min_coverage, eol = eol,
  model_grid = model_grid, model_x_dim = model_x_dim, model_y_dim = model_y_dim,
  model_time_dim = model_time_dim, utm_lon0 = utm_lon0,
  tz_offset = tz_offset, obs_tz_offset = obs_tz_offset, model_tz_offset = model_tz_offset,
  gmt_lag = gmt_lag, model_shift_h = model_shift_h, model_interp = model_interp, obs_hour_label = obs_hour_label
)
print(res$stations)
