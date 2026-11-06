# Lettura dei metadati EEA (DataExtract.csv) e delle osservazioni (parquet E1a).

# Tutti i record del DataExtract.csv (uno per Sampling Point Id + Process Id: lo stesso
# SPO puo' comparire con piu' SPP). Nessun record viene scartato: `pol` e' il nome DELTA
# se "Air Pollutant" e' nella colonna `eea` della tabella `pollutants` (vedi units.R),
# NA altrimenti (specie non selezionata); `pol_eea` e' il nome EEA originale.
# `code`/`method`/`sp_eoi` sono ricavati da "SPO.<EoI>_<codice>_<metodo>_<data>".
read_eea_metadata <- function(csv, pollutants) {
  # Il CSV EEA e' UTF-8 (con qualche carattere gia' corrotto a monte): niente
  # fileEncoding, che fa fallire la lettura al primo byte non valido.
  raw <- utils::read.csv(csv, encoding = "UTF-8", colClasses = "character",
                         check.names = FALSE, na.strings = "")
  need <- c("Sampling Point Id", "Air Quality Station EoI Code",
            "Air Quality Station Nat Code", "Air Quality Station Name",
            "Air Pollutant", "Longitude", "Latitude", "Altitude",
            "Air Quality Station Area", "Air Quality Station Type", "Timezone")
  miss <- setdiff(need, names(raw))
  if (length(miss)) stop("Colonne mancanti nel CSV EEA: ", paste(miss, collapse = ", "))

  raw$pol <- pollutants$delta[match(raw[["Air Pollutant"]], pollutants$eea)]
  spp <- if ("Process Id" %in% names(raw)) raw[["Process Id"]] else rep(NA_character_, nrow(raw))
  idp <- "^SP[OP]\\.([^_]+)_([^_]+)_(.*)$"
  has <- grepl(idp, raw[["Sampling Point Id"]])
  part <- function(i) ifelse(has, sub(idp, paste0("\\", i), raw[["Sampling Point Id"]]), NA_character_)

  tz <- raw[["Timezone"]]
  tz_off <- suppressWarnings(as.integer(sub("^UTC([+-]?[0-9]+).*$", "\\1", tz)))
  tz_off[tz %in% "UTC"] <- 0L

  data.frame(
    sp = raw[["Sampling Point Id"]],
    spp = spp,
    sp_eoi = part(1), code = part(2), method = sub("_[0-9]{4}-.*$", "", part(3)),
    pol_eea = raw[["Air Pollutant"]],
    eoi = raw[["Air Quality Station EoI Code"]],
    nat = raw[["Air Quality Station Nat Code"]],
    name = raw[["Air Quality Station Name"]],
    pol = raw$pol,
    lon = as.numeric(raw[["Longitude"]]),
    lat = as.numeric(raw[["Latitude"]]),
    alt = as.numeric(raw[["Altitude"]]),
    area = tolower(raw[["Air Quality Station Area"]]),   # denominazione del DataExtract (es. rural-nearcity)
    type = tolower(raw[["Air Quality Station Type"]]),
    tz_offset = tz_off,
    muni = if ("Municipality" %in% names(raw)) raw[["Municipality"]] else NA_character_,
    stringsAsFactors = FALSE
  )
}

# Cerca nel DataExtract il record di un sampling point delle osservazioni
# ("SPO.<EoI>_<codice>_<metodo>_<data>"). In ordine:
#   1. stesso SPO; 2. stesso SPP (Process Id); 3. stessa stazione, codice e metodo
#   (la data o il metodo del processo possono essere cambiati); 4. stessa stazione e codice;
#   5. solo la stazione: record costruito con i valori degli altri record della stazione e
#      specie ricavata dal codice (vedi sotto).
# Piu' righe candidate: quella con meno dati mancanti, poi l'ultima in ordine di SPP.
# Ritorna NULL se la stazione non e' nel DataExtract, altrimenti una riga di `meta`
# con `sp` = il sampling point delle osservazioni e `how` = criterio usato.
match_sampling_point <- function(sp, meta) {
  m <- regmatches(sp, regexec("^SP[OP]\\.([^_]+)_([^_]+)_(.*)$", sp))[[1]]
  if (length(m) != 4) return(NULL)
  eoi <- m[2]; code <- m[3]; method <- sub("_[0-9]{4}-.*$", "", m[4])
  st <- meta$sp_eoi %in% eoi | meta$eoi %in% eoi
  pick <- function(i, how) {
    cols <- c("lon", "lat", "alt", "area", "type")
    nmiss <- rowSums(is.na(meta[i, cols, drop = FALSE]))
    i <- i[order(nmiss, order(order(meta$spp[i], decreasing = TRUE)))][1]
    r <- meta[i, , drop = FALSE]
    r$sp <- sp
    r$how <- how
    r
  }
  i <- which(meta$sp == sp)
  if (length(i)) return(pick(i, "SPO"))
  i <- which(meta$spp %in% c(sp, sub("^SPO\\.", "SPP.", sp)))
  if (length(i)) return(pick(i, "SPP"))
  i <- which(st & meta$code %in% code & meta$method %in% method)
  if (length(i)) return(pick(i, "stessa stazione, codice e metodo"))
  i <- which(st & meta$code %in% code)
  if (length(i)) return(pick(i, "stessa stazione e codice"))
  i <- which(st)
  if (!length(i)) return(NULL)
  r <- pick(i, "solo stazione")
  # specie dal codice, come nel resto del DataExtract
  k <- which(meta$code %in% code)
  r$code <- code
  r$pol <- if (length(k)) meta$pol[k[1]] else NA_character_
  r$pol_eea <- if (length(k)) meta$pol_eea[k[1]] else NA_character_
  r
}

read_obs_file <- function(f) {
  if (grepl("\\.parquet$", f, ignore.case = TRUE)) {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Per leggere i file parquet serve il pacchetto 'arrow'.")
    }
    as.data.frame(arrow::read_parquet(f))
  } else {
    utils::read.csv(f, stringsAsFactors = FALSE)  # export CSV con le stesse colonne
  }
}

# Orologio "a muro" come POSIXct UTC. Il numero salvato nel parquet E' l'orologio (nessun fuso):
# se l'oggetto non ha fuso (tzone NULL o ""), va letto in UTC e NON nel fuso della sessione
# R (es. TZ=Europe/Rome, che aggiungerebbe 1 ora d'inverno e 2 d'estate); se ha un fuso
# esplicito, si legge l'orologio in quel fuso.
.naive_utc <- function(x) {
  if (is.character(x)) return(as.POSIXct(x, tz = "UTC"))  # export CSV
  tz <- attr(x, "tzone")
  if (is.null(tz) || !nzchar(tz[1])) tz <- "UTC"
  as.POSIXct(format(x, "%Y-%m-%d %H:%M:%S", tz = tz[1]), tz = "UTC")
}

# Serie oraria UTC da un parquet EEA.
#  - AggType "hour": il valore va all'ora di inizio (Start).
#  - AggType "day" e "var": il valore e' costante su tutto l'intervallo
#    [Start, End) e viene ripetuto su ogni ora dell'intervallo, qualunque ne
#    sia la lunghezza (giorno, settimana, ...: benzene, Pb, Cd, ...).
#  - Altri AggType: ignorati con avviso.
# Start/End sono ora locale della stazione (fuso fisso, es. UTC+01): si
# sottrae tz_offset per ottenere UTC.
obs_to_hourly <- function(d, tz_offset, valid_codes, factor) {
  start <- .naive_utc(d$Start)
  end <- .naive_utc(d$End)
  val <- as.numeric(d$Value)
  ok <- !is.na(val) & val > -900 & d$Validity %in% valid_codes
  val <- val * factor   # conversione di unita' (dopo aver escluso -9999); factor: scalare o per riga
  agg <- tolower(d$AggType)
  other <- setdiff(unique(agg), c("hour", "day", "var"))
  if (length(other)) warning("AggType non gestito, ignorato: ", paste(other, collapse = ", "))

  shift <- tz_offset * 3600
  h <- ok & agg == "hour"
  out <- data.frame(time = start[h] - shift, value = val[h])

  dd <- ok & agg %in% c("day", "var")
  if (any(dd)) {
    n <- pmax(1L, as.integer(round(as.numeric(difftime(end[dd], start[dd], units = "hours")))))
    idx <- rep(seq_along(n), times = n)
    out <- rbind(out, data.frame(
      time = start[dd][idx] + 3600 * (sequence(n) - 1) - shift,
      value = val[dd][idx]
    ))
  }
  out[!duplicated(out$time), , drop = FALSE]
}

# I valori dei metadati EEA si lasciano come sono, record per record (la stessa stazione
# puo' avere coordinate, tipo o area diversi tra i suoi sampling point, e lo startup li
# riporta cosi'). SOLO dove il dato manca (NA) si usa il valore degli altri record della
# stessa stazione (EoI): per ogni gruppo di colonne `cols` (insieme, es. lon+lat), quello
# sostenuto da piu' ore di dati validi (somma di `cov`); a parita' il primo in ordine
# alfabetico. Un record con tutti i valori presenti non viene mai toccato.
# `tab` deve avere `eoi` e `cov`. Ritorna la tabella e (attributo "filled") gli eoi toccati.
fill_missing_by_station <- function(tab, cols) {
  filled <- character()
  for (idx in split(seq_len(nrow(tab)), tab$eoi)) {
    miss <- idx[rowSums(is.na(tab[idx, cols, drop = FALSE])) > 0]
    have <- setdiff(idx, miss)
    if (!length(miss) || !length(have)) next
    key <- do.call(paste, c(lapply(tab[have, cols, drop = FALSE], as.character), sep = "\r"))
    tot <- tapply(tab$cov[have], key, sum)
    best <- have[match(names(tot)[which.max(tot)], key)]
    for (m in miss) {
      na <- is.na(tab[m, cols])
      tab[m, cols[na]] <- tab[best, cols[na]]
    }
    filled <- c(filled, tab$eoi[idx[1]])
  }
  attr(tab, "filled") <- filled
  tab
}
