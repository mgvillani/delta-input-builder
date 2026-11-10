# Final report on screen: warnings and discarded stations.

# One row of the discard log (vectors of the same length; NA where unknown).
.disc_row <- function(eoi, element, name, lon, lat, muni, reason) {
  n <- length(element)
  data.frame(eoi = rep_len(as.character(eoi), n), element = as.character(element),
             name = rep_len(as.character(name), n), lon = rep_len(as.numeric(lon), n),
             lat = rep_len(as.numeric(lat), n), muni = rep_len(as.character(muni), n),
             reason = rep_len(as.character(reason), n), stringsAsFactors = FALSE)
}

# Adds municipality and province (from the ISTAT boundaries, if the position is known;
# otherwise the municipality of DataExtract.csv, marked [EEA]) and orders the columns.
.disc_table <- function(disc, bnd, comune_col, region_col, max_dist_m, province_col, province_abbr_col) {
  if (!length(disc)) return(NULL)
  tab <- do.call(rbind, disc)
  geo <- NULL
  if (!is.null(bnd)) {
    geo <- tryCatch(istat_lookup(bnd, tab$lon, tab$lat, comune_col, region_col, max_dist_m,
                                 province_col, province_abbr_col),
                    error = function(e) NULL)
  }
  comune <- if (is.null(geo)) rep(NA_character_, nrow(tab)) else geo$comune
  eea <- ifelse(is.na(tab$muni), NA_character_, paste0(tab$muni, " [EEA]"))
  comune <- ifelse(is.na(comune), eea, comune)
  prov <- if (is.null(geo)) rep(NA_character_, nrow(tab)) else geo$provincia
  out <- data.frame(eoi = tab$eoi, item = tab$element, station_name = tab$name,
                    municipality = comune, province = prov, reason = tab$reason,
                    stringsAsFactors = FALSE)
  out[!duplicated(out), , drop = FALSE]
}

# Prints (message) warnings and discarded stations. They remain in full in the report
# files; on screen at most `max_lines` rows per block.
.print_report <- function(wlog, disc_tab, max_lines = 60L) {
  if (length(wlog)) {
    message("\n===== WARNINGS (", length(wlog), ") =====")
    shown <- utils::head(wlog, max_lines)
    message(paste0(sprintf("%2d. ", seq_along(shown)), shown, collapse = "\n"))
    if (length(wlog) > max_lines) {
      message("... and ", length(wlog) - max_lines, " more warnings (full list in the warnings file)")
    }
  }
  if (!is.null(disc_tab) && nrow(disc_tab)) {
    message("\n===== DISCARDED STATIONS (", nrow(disc_tab), ") =====")
    show <- utils::head(disc_tab, max_lines)
    show[is.na(show)] <- "-"
    message(paste0(sprintf("%2d. EoI %s | %s | station: %s | municipality: %s | province: %s\n      reason: %s",
                           seq_len(nrow(show)), show$eoi, show$item, show$station_name, show$municipality,
                           show$province, show$reason), collapse = "\n"))
    if (nrow(disc_tab) > max_lines) {
      message("... and ", nrow(disc_tab) - max_lines, " more rows (full list in the discarded-stations file)")
    }
  }
}
