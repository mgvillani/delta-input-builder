# Lettura dei NetCDF FARM (variabili c_NO2, c_O3, ...; dimensioni x,y,z,time;
# x,y in km UTM; time in "hours since ...").

# `pattern`: espressione regolare sul nome del file. `version`: testo (non regex) che
# il nome deve contenere, per scegliere una versione/run del modello (es. "g2", "v5").
farm_files <- function(model_dir, pattern, version) {
  f <- sort(list.files(model_dir, pattern = pattern, full.names = TRUE))
  if (!is.null(version) && length(version) == 1 && !is.na(version) && nzchar(version)) {
    f <- f[grepl(version, basename(f), fixed = TRUE)]
  }
  if (!length(f)) {
    stop("Nessun file NetCDF in ", model_dir, " (pattern ", pattern,
         if (!is.null(version)) paste0(", versione '", version, "'") else "", ")")
  }
  f
}

# Tempo CF ("<unita'> since <origine>", unita' seconds/minutes/hours/days) -> POSIXct UTC.
.cf_hours_to_posix <- function(values, units) {
  m <- regmatches(units, regexec("^\\s*(second|minute|hour|day)s?\\s+since\\s+(.*)$", units, ignore.case = TRUE))[[1]]
  if (length(m) != 3) stop("Unita' del tempo non gestita: ", units)
  mult <- c(second = 1, minute = 60, hour = 3600, day = 86400)[[tolower(m[2])]]
  o <- sub("\\s*(UTC|GMT|Z)?\\s*$", "", trimws(m[3]))
  origin <- NA
  for (fmt in c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M", "%Y-%m-%d")) {
    origin <- as.POSIXct(o, tz = "UTC", format = fmt)
    if (!is.na(origin)) break
  }
  if (is.na(origin)) stop("Origine del tempo non interpretabile: ", units)
  origin + values * mult
}

# Coordinate della griglia dal primo file: valori delle dimensioni `x_dim` e `y_dim`
# (es. "x","y" in km UTM; oppure "lon","lat" in gradi).
farm_grid <- function(file, x_dim, y_dim) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  if (is.null(nc$dim[[x_dim]]) || is.null(nc$dim[[y_dim]]) ||
      !length(nc$dim[[x_dim]]$vals) || !length(nc$dim[[y_dim]]$vals)) {
    stop("Nel NetCDF '", basename(file), "' non trovo le dimensioni '", x_dim, "' e '", y_dim,
         "' della griglia (dimensioni presenti: ", paste(names(nc$dim), collapse = ", "),
         "): impostale con model_x_dim e model_y_dim")
  }
  list(x = as.numeric(nc$dim[[x_dim]]$vals), y = as.numeric(nc$dim[[y_dim]]$vals))
}

# Nomi delle variabili presenti nel file.
farm_varnames <- function(file) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  names(nc$var)
}

# Indice della cella piu' vicina; NA se il punto cade fuori dalla griglia.
nearest_cell <- function(px_km, py_km, gx, gy) {
  half_x <- abs(stats::median(diff(gx))) / 2
  half_y <- abs(stats::median(diff(gy))) / 2
  near <- function(v, g) vapply(v, function(p) if (is.na(p)) NA_integer_ else which.min(abs(g - p)),
                                integer(1))
  ix <- near(px_km, gx)
  iy <- near(py_km, gy)
  inside <- abs(gx[ix] - px_km) <= half_x + 1e-9 & abs(gy[iy] - py_km) <= half_y + 1e-9
  inside[is.na(inside)] <- FALSE   # punto senza coordinate: fuori
  ix[!inside] <- NA_integer_
  iy[!inside] <- NA_integer_
  list(ix = ix, iy = iy)
}

# Celle e pesi per ogni punto. `interp`:
#   "nearest"  : cella con il centro piu' vicino (peso 1);
#   "bilinear" : interpolazione bilineare tra i centri delle 4 celle che circondano il punto
#                (come raster::extract(..., method = "bilinear")). Un punto tra l'ultimo centro e
#                il bordo della griglia (entro mezza cella) usa le celle del bordo (peso fisso).
# Ritorna ix0, ix1, iy0, iy1 (indici delle 2 celle per asse) e wx, wy (peso della seconda).
interp_cells <- function(px, py, gx, gy, interp) {
  n <- length(px)
  if (identical(interp, "nearest")) {
    nc <- nearest_cell(px, py, gx, gy)
    return(list(ix0 = nc$ix, ix1 = nc$ix, iy0 = nc$iy, iy1 = nc$iy, wx = rep(0, n), wy = rep(0, n)))
  }
  if (!identical(interp, "bilinear")) stop("model_interp deve essere \"nearest\" o \"bilinear\"")
  axis <- function(p, g) {
    o <- order(g); gs <- g[o]
    k <- findInterval(p, gs, all.inside = TRUE)
    t <- pmin(1, pmax(0, (p - gs[k]) / (gs[k + 1] - gs[k])))
    list(i0 = o[k], i1 = o[k + 1], w = t)
  }
  ax <- axis(px, gx); ay <- axis(py, gy)
  list(ix0 = ax$i0, ix1 = ax$i1, iy0 = ay$i0, iy1 = ay$i1, wx = ax$w, wy = ay$w)
}

# Serie temporali nelle celle indicate. Ritorna
#   $time : POSIXct UTC (senza duplicati; per le ore ripetute tra file
#           consecutivi, es. 00 del giorno dopo, vince il file piu' recente)
#   $data : lista per inquinante di matrici [tempo x stazione]
#   $time e' il tempo scritto nei file (vedi model_tz_offset in build.R).
# `vars`: vettore con nomi = inquinante DELTA, valori = variabile NetCDF.
# `out_units`, `factors`: per inquinante (stessi nomi di `vars`), unita' di uscita e fattore
# manuale (NA = si ricava dall'attributo "units" della variabile NetCDF).
# `cells`: lista di interp_cells() (celle e pesi per stazione).
# `x_dim`, `y_dim`, `time_dim`: nomi delle dimensioni; l'ordine delle dimensioni della
# variabile non conta (le altre, es. la quota, sono ridotte al primo livello).
read_farm_series <- function(model_dir, cells, vars, pattern, version, x_dim, y_dim, time_dim,
                             out_units, factors) {
  files <- farm_files(model_dir, pattern, version)
  pollutants <- names(vars)
  times <- vector("list", length(files))
  units_seen <- setNames(vector("list", length(pollutants)), pollutants)
  factor_used <- setNames(rep(NA_real_, length(pollutants)), pollutants)
  vals <- setNames(lapply(pollutants, function(p) vector("list", length(files))), pollutants)
  for (k in seq_along(files)) {
    nc <- ncdf4::nc_open(files[k])
    if (is.null(nc$dim[[time_dim]])) {
      stop("Nel NetCDF '", basename(files[k]), "' manca la dimensione tempo '", time_dim,
           "' (presenti: ", paste(names(nc$dim), collapse = ", "), "): impostala con model_time_dim")
    }
    tm <- .cf_hours_to_posix(as.numeric(nc$dim[[time_dim]]$vals), nc$dim[[time_dim]]$units)
    times[[k]] <- tm
    for (p in pollutants) {
      dn <- vapply(nc$var[[vars[[p]]]]$dim, function(d) d$name, character(1))
      need <- c(x_dim, y_dim, time_dim)
      if (!all(need %in% dn)) {
        stop("La variabile '", vars[[p]], "' non ha le dimensioni ", paste(need, collapse = ", "),
             " (ha: ", paste(dn, collapse = ", "), ")")
      }
      u <- ncdf4::ncatt_get(nc, vars[[p]], "units")
      unit_in <- if (u$hasatt) as.character(u$value) else NA_character_
      if (is.na(unit_in) && is.na(factors[[p]])) {
        stop("La variabile '", vars[[p]], "' non ha l'attributo 'units': scrivi model_factor per ", p,
             " nella tabella pollutants")
      }
      fac <- unit_factor(unit_in, out_units[[p]], factors[[p]], paste0("la variabile '", vars[[p]], "' del modello"))
      units_seen[[p]] <- union(units_seen[[p]], unit_in)
      factor_used[[p]] <- fac[1]
      a <- ncdf4::ncvar_get(nc, vars[[p]], collapse_degen = FALSE)   # tiene anche le dimensioni di lunghezza 1
      d <- dim(a)
      if (is.null(d)) d <- length(a)
      a <- array(a, dim = d)
      a <- aperm(a, c(match(need, dn), setdiff(seq_along(dn), match(need, dn))))
      a <- array(a, dim = dim(a)[1:3])           # elimina le altre dimensioni (primo livello)
      val_at <- function(s) {
        w <- c((1 - cells$wx[s]) * (1 - cells$wy[s]), cells$wx[s] * (1 - cells$wy[s]),
               (1 - cells$wx[s]) * cells$wy[s], cells$wx[s] * cells$wy[s])
        ii <- c(cells$ix0[s], cells$ix1[s], cells$ix0[s], cells$ix1[s])
        jj <- c(cells$iy0[s], cells$iy0[s], cells$iy1[s], cells$iy1[s])
        out <- 0
        for (q in which(w > 0)) out <- out + w[q] * a[ii[q], jj[q], ]   # un NA nelle celle usate da' NA
        out
      }
      vals[[p]][[k]] <- fac[1] * vapply(seq_along(cells$ix0), val_at, numeric(length(tm)))
      if (length(tm) == 1) vals[[p]][[k]] <- matrix(vals[[p]][[k]], nrow = 1)
    }
    ncdf4::nc_close(nc)
  }
  time <- do.call(c, times)
  # File consecutivi condividono al piu' un'ora (la 00 del giorno dopo): molte ore ripetute
  # vuol dire che nella cartella ci sono piu' versioni/run dello stesso periodo.
  if (sum(duplicated(as.numeric(time))) > length(files)) {
    warning("Molte ore compaiono in piu' file (", sum(duplicated(as.numeric(time))),
            " duplicati su ", length(files), " file): probabilmente ci sono piu' versioni del modello ",
            "nella cartella; vince l'ultimo file in ordine di nome. Usa model_version o model_pattern ",
            "per sceglierne una.", call. = FALSE)
  }
  keep <- !duplicated(as.numeric(time), fromLast = TRUE)
  data <- lapply(vals, function(l) do.call(rbind, l)[keep, , drop = FALSE])
  list(time = time[keep], data = data, units = units_seen, factors = factor_used)
}
