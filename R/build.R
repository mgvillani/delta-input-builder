# Costruzione degli input DELTA (formato legacy): startup.ini + un CSV per
# stazione per le osservazioni e uno per il modellato, con lo stesso nome.

write_delta_csv <- function(times, mat, path, eol) {
  lt <- as.POSIXlt(times, tz = "UTC")
  out <- data.frame(year = lt$year + 1900, month = lt$mon + 1, day = lt$mday,
                    hour = lt$hour)
  for (cn in colnames(mat)) {
    out[[cn]] <- ifelse(is.na(mat[, cn]), "-999", sprintf("%.2f", mat[, cn]))
  }
  lines <- c(paste(names(out), collapse = ";"), do.call(paste, c(out, sep = ";")))
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeChar(paste0(paste(lines, collapse = eol), eol), con, eos = NULL)
}

write_startup <- function(st, path, year, pollutants, gmt_lag, scale, eol) {
  fmt <- function(x) as.character(x)   # tutti i decimali presenti nei metadati
  rows <- paste(st$code, st$id, st$id, fmt(st$alt), fmt(st$lon), fmt(st$lat), gmt_lag,
                st$region, st$type, st$area, st$siting, st$vars, sep = ";")
  lines <- c("[MODEL]", ";Year", ";frequency", ";Scale", year, "hour", scale,
             "[PARAMETERS]", ";Specie*type*measure unit",
             paste(pollutants$delta, pollutants$type, pollutants$unit, sep = ";"),
             "[MONITORING]",
             paste("Station Code", "Station Name", "Station abbreviation", "Altitude",
                   "Lon", "Lat", "GMTLag", "Region", "Station Type", "Area Type",
                   "Siting", "listOfvariables", sep = ";"),
             rows)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeChar(paste0(paste(lines, collapse = eol), eol), con, eos = NULL)
}

# TUTTI i parametri si danno in un colpo solo, all'inizio (vedi run_example.R): nessuna
# funzione dei file in R/ ha valori predefiniti per nomi di file, cartelle, fusi orari o
# tabelle. Descrizione dei parametri:
#
# Dati in ingresso
#   obs_dir        cartella con i file di osservazioni EEA (uno per sampling point)
#   obs_pattern    espressione regolare sul NOME di quei file (es. "\\.parquet$")
#   meta_csv       DataExtract.csv dell'EEA (metadati stazioni)
#   model_dir      cartella con i NetCDF del modello (concentrazioni)
#   model_pattern  espressione regolare sul NOME dei file di concentrazione da leggere
#                  (es. "^FARM_conc_.*\\.nc$" oppure "^FARM_conc_g2_.*_D1\\.nc$")
#   model_version  testo che il nome del file deve contenere per scegliere una versione/run
#                  del modello (es. "g2", "v5"); NULL = nessun filtro. Si somma a model_pattern.
#   istat_dir      cartella dedicata ai limiti ISTAT, con dentro uno zip per anno (es.
#                  Limiti01012023.zip) o le cartelle gia' estratte. Da qui vengono Region e
#                  Siting di ogni stazione, ripuliti da accenti, apostrofi e spazi.
#   istat_year     anno dell'edizione ISTAT da usare; NULL = `year`. Se quell'anno non c'e'
#                  si usa la piu' recente precedente, con un avviso.
#   istat_max_dist_m  distanza massima (m) dal comune piu' vicino per le stazioni fuori da ogni
#                  poligono; oltre, la stazione e' scartata con un avviso
#   comune_col, region_col  colonne ISTAT con il nome del comune e della regione
#   province_col, province_abbr_col  colonne del layer ISTAT delle province (ProvCM*) con il nome
#                  e la sigla della provincia: servono solo al rapporto delle stazioni scartate
#   pollutants     tabella degli inquinanti: una riga per specie, TUTTE quelle che vuoi preparare
#                  (colonne delta, eea, farm, type, unit; facoltative obs_factor, model_factor).
#                  Nomi e unita' di misura: vedi R/units.R. Conversione automatica delle unita'
#                  di massa per m3 (ug/m3, mg/m3, ng/m3, ...); altrimenti fattore a mano.
#   species        quali specie della tabella preparare: vettore di nomi `delta` (es. c("NO2",
#                  "PM10")); NULL = tutte. Con una selezione il nome della cartella di output
#                  automatica (out_label = NULL) comprende le specie.
#
# Uscita e periodo
#   out_dir        cartella base di output
#   out_label      sottocartella di `out_dir` dove scrivere startup.ini, obs/, mod/, cosi' run
#                  diversi non si sovrascrivono. NULL = automatica: "<year>", piu' "_<model_version>"
#                  se indicata, piu' "_<inizio>-<fine>" se `period` e' impostato (es. "2023_d0",
#                  "2023_d0_20230101-20230102"). Una stringa = quel nome; "" = direttamente in out_dir
#   startup_name   nome del file startup
#   discarded_name nome del file CSV (in out_dir/out_label) con le stazioni scartate
#   warnings_name  nome del file di testo (in out_dir/out_label) con tutti gli avvisi
#   year           anno della griglia oraria
#   period         NULL = tutto l'anno; oppure c(inizio, fine) come orologio nel fuso
#                  `tz_offset` (POSIXct con tz = "UTC" usato solo come contenitore)
#   scale          scala scritta nello startup (es. "urban")
#   valid_codes     codici EEA della colonna Validity accettati come validi (1 = solo dati validi; 2 e 3 sono validi sotto il limite di rilevabilita')
#   eol            fine riga dei file scritti ("\n" oppure "\r\n")
#
# Geografia
#   model_grid     tipo di griglia del modello: "utm" (x,y in km UTM, come FARM) oppure
#                  "lonlat" (longitudine/latitudine in gradi)
#   model_x_dim, model_y_dim, model_time_dim  nomi delle dimensioni nei NetCDF (es. "x", "y",
#                  "time" per FARM; "lon", "lat", "time" per una griglia lon/lat)
#   utm_lon0       meridiano centrale UTM delle coordinate del modello (solo model_grid = "utm";
#                  9 per FARM)
#
# Fusi orari (ore rispetto a UTC; 1 = UTC+1, 0 = UTC):
#   tz_offset        fuso di TUTTI i file in uscita (osservati, modellati, griglia
#                    oraria) e dell'etichetta GMTLag dello startup
#   obs_tz_offset    fuso delle ore EEA; NULL = quello della colonna Timezone di ogni
#                    stazione (UTC+01 per l'Italia)
#   model_tz_offset  fuso scritto nei NetCDF del modello
#   gmt_lag          testo della colonna GMTLag; NULL = "UTC" se tz_offset = 0,
#                    altrimenti "UTC+1", "UTC-2", ...
#   valid_codes       codici della colonna Validity dei parquet accettati come dati validi: c(1) = solo "valido";
#                    c(1, 2, 3) include anche i dati validi sotto il limite di rilevabilita'
#   min_coverage     copertura minima (0-1) di ore valide nel periodo perche' un sampling point
#                    (stazione + inquinante) sia usato: es. 0.75 = almeno il 75% delle ore.
#                    Sotto soglia e' scartato e compare nel rapporto delle stazioni scartate.
#   obs_hour_label   a quale ora si attribuisce il dato orario delle osservazioni (intervallo [Start, End) EEA):
#                    "start" = ora di inizio (il dato 00:00-01:00 va all'ora 0, come PMSS);
#                    "end" = ora di fine (va all'ora 1, come i tempi di FARM, che sono istanti a fine ora).
#                    Vale per tutte le osservazioni (orarie, giornaliere e a intervallo variabile)
#   model_interp     "nearest" = cella piu' vicina; "bilinear" = interpolazione bilineare tra le
#                    4 celle intorno alla stazione (come raster::extract(method = "bilinear"))
#   model_shift_h    ore da sommare al tempo di griglia per leggere il modello
#                    (solo convenzione oraria, non fuso)
build_delta_inputs <- function(obs_dir, obs_pattern, meta_csv,
                               model_dir, model_pattern, model_version,
                               istat_dir, istat_year, istat_max_dist_m, comune_col, region_col, province_col, province_abbr_col,
                               pollutants, species,
                               out_dir, out_label, startup_name, discarded_name, warnings_name, year, period, scale,
                               valid_codes, min_coverage, eol,
                               model_grid, model_x_dim, model_y_dim, model_time_dim, utm_lon0,
                               tz_offset, obs_tz_offset, model_tz_offset, gmt_lag, model_shift_h, model_interp, obs_hour_label) {
  # Registri per il rapporto finale: avvisi e stazioni scartate. Gli avvisi sono raccolti
  # (non appaiono subito) e scritti per esteso alla fine, anche se lo script si ferma.
  .wlog <- character()
  .disc <- list()
  .dt <- NULL
  bnd <- NULL
  .mk_dt <- function() .disc_table(.disc, bnd, comune_col, region_col, istat_max_dist_m,
                                   province_col, province_abbr_col)
  on.exit({
    if (is.null(.dt)) .dt <- .mk_dt()
    .print_report(.wlog, .dt)
  }, add = TRUE)
  .res <- withCallingHandlers({
  # I limiti ISTAT sono obbligatori: se mancano ci si ferma subito, prima di
  # leggere dati pesanti.
  bnd <- read_istat_boundaries(istat_dir, if (is.null(istat_year)) year else istat_year)
  message("Limiti ISTAT: edizione ", attr(bnd, "edition"))
  if (is.null(gmt_lag)) gmt_lag <- if (tz_offset == 0) "UTC" else sprintf("UTC%+g", tz_offset)
  # Griglia oraria = orologio nel fuso tz_offset (anno intero o `period`).
  grid_t <- if (is.null(period)) {
    seq(ISOdatetime(year, 1, 1, 0, 0, 0, tz = "UTC"),
        ISOdatetime(year, 12, 31, 23, 0, 0, tz = "UTC"), by = "hour")
  } else seq(period[1], period[2], by = "hour")

  if (!is.numeric(min_coverage) || length(min_coverage) != 1 || is.na(min_coverage) ||
      min_coverage < 0 || min_coverage > 1) {
    stop("min_coverage deve essere un numero tra 0 e 1 (es. 0.75 = almeno il 75% di ore valide)")
  }
  pollutants <- check_pollutants(pollutants)
  if (!is.null(species)) {
    unk <- setdiff(species, pollutants$delta)
    if (length(unk)) {
      stop("Specie non presenti nella tabella pollutants: ", paste(unk, collapse = ", "),
           " (disponibili: ", paste(pollutants$delta, collapse = ", "), ")")
    }
    pollutants <- pollutants[pollutants$delta %in% species, , drop = FALSE]   # ordine della tabella
  }
  message("Specie: ", paste(pollutants$delta, collapse = ", "))
  # Specie senza variabile nei NetCDF: non si puo' validare, quindi si scartano.
  have <- farm_varnames(farm_files(model_dir, model_pattern, model_version)[1])
  no_var <- !pollutants$farm %in% have
  if (any(no_var)) {
    warning("Variabili assenti nei NetCDF, specie scartate: ",
            paste(pollutants$delta[no_var], collapse = ", "))
    pollutants <- pollutants[!no_var, , drop = FALSE]
  }
  if (!nrow(pollutants)) {
    stop("Nessuna specie con variabile nei NetCDF. Variabili presenti: ", paste(have, collapse = ", "),
         ". Imposta la colonna `farm` della tabella pollutants con questi nomi.")
  }

  meta <- read_eea_metadata(meta_csv, pollutants)
  nometa <- setdiff(pollutants$delta, meta$pol)
  if (length(nometa)) {
    warning("Specie senza nessun sampling point nei metadati EEA (controlla il nome in `eea`): ",
            paste(nometa, collapse = ", "), call. = FALSE)
  }

  ## 1. Osservazioni: una serie oraria (fuso tz_offset) per sampling point ----
  files <- list.files(obs_dir, pattern = obs_pattern, full.names = TRUE)
  if (!length(files)) stop("Nessun file osservazioni in ", obs_dir)
  parts <- list()
  recs <- list()       # un record di metadati per sampling point delle osservazioni
  skipped <- 0L
  nsel <- character()  # specie presenti nelle osservazioni ma non selezionate
  how <- character()
  obs_units <- list()
  obs_factors <- setNames(rep(NA_real_, nrow(pollutants)), pollutants$delta)
  for (f in files) {
    d0 <- read_obs_file(f)
    sps <- unique(sub("^[A-Za-z]{2}/", "", d0$Samplingpoint))
    for (sp in sps) {
      d <- d0[sub("^[A-Za-z]{2}/", "", d0$Samplingpoint) == sp, , drop = FALSE]
      r <- match_sampling_point(sp, meta)
      if (is.null(r)) {
        warning("Stazione non presente nei metadati, saltato: ", sp, " (", basename(f), ")", call. = FALSE)
        skipped <- skipped + 1L
        .disc[[length(.disc) + 1]] <- .disc_row(
          eoi = sub("^SP[OP]\\.([A-Za-z0-9]+)_.*$", "\\1", sp), element = basename(f), name = NA,
          lon = NA, lat = NA, muni = NA,
          reason = "codice EoI non presente nel DataExtract.csv")
        next
      }
      if (is.na(r$pol)) {
        nsel <- union(nsel, if (is.na(r$pol_eea)) paste0("codice ", r$code) else r$pol_eea)
        skipped <- skipped + 1L
        next
      }
      if (r$how != "SPO") how[[sp]] <- r$how
      off <- if (is.null(obs_tz_offset)) r$tz_offset else obs_tz_offset
      if (is.na(off)) stop("Fuso EEA non riconosciuto per ", sp, ": imposta obs_tz_offset")
      prow <- pollutants[match(r$pol, pollutants$delta), ]
      if ("Unit" %in% names(d)) {
        f_u <- unit_factor(d$Unit, prow$unit, prow$obs_factor,
                           paste0("le osservazioni di ", prow$delta, " (", basename(f), ")"))
        obs_units[[prow$delta]] <- union(obs_units[[prow$delta]], unique(as.character(d$Unit)))
      } else if (!is.na(prow$obs_factor)) {
        f_u <- prow$obs_factor
      } else {
        warning("Colonna Unit assente in ", basename(f), ": nessuna conversione di unita' (",
                prow$delta, "); se serve imposta obs_factor", call. = FALSE)
        f_u <- 1
      }
      obs_factors[[prow$delta]] <- f_u[1]
      s <- obs_to_hourly(d, off - tz_offset, valid_codes, f_u)   # dal fuso EEA a tz_offset
      if (obs_hour_label == "end") s$time <- s$time + 3600       # il dato [Start, End) va all'ora di fine
      parts[[sp]] <- rbind(parts[[sp]], s)
      recs[[sp]] <- r
    }
  }
  if (length(nsel)) {
    message("Osservazioni di specie non selezionate (ignorate): ", paste(nsel, collapse = ", "))
  }
  if (length(how)) {
    message("Sampling point delle osservazioni abbinati ai metadati senza corrispondenza esatta dell'SPO: ")
    for (h in unique(how)) {
      message("  ", h, ": ", sum(how == h), " (es. ", names(how)[how == h][1], ")")
      warning(sum(how == h), " sampling point abbinati per '", h, "', es. ", names(how)[how == h][1],
              call. = FALSE)
    }
  }
  for (pn in names(obs_units)) {
    message("Unita' osservazioni ", pn, ": ", paste(obs_units[[pn]], collapse = ", "), " -> ",
            pollutants$unit[match(pn, pollutants$delta)],
            if (!is.na(obs_factors[[pn]]) && obs_factors[[pn]] != 1) paste0(" (x", format(obs_factors[[pn]], digits = 6), ")") else "")
  }
  series <- lapply(parts, function(s) {
    s <- s[!duplicated(s$time), ]
    s$value[match(as.numeric(grid_t), as.numeric(s$time))]
  })
  sp_tab <- do.call(rbind, recs[names(series)])
  rownames(sp_tab) <- NULL
  sp_tab$cov <- vapply(sp_tab$sp, function(s) sum(!is.na(series[[s]])), numeric(1))
  message("Osservazioni: ", length(files), " file, ", skipped, " saltati, ", sum(sp_tab$cov > 0),
          " sampling point con dati validi nel periodo")
  sp_tab$frac <- sp_tab$cov / length(grid_t)
  nodata <- sp_tab[sp_tab$cov == 0, ]
  if (nrow(nodata)) {
    .disc[[length(.disc) + 1]] <- .disc_row(nodata$eoi, nodata$sp, nodata$name, nodata$lon, nodata$lat,
                                            nodata$muni, "nessun dato valido nel periodo richiesto")
  }
  low <- sp_tab$cov > 0 & sp_tab$frac < min_coverage
  if (any(low)) {
    lw <- sp_tab[low, ]
    .disc[[length(.disc) + 1]] <- .disc_row(lw$eoi, lw$sp, lw$name, lw$lon, lw$lat, lw$muni,
      sprintf("copertura %.0f%% di ore valide, sotto la soglia del %.0f%% (%s)", 100 * lw$frac,
              100 * min_coverage, lw$pol))
    message("Sampling point sotto la soglia di copertura del ", format(100 * min_coverage), "%: ", sum(low))
  }
  sp_tab <- sp_tab[sp_tab$cov > 0 & !low, ]
  if (!nrow(sp_tab)) stop("Nessun dato osservato valido nel periodo richiesto")

  # I valori dei metadati si lasciano come sono, record per record (la stessa stazione puo'
  # avere coordinate, tipo o area diversi tra i sampling point). Solo dove il dato manca si
  # usa quello degli altri record della stessa stazione (vedi fill_missing_by_station).
  filled <- character()
  for (cols in list(c("lon", "lat"), "alt", "area", "type")) {
    sp_tab <- fill_missing_by_station(sp_tab, cols)
    filled <- c(filled, attr(sp_tab, "filled"))
  }
  if (length(filled)) message("Dati mancanti nei metadati, completati con quelli della stessa ",
                              "stazione: ", paste(unique(filled), collapse = ", "))

  ## 2. Un file per (stazione, posizione/tipo/area, livello): lettere a, b, c ... ----
  # La stessa stazione EoI si divide in piu' file se i suoi record hanno coordinate, tipo
  # o area DIVERSI (valori come nel DataExtract, dopo il completamento dei dati mancanti).
  # Dentro ogni (stazione, valori, inquinante) lo stesso inquinante da piu' sampling point
  # prende livelli successivi: prima chi ha piu' dati validi. I file di una stazione sono
  # poi ordinati per livello e, a parita', per dati validi totali.
  chr <- function(x) ifelse(is.na(x), "NA", as.character(x))
  sp_tab$key <- paste(chr(sp_tab$lon), chr(sp_tab$lat), chr(sp_tab$area), chr(sp_tab$type), sep = "|")
  sp_tab <- sp_tab[order(sp_tab$eoi, sp_tab$key, sp_tab$pol, -sp_tab$cov, sp_tab$sp), ]
  sp_tab$level <- stats::ave(seq_len(nrow(sp_tab)), sp_tab$eoi, sp_tab$key, sp_tab$pol, FUN = seq_along)
  sp_tab$slot <- paste(sp_tab$eoi, sp_tab$key, sp_tab$level, sep = "#")
  slots <- sp_tab[!duplicated(sp_tab$slot), c("eoi", "key", "level", "slot")]
  slots$tot <- as.numeric(tapply(sp_tab$cov, sp_tab$slot, sum)[slots$slot])
  slots <- slots[order(slots$eoi, slots$level, -slots$tot, slots$key), ]
  slots$n <- stats::ave(seq_len(nrow(slots)), slots$eoi, FUN = seq_along)
  if (max(slots$n) > 26) stop("Piu' di 26 file per la stessa stazione EoI")
  sp_tab$id <- paste0(sp_tab$eoi, letters[slots$n[match(sp_tab$slot, slots$slot)]])
  nsplit <- sum(tapply(slots$n, slots$eoi, max) > 1)
  if (nsplit) message("Stazioni EEA divise in piu' file (coordinate, tipo, area o sampling point diversi): ", nsplit)

  ## 3. Un file per id (stazione + lettera): posizione, cella FARM, comune -----------
  # Il file prende i metadati del suo primo inquinante (nell'ordine della tabella); la
  # cella FARM e il comune sono quelli di QUELLA posizione, anche se un'altra lettera
  # della stessa stazione ha coordinate diverse.
  ord_pol <- match(sp_tab$pol, pollutants$delta)
  sp_tab <- sp_tab[order(sp_tab$id, ord_pol), ]
  ft <- sp_tab[!duplicated(sp_tab$id), c("id", "eoi", "nat", "lon", "lat", "alt", "type", "area", "name", "muni")]
  nocoord <- is.na(ft$lon) | is.na(ft$lat)
  if (any(nocoord)) {
    warning("File senza coordinate nei metadati, scartati: ", paste(ft$id[nocoord], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[nocoord], ft$id[nocoord], ft$name[nocoord], NA, NA,
                                            ft$muni[nocoord], "coordinate mancanti nel DataExtract.csv")
    ft <- ft[!nocoord, ]
  }
  if (!nrow(ft)) stop("Nessuna stazione con coordinate nei metadati")
  if (!obs_hour_label %in% c("start", "end")) stop("obs_hour_label deve essere \"start\" o \"end\"")
  if (!model_interp %in% c("nearest", "bilinear")) stop("model_interp deve essere \"nearest\" o \"bilinear\"")
  if (!model_grid %in% c("utm", "lonlat")) stop("model_grid deve essere \"utm\" o \"lonlat\"")
  g <- farm_grid(farm_files(model_dir, model_pattern, model_version)[1], model_x_dim, model_y_dim)
  if (model_grid == "utm") {
    utm <- lonlat_to_utm(ft$lon, ft$lat, lon0 = utm_lon0)
    cell <- nearest_cell(utm$x / 1000, utm$y / 1000, g$x, g$y)   # griglia in km
  } else {
    cell <- nearest_cell(ft$lon, ft$lat, g$x, g$y)                # griglia in gradi
  }
  outside <- is.na(cell$ix)
  if (any(outside)) {
    warning("File fuori dalla griglia FARM, scartati: ", paste(ft$id[outside], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[outside], ft$id[outside], ft$name[outside], ft$lon[outside],
                                            ft$lat[outside], ft$muni[outside], "fuori dalla griglia del modello")
  }
  ft <- ft[!outside, ]
  ft$ix <- cell$ix[!outside]
  ft$iy <- cell$iy[!outside]
  if (!nrow(ft)) stop("Nessuna stazione dentro la griglia FARM")

  # Regione e comune dai limiti ISTAT. Senza non si puo' scrivere lo startup,
  # quindi i file lontani da ogni comune sono scartati.
  geo <- istat_lookup(bnd, ft$lon, ft$lat, comune_col, region_col, istat_max_dist_m,
                      province_col, province_abbr_col)
  no_geo <- is.na(geo$comune) | is.na(geo$region)
  if (any(no_geo)) {
    warning("File a piu' di ", istat_max_dist_m, " m da ogni comune ISTAT, scartati: ",
            paste(ft$id[no_geo], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[no_geo], ft$id[no_geo], ft$name[no_geo], ft$lon[no_geo],
                                            ft$lat[no_geo], ft$muni[no_geo],
                                            paste0("a piu' di ", istat_max_dist_m, " m da ogni comune ISTAT"))
  }
  ft <- ft[!no_geo, ]
  ft$region <- geo$region[!no_geo]
  ft$comune <- geo$comune[!no_geo]
  if (!nrow(ft)) stop("Nessuna stazione con comune e regione ISTAT")
  sp_tab <- sp_tab[sp_tab$id %in% ft$id, ]

  ## 4. Modellato nelle celle delle stazioni -----------------------------------
  used <- intersect(pollutants$delta, unique(sp_tab$pol))
  # Celle e pesi per le stazioni rimaste (stessa griglia e coordinate dell'abbinamento sopra).
  cells <- if (model_grid == "utm") {
    u <- lonlat_to_utm(ft$lon, ft$lat, lon0 = utm_lon0)
    interp_cells(u$x / 1000, u$y / 1000, g$x, g$y, model_interp)
  } else {
    interp_cells(ft$lon, ft$lat, g$x, g$y, model_interp)
  }
  mod <- read_farm_series(model_dir, cells,
                          stats::setNames(pollutants$farm[match(used, pollutants$delta)], used),
                          pattern = model_pattern, version = model_version,
                          x_dim = model_x_dim, y_dim = model_y_dim, time_dim = model_time_dim,
                          out_units = stats::setNames(pollutants$unit[match(used, pollutants$delta)], used),
                          factors = stats::setNames(pollutants$model_factor[match(used, pollutants$delta)], used))
  for (pn in used) {
    message("Unita' modello ", pn, " (", pollutants$farm[match(pn, pollutants$delta)], "): ",
            paste(mod$units[[pn]], collapse = ", "), " -> ", pollutants$unit[match(pn, pollutants$delta)],
            if (!is.na(mod$factors[[pn]]) && mod$factors[[pn]] != 1) paste0(" (x", format(mod$factors[[pn]], digits = 6), ")") else "")
  }
  # I NetCDF sono nel fuso model_tz_offset: li portiamo a tz_offset come le osservazioni.
  mod_t <- mod$time + (tz_offset - model_tz_offset) * 3600
  mi <- match(as.numeric(grid_t + model_shift_h * 3600), as.numeric(mod_t))
  if (all(is.na(mi))) stop("Il modellato non copre il periodo richiesto")
  if (anyNA(mi)) {
    nm <- grid_t[is.na(mi)]
    warning(sum(is.na(mi)), " ore su ", length(mi), " senza modellato: scritte come -999 (",
            paste(format(utils::head(nm, 8), "%Y-%m-%d %H:00"), collapse = ", "),
            if (length(nm) > 8) ", ..." else "", ")", call. = FALSE)
  }

  ## 5. Scrittura ------------------------------------------------------------
  if (is.null(out_label)) {
    out_label <- paste(c(year,
                         if (!is.null(model_version) && nzchar(model_version)) model_version,
                         if (!is.null(species)) paste(pollutants$delta, collapse = "-"),
                         if (!is.null(period)) paste(format(period[c(1, length(period))], "%Y%m%d"), collapse = "-")),
                       collapse = "_")
  }
  if (nzchar(out_label)) out_dir <- file.path(out_dir, out_label)
  message("Output in: ", out_dir)
  dir.create(file.path(out_dir, "obs"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "mod"), recursive = TRUE, showWarnings = FALSE)
  stations <- list()
  for (id in unique(sp_tab$id)) {
    sel <- sp_tab[sp_tab$id == id, ]
    sel <- sel[match(intersect(pollutants$delta, sel$pol), sel$pol), ]
    col <- match(id, ft$id)
    om <- vapply(sel$sp, function(s) series[[s]], numeric(length(grid_t)))
    mm <- vapply(sel$pol, function(p) mod$data[[p]][mi, col], numeric(length(grid_t)))
    om <- matrix(om, nrow = length(grid_t), dimnames = list(NULL, sel$pol))
    mm <- matrix(mm, nrow = length(grid_t), dimnames = list(NULL, sel$pol))
    write_delta_csv(grid_t, om, file.path(out_dir, "obs", paste0(id, ".csv")), eol)
    write_delta_csv(grid_t, mm, file.path(out_dir, "mod", paste0(id, ".csv")), eol)
    m <- ft[col, ]
    stations[[id]] <- data.frame(
      id = id, code = paste0(gsub("[^A-Za-z0-9]", "", m$nat), substr(id, nchar(id), nchar(id))),   # solo lettere e cifre
      alt = ifelse(is.na(m$alt), 0, m$alt), lon = m$lon, lat = m$lat,
      region = clean_name(m$region), type = m$type, area = m$area,
      siting = clean_name(m$comune),
      vars = paste(sel$pol, collapse = "*"), eoi = m$eoi, stringsAsFactors = FALSE)
  }
  st <- do.call(rbind, stations)
  # Station Code, Station Name e Station abbreviation devono essere UNICI. Name e abbreviation
  # sono l'id (codice EoI + lettera), unico per costruzione. Il codice e' "<Nat Code><lettera>",
  # ma lo stesso Nat Code puo' essere in piu' stazioni EoI: in quel caso si aggiunge l'EoI.
  dupc <- st$code %in% st$code[duplicated(st$code)]
  if (any(dupc)) {
    warning("Station Code duplicato (stesso Nat Code in stazioni EoI diverse), aggiunto l'EoI: ",
            paste(unique(st$code[dupc]), collapse = ", "), call. = FALSE)
    st$code[dupc] <- paste0(st$code[dupc], st$eoi[dupc])
  }
  if (anyDuplicated(st$code) || anyDuplicated(st$id) || anyDuplicated(tolower(st$id))) {
    stop("Station Code, Station Name o Station abbreviation non sono unici: ",
         paste(unique(c(st$code[duplicated(st$code)], st$id[duplicated(tolower(st$id))])), collapse = ", "))
  }
  # [PARAMETERS] elenca solo le specie che hanno davvero dati in almeno un file.
  noobs <- setdiff(pollutants$delta, sp_tab$pol)
  if (length(noobs)) message("Specie senza osservazioni (non scritte nello startup): ", paste(noobs, collapse = ", "))
  pollutants <- pollutants[pollutants$delta %in% sp_tab$pol, , drop = FALSE]
  write_startup(st, file.path(out_dir, startup_name), year, pollutants, gmt_lag, scale, eol)
  message("Fatto: ", nrow(st), " file di stazione (", length(unique(st$eoi)), " stazioni EEA) per ",
          length(grid_t), " ore, specie: ", paste(pollutants$delta, collapse = ", "))
  list(stations = st, sampling_points = sp_tab, out_dir = out_dir)
  }, warning = function(w) {
    .wlog <<- c(.wlog, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  # File di rapporto: avvisi completi e stazioni scartate (con comune e provincia).
  .dt <- .mk_dt()
  if (length(.wlog)) writeLines(.wlog, file.path(.res$out_dir, warnings_name), useBytes = TRUE)
  if (!is.null(.dt)) {
    utils::write.table(.dt, file.path(.res$out_dir, discarded_name), sep = ";", row.names = FALSE,
                       na = "", quote = FALSE, fileEncoding = "UTF-8")
  }
  .res$warnings <- .wlog
  .res$discarded <- .dt
  invisible(.res)
}
