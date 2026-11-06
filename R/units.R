# Nomi e unita' di misura degli inquinanti.
#
# Ogni inquinante e' una riga della tabella `pollutants` (vedi run_example.R):
#   delta        nome scritto nello startup e nelle colonne dei CSV (senza spazi, ';' o '*')
#   eea          nome nella colonna "Air Pollutant" del DataExtract.csv
#   farm         nome della variabile nel NetCDF del modello
#   type         GAS oppure PM
#   unit         unita' di uscita (quella dichiarata nello startup), es. "ugm-3"
#   obs_factor   (facoltativa) fattore moltiplicativo per le osservazioni; NA = automatico
#   model_factor (facoltativa) fattore moltiplicativo per il modello; NA = automatico
# Automatico: l'unita' delle osservazioni (colonna "Unit" dei parquet EEA) e quella del
# modello (attributo "units" della variabile NetCDF) si convertono in `unit`. Si gestiscono
# solo unita' di massa per m3 (kg, g, mg, ug, ng, pg). Per tutto il resto (ppb, mol/mol, ...)
# la conversione dipende da massa molecolare, temperatura e pressione: va data a mano
# con obs_factor / model_factor.

.MASS_G <- c(kg = 1e3, g = 1, mg = 1e-3, ug = 1e-6, ng = 1e-9, pg = 1e-12)

# Grammi per unita' di `u` ("ug/m3", "ug.m-3", "mg m-3", "ugm-3", ...); NA se non riconosciuta.
.mass_per_unit <- function(u) {
  vapply(as.character(u), function(x) {
    if (is.na(x)) return(NA_real_)
    cp <- utf8ToInt(x)
    cp[cp %in% c(181L, 956L)] <- 117L              # micro (mu) -> u, senza dipendere dal locale
    x <- tolower(intToUtf8(cp))
    x <- gsub("[ .*]", "", x)
    m <- regmatches(x, regexec("^(kg|g|mg|ug|ng|pg)(/m3|m-3|m\\^-3|/m\\^3)$", x))[[1]]
    if (length(m) != 3) NA_real_ else unname(.MASS_G[m[2]])
  }, numeric(1), USE.NAMES = FALSE)
}

# Fattore per portare i valori da `from` (vettore di unita') a `to` (una unita'). Se
# `override` non e' NA vale quello. Errore chiaro se un'unita' non e' riconosciuta.
unit_factor <- function(from, to, override, what) {
  if (!is.null(override) && !is.na(override)) return(rep(as.numeric(override), length(from)))
  f <- .mass_per_unit(from) / .mass_per_unit(to)
  if (anyNA(f)) {
    bad <- unique(as.character(from)[is.na(f)])
    stop("Unita' non riconosciuta per ", what, ": ", paste0("'", bad, "'", collapse = ", "),
         " (unita' di uscita: '", to, "'). Si convertono in automatico solo kg, g, mg, ug, ng, pg ",
         "per m3: scrivi il fattore a mano nella tabella pollutants (colonne obs_factor / model_factor).")
  }
  f
}

# Controlla la tabella pollutants e aggiunge le colonne facoltative obs_factor / model_factor.
check_pollutants <- function(pollutants) {
  need <- c("delta", "eea", "farm", "type", "unit")
  miss <- setdiff(need, names(pollutants))
  if (length(miss)) stop("Nella tabella pollutants mancano le colonne: ", paste(miss, collapse = ", "))
  for (cn in c("obs_factor", "model_factor")) {
    if (!cn %in% names(pollutants)) pollutants[[cn]] <- NA_real_
    pollutants[[cn]] <- as.numeric(pollutants[[cn]])
  }
  if (anyNA(pollutants[need])) stop("La tabella pollutants ha celle vuote (NA) nelle colonne ", paste(need, collapse = ", "))
  bad <- pollutants$delta[!grepl("^[A-Za-z][A-Za-z0-9]*$", pollutants$delta)]
  if (length(bad)) {
    stop("Nome DELTA non valido: ", paste0("'", bad, "'", collapse = ", "),
         ". Il nome va scritto nello startup e nei CSV: solo lettere e cifre (niente spazi, '_', ';', '*', '.' o altri simboli), ",
         "e deve iniziare con una lettera (es. PM2.5 -> PM25).")
  }
  for (cn in c("delta", "eea", "farm")) {
    dup <- unique(pollutants[[cn]][duplicated(pollutants[[cn]])])
    if (length(dup)) stop("Nella tabella pollutants la colonna ", cn, " ha valori ripetuti: ", paste(dup, collapse = ", "))
  }
  if (!all(pollutants$type %in% c("GAS", "PM"))) stop("La colonna type di pollutants deve essere GAS oppure PM")
  pollutants
}
