# Comune e regione di ogni stazione dai limiti amministrativi ISTAT.
# I limiti ISTAT sono OBBLIGATORI e vanno messi in una cartella dedicata
# (es. dati/istat/). ISTAT pubblica una edizione ogni anno (Limiti01012023.zip,
# Limiti01012024.zip, ...): la cartella puo' contenerne quante se ne vuole, come zip
# oppure come cartelle gia' estratte (Com01012023/, Reg01012023/, ...). L'edizione si
# riconosce dalla data nel nome dei layer (Com01012023_WGS84.shp -> 2023).

# Anno dell'edizione dal nome di un layer: Com01012023_WGS84.shp -> 2023 (NA se assente).
.istat_edition <- function(shp_names) {
  b <- basename(shp_names)
  ifelse(grepl("^(ProvCM|Com|Reg)[0-9]{4}[0-9]{4}", b, ignore.case = TRUE),
         suppressWarnings(as.integer(sub("^(ProvCM|Com|Reg)[0-9]{4}([0-9]{4}).*$", "\\2", b,
                                         ignore.case = TRUE))),
         NA_integer_)
}

# Sceglie l'edizione: quella di `year` se c'e'; altrimenti la piu' recente precedente
# (o, se non ce ne sono, la piu' vecchia successiva), con un avviso.
.pick_edition <- function(editions, year, dir) {
  ed <- sort(unique(editions[!is.na(editions)]))
  if (!length(ed)) return(NA_integer_)
  if (is.null(year) || year %in% ed) return(if (is.null(year)) max(ed) else as.integer(year))
  chosen <- if (any(ed < year)) max(ed[ed < year]) else min(ed)
  warning("Nessuna edizione ISTAT del ", year, " in '", dir, "' (disponibili: ",
          paste(ed, collapse = ", "), "): uso l'edizione ", chosen, ".", call. = FALSE)
  chosen
}

# Legge dalla cartella `dir` i layer dei comuni (Com*) e delle regioni (Reg*)
# dell'edizione ISTAT dell'anno `year` (vedi .pick_edition). Con year = NULL usa
# la piu' recente.
read_istat_boundaries <- function(dir, year) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Serve il pacchetto 'sf' per leggere i limiti ISTAT: install.packages(\"sf\")")
  }
  if (is.null(dir) || !is.character(dir) || length(dir) != 1 || !dir.exists(dir)) {
    stop("La cartella dei limiti ISTAT (istat_dir) e' obbligatoria e deve esistere: ",
         if (is.character(dir) && length(dir) == 1) dir else "non indicata")
  }
  is_layer <- function(x, prefix) grepl(paste0("^", prefix, "[0-9]"), basename(x), ignore.case = TRUE)
  shp_ext <- list.files(dir, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE,
                        ignore.case = TRUE)
  shp_ext <- shp_ext[is_layer(shp_ext, "Com") | is_layer(shp_ext, "Reg") | is_layer(shp_ext, "ProvCM")]
  zips <- list.files(dir, pattern = "\\.zip$", full.names = TRUE, ignore.case = TRUE)
  if (!length(zips) && !length(shp_ext)) {
    stop("Nessun limite ISTAT in '", dir, "': copia qui lo zip scaricato da ISTAT ",
         "(es. Limiti01012023.zip) oppure le cartelle gia' estratte.")
  }

  # Elenco dei layer disponibili (senza estrarre nulla): sorgente, nome, edizione.
  parts <- list()
  if (length(shp_ext)) {
    parts[[1]] <- data.frame(zip = NA_character_, path = shp_ext, stringsAsFactors = FALSE)
  }
  for (z in zips) {
    nm <- utils::unzip(z, list = TRUE)$Name
    nm <- nm[grepl("\\.shp$", nm, ignore.case = TRUE) & (is_layer(nm, "Com") | is_layer(nm, "Reg") | is_layer(nm, "ProvCM"))]
    if (length(nm)) parts[[length(parts) + 1]] <- data.frame(zip = z, path = nm, stringsAsFactors = FALSE)
  }
  if (!length(parts)) {
    stop("Nei limiti ISTAT in '", dir, "' mancano i layer Com* (comuni) e Reg* (regioni)")
  }
  lay <- do.call(rbind, parts)
  lay$kind <- ifelse(is_layer(lay$path, "Com"), "Com", ifelse(is_layer(lay$path, "ProvCM"), "ProvCM", "Reg"))
  lay$edition <- .istat_edition(lay$path)

  # Solo le edizioni che hanno sia Com* sia Reg*.
  full <- intersect(lay$edition[lay$kind == "Com"], lay$edition[lay$kind == "Reg"])
  full <- full[!is.na(full)]
  if (length(full)) {
    ed <- .pick_edition(full, year, dir)
    lay <- lay[!is.na(lay$edition) & lay$edition == ed, , drop = FALSE]
  } else {
    ed <- NA_integer_   # nomi senza data: si usa tutto quello che c'e'
  }

  pick <- function(prefix) {
    s <- lay[lay$kind == prefix, , drop = FALSE]
    if (!nrow(s)) stop("Nei limiti ISTAT in '", dir, "' manca il layer ", prefix,
                       "* (comuni: Com*, regioni: Reg*)")
    s <- s[order(s$path, decreasing = TRUE), , drop = FALSE][1, ]
    if (is.na(s$zip)) return(s$path)
    tmp <- tempfile("istat_")
    dir.create(tmp)
    utils::unzip(s$zip, exdir = tmp)
    file.path(tmp, s$path)
  }
  # Il layer delle province (ProvCM*) e' facoltativo: serve solo a scrivere la provincia
  # nel rapporto delle stazioni scartate.
  prov <- if (any(lay$kind == "ProvCM")) sf::st_read(pick("ProvCM"), quiet = TRUE) else NULL
  out <- list(com = sf::st_read(pick("Com"), quiet = TRUE),
              reg = sf::st_read(pick("Reg"), quiet = TRUE), prov = prov)
  attr(out, "edition") <- ed
  out
}

# Nome del comune, della regione e (se c'e' il layer ProvCM) della provincia per ogni punto
# lon/lat (WGS84). Punti con coordinate NA danno NA.
# Un punto fuori da ogni poligono (es. sulla costa) prende il poligono piu'
# vicino se entro `max_dist_m`; oltre il risultato e' NA.
istat_lookup <- function(bnd, lon, lat, comune_col, region_col, max_dist_m,
                         province_col, province_abbr_col) {
  n <- length(lon)
  ok <- !is.na(lon) & !is.na(lat)
  res <- data.frame(comune = rep(NA_character_, n), region = rep(NA_character_, n),
                    provincia = rep(NA_character_, n), stringsAsFactors = FALSE)
  if (!any(ok)) return(res)
  pts_all <- sf::st_as_sf(data.frame(lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4326)
  find <- function(layer, col, strict = TRUE) {
    if (is.null(col) || !col %in% names(layer)) {
      if (!strict) return(rep(NA_character_, nrow(pts_all)))
      stop("Colonna '", col, "' assente nel layer ISTAT (colonne presenti: ",
           paste(setdiff(names(layer), "geometry"), collapse = ", "), ")")
    }
    pts <- sf::st_transform(pts_all, sf::st_crs(layer))
    idx <- vapply(sf::st_intersects(pts, layer),
                  function(h) if (length(h)) h[1] else NA_integer_, integer(1))
    miss <- which(is.na(idx))
    if (length(miss)) {
      nn <- sf::st_nearest_feature(pts[miss, ], layer)
      d <- as.numeric(sf::st_distance(pts[miss, ], layer[nn, ], by_element = TRUE))
      idx[miss] <- ifelse(d <= max_dist_m, nn, NA_integer_)
    }
    as.character(sf::st_drop_geometry(layer)[[col]])[idx]
  }
  res$comune[ok] <- find(bnd$com, comune_col)
  res$region[ok] <- find(bnd$reg, region_col)
  if (!is.null(bnd$prov)) {
    nm <- find(bnd$prov, province_col, strict = FALSE)
    ab <- find(bnd$prov, province_abbr_col, strict = FALSE)
    res$provincia[ok] <- ifelse(is.na(nm) & is.na(ab), NA_character_,
                                ifelse(is.na(ab), nm, ifelse(is.na(nm), ab, paste0(nm, " (", ab, ")"))))
  }
  res
}
