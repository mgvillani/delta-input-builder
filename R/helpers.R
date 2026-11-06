# Funzioni di aiuto per compilare la tabella `pollutants` (non servono per la costruzione).

# Inquinanti presenti nel DataExtract.csv dell'EEA e quanti sampling point hanno: i nomi
# della colonna "eea" della tabella pollutants si prendono da qui.
list_eea_pollutants <- function(meta_csv) {
  raw <- utils::read.csv(meta_csv, encoding = "UTF-8", colClasses = "character",
                         check.names = FALSE, na.strings = "")
  tab <- sort(table(raw[["Air Pollutant"]]), decreasing = TRUE)
  data.frame(eea = names(tab), sampling_points = as.integer(tab), row.names = NULL,
             stringsAsFactors = FALSE)
}

# Variabili del primo NetCDF del modello, con unita' e dimensioni: i nomi della colonna
# "farm" della tabella pollutants si prendono da qui.
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
