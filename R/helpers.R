# Helper functions to fill in the `pollutants` table (not needed for the build).

# Pollutants present in the EEA DataExtract.csv and how many sampling points each has: the
# names of the "eea" column of the pollutants table are taken from here.
list_eea_pollutants <- function(meta_csv) {
  raw <- utils::read.csv(meta_csv, encoding = "UTF-8", colClasses = "character",
                         check.names = FALSE, na.strings = "")
  tab <- sort(table(raw[["Air Pollutant"]]), decreasing = TRUE)
  data.frame(eea = names(tab), sampling_points = as.integer(tab), row.names = NULL,
             stringsAsFactors = FALSE)
}

# Variables of the first model NetCDF, with units and dimensions: the names of the "farm"
# column of the pollutants table are taken from here.
list_model_variables <- function(model_dir, model_pattern, model_version) {
  f <- farm_files(model_dir, model_pattern, model_version)[1]
  nc <- ncdf4::nc_open(f)
  on.exit(ncdf4::nc_close(nc))
  data.frame(
    variable = names(nc$var),
    units = vapply(nc$var, function(v) { u <- ncdf4::ncatt_get(nc, v$name, "units"); if (u$hasatt) as.character(u$value) else NA_character_ }, character(1)),
    dims = vapply(nc$var, function(v) paste(vapply(v$dim, function(d) d$name, ""), collapse = ","), character(1)),
    file = basename(f), row.names = NULL, stringsAsFactors = FALSE)
}
