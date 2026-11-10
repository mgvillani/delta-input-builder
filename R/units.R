# Names and units of the pollutants.
#
# Each pollutant is a row of the `pollutants` table (see run_example.R):
#   delta        name written in the startup and in the CSV columns (no spaces, ';' or '*')
#   eea          name in the "Air Pollutant" column of DataExtract.csv
#   farm         name of the variable in the model NetCDF
#   type         GAS or PM
#   unit         output unit (the one declared in the startup), e.g. "ugm-3"
#   obs_factor   (optional) multiplicative factor for the observations; NA = automatic
#   model_factor (optional) multiplicative factor for the model; NA = automatic
# Automatic: the unit of the observations ("Unit" column of the EEA parquet files) and that
# of the model ("units" attribute of the NetCDF variable) are converted to `unit`. Only
# mass-per-m3 units are handled (kg, g, mg, ug, ng, pg). For everything else (ppb, mol/mol, ...)
# the conversion depends on molecular mass, temperature and pressure: give it by hand
# with obs_factor / model_factor.

.MASS_G <- c(kg = 1e3, g = 1, mg = 1e-3, ug = 1e-6, ng = 1e-9, pg = 1e-12)

# Grams per unit of `u` ("ug/m3", "ug.m-3", "mg m-3", "ugm-3", ...); NA if not recognised.
.mass_per_unit <- function(u) {
  vapply(as.character(u), function(x) {
    if (is.na(x)) return(NA_real_)
    cp <- utf8ToInt(x)
    cp[cp %in% c(181L, 956L)] <- 117L              # micro (mu) -> u, independent of the locale
    x <- tolower(intToUtf8(cp))
    x <- gsub("[ .*]", "", x)
    m <- regmatches(x, regexec("^(kg|g|mg|ug|ng|pg)(/m3|m-3|m\\^-3|/m\\^3)$", x))[[1]]
    if (length(m) != 3) NA_real_ else unname(.MASS_G[m[2]])
  }, numeric(1), USE.NAMES = FALSE)
}

# Factor to bring values from `from` (vector of units) to `to` (one unit). If
# `override` is not NA it is used. Clear error if a unit is not recognised.
unit_factor <- function(from, to, override, what) {
  if (!is.null(override) && !is.na(override)) return(rep(as.numeric(override), length(from)))
  f <- .mass_per_unit(from) / .mass_per_unit(to)
  if (anyNA(f)) {
    bad <- unique(as.character(from)[is.na(f)])
    stop("Unrecognised unit for ", what, ": ", paste0("'", bad, "'", collapse = ", "),
         " (output unit: '", to, "'). Only kg, g, mg, ug, ng, pg per m3 are converted automatically: ",
         "write the factor by hand in the pollutants table (obs_factor / model_factor columns).")
  }
  f
}

# Checks the pollutants table and adds the optional obs_factor / model_factor columns.
check_pollutants <- function(pollutants) {
  need <- c("delta", "eea", "farm", "type", "unit")
  miss <- setdiff(need, names(pollutants))
  if (length(miss)) stop("The pollutants table is missing columns: ", paste(miss, collapse = ", "))
  for (cn in c("obs_factor", "model_factor")) {
    if (!cn %in% names(pollutants)) pollutants[[cn]] <- NA_real_
    pollutants[[cn]] <- as.numeric(pollutants[[cn]])
  }
  if (anyNA(pollutants[need])) stop("The pollutants table has empty cells (NA) in columns ", paste(need, collapse = ", "))
  bad <- pollutants$delta[!grepl("^[A-Za-z][A-Za-z0-9]*$", pollutants$delta)]
  if (length(bad)) {
    stop("Invalid DELTA name: ", paste0("'", bad, "'", collapse = ", "),
         ". The name is written in the startup and in the CSV files: only letters and digits (no spaces, '_', ';', '*', '.' or other symbols), ",
         "and it must start with a letter (e.g. PM2.5 -> PM25).")
  }
  for (cn in c("delta", "eea", "farm")) {
    dup <- unique(pollutants[[cn]][duplicated(pollutants[[cn]])])
    if (length(dup)) stop("In the pollutants table column ", cn, " has repeated values: ", paste(dup, collapse = ", "))
  }
  if (!all(pollutants$type %in% c("GAS", "PM"))) stop("The type column of pollutants must be GAS or PM")
  pollutants
}
