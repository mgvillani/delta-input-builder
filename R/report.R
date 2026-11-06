# Rapporto finale a schermo: avvisi (warning) e stazioni scartate.

# Una riga del registro degli scarti (vettori della stessa lunghezza; NA dove non noto).
.disc_row <- function(eoi, element, name, lon, lat, muni, reason) {
  n <- length(element)
  data.frame(eoi = rep_len(as.character(eoi), n), element = as.character(element),
             name = rep_len(as.character(name), n), lon = rep_len(as.numeric(lon), n),
             lat = rep_len(as.numeric(lat), n), muni = rep_len(as.character(muni), n),
             reason = rep_len(as.character(reason), n), stringsAsFactors = FALSE)
}

# Aggiunge comune e provincia (dai limiti ISTAT, se la posizione e' nota; altrimenti il
# comune del DataExtract.csv, segnato [EEA]) e ordina le colonne.
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
  out <- data.frame(eoi = tab$eoi, elemento = tab$element, nome_stazione = tab$name,
                    comune = comune, provincia = prov, motivo = tab$reason,
                    stringsAsFactors = FALSE)
  out[!duplicated(out), , drop = FALSE]
}

# Scrive a schermo (message) avvisi e stazioni scartate. Restano interamente nei file
# di rapporto; a schermo al massimo `max_lines` righe per blocco.
.print_report <- function(wlog, disc_tab, max_lines = 60L) {
  if (length(wlog)) {
    message("\n===== AVVISI (", length(wlog), ") =====")
    shown <- utils::head(wlog, max_lines)
    message(paste0(sprintf("%2d. ", seq_along(shown)), shown, collapse = "\n"))
    if (length(wlog) > max_lines) {
      message("... e altri ", length(wlog) - max_lines, " avvisi (elenco completo nel file degli avvisi)")
    }
  }
  if (!is.null(disc_tab) && nrow(disc_tab)) {
    message("\n===== STAZIONI SCARTATE (", nrow(disc_tab), ") =====")
    show <- utils::head(disc_tab, max_lines)
    show[is.na(show)] <- "-"
    message(paste0(sprintf("%2d. EoI %s | %s | stazione: %s | comune: %s | provincia: %s\n      motivo: %s",
                           seq_len(nrow(show)), show$eoi, show$elemento, show$nome_stazione, show$comune,
                           show$provincia, show$motivo), collapse = "\n"))
    if (nrow(disc_tab) > max_lines) {
      message("... e altre ", nrow(disc_tab) - max_lines, " righe (elenco completo nel file delle stazioni scartate)")
    }
  }
}
