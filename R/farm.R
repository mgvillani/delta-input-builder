# Reading the FARM NetCDF files (variables c_NO2, c_O3, ...; dimensions x,y,z,time;
# x,y in UTM km; time in "hours since ...").

# `pattern`: regular expression on the file name. `version`: text (not a regex) the
# name must contain, to choose a model version/run (e.g. "g2", "v5").
farm_files <- function(model_dir, pattern, version) {
  f <- sort(list.files(model_dir, pattern = pattern, full.names = TRUE))
  if (!is.null(version) && length(version) == 1 && !is.na(version) && nzchar(version)) {
    f <- f[grepl(version, basename(f), fixed = TRUE)]
  }
  if (!length(f)) {
    stop("No NetCDF files in ", model_dir, " (pattern ", pattern,
         if (!is.null(version)) paste0(", version '", version, "'") else "", ")")
  }
  f
}

# CF time ("<unit> since <origin>", units seconds/minutes/hours/days) -> POSIXct UTC.
.cf_hours_to_posix <- function(values, units) {
  m <- regmatches(units, regexec("^\\s*(second|minute|hour|day)s?\\s+since\\s+(.*)$", units, ignore.case = TRUE))[[1]]
  if (length(m) != 3) stop("Time units not handled: ", units)
  mult <- c(second = 1, minute = 60, hour = 3600, day = 86400)[[tolower(m[2])]]
  o <- sub("\\s*(UTC|GMT|Z)?\\s*$", "", trimws(m[3]))
  origin <- NA
  for (fmt in c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M", "%Y-%m-%d")) {
    origin <- as.POSIXct(o, tz = "UTC", format = fmt)
    if (!is.na(origin)) break
  }
  if (is.na(origin)) stop("Time origin cannot be interpreted: ", units)
  origin + values * mult
}

# Grid coordinates from the first file: values of the dimensions `x_dim` and `y_dim`
# (e.g. "x","y" in UTM km; or "lon","lat" in degrees).
farm_grid <- function(file, x_dim, y_dim) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  if (is.null(nc$dim[[x_dim]]) || is.null(nc$dim[[y_dim]]) ||
      !length(nc$dim[[x_dim]]$vals) || !length(nc$dim[[y_dim]]$vals)) {
    stop("In the NetCDF '", basename(file), "' I cannot find the grid dimensions '", x_dim, "' and '", y_dim,
         "' (dimensions present: ", paste(names(nc$dim), collapse = ", "),
         "): set them with model_x_dim and model_y_dim")
  }
  list(x = as.numeric(nc$dim[[x_dim]]$vals), y = as.numeric(nc$dim[[y_dim]]$vals))
}

# Names of the variables present in the file.
farm_varnames <- function(file) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  names(nc$var)
}

# Index of the nearest cell; NA if the point falls outside the grid.
nearest_cell <- function(px_km, py_km, gx, gy) {
  half_x <- abs(stats::median(diff(gx))) / 2
  half_y <- abs(stats::median(diff(gy))) / 2
  near <- function(v, g) vapply(v, function(p) if (is.na(p)) NA_integer_ else which.min(abs(g - p)),
                                integer(1))
  ix <- near(px_km, gx)
  iy <- near(py_km, gy)
  inside <- abs(gx[ix] - px_km) <= half_x + 1e-9 & abs(gy[iy] - py_km) <= half_y + 1e-9
  inside[is.na(inside)] <- FALSE   # point without coordinates: outside
  ix[!inside] <- NA_integer_
  iy[!inside] <- NA_integer_
  list(ix = ix, iy = iy)
}

# Cells and weights for each point. `interp`:
#   "nearest"  : cell with the nearest centre (weight 1);
#   "bilinear" : bilinear interpolation among the centres of the 4 cells around the point
#                (as raster::extract(..., method = "bilinear")). A point between the last centre and
#                the grid edge (within half a cell) uses the edge cells (fixed weight).
# Returns ix0, ix1, iy0, iy1 (indices of the 2 cells per axis) and wx, wy (weight of the second).
interp_cells <- function(px, py, gx, gy, interp) {
  n <- length(px)
  if (identical(interp, "nearest")) {
    nc <- nearest_cell(px, py, gx, gy)
    return(list(ix0 = nc$ix, ix1 = nc$ix, iy0 = nc$iy, iy1 = nc$iy, wx = rep(0, n), wy = rep(0, n)))
  }
  if (!identical(interp, "bilinear")) stop("model_interp must be \"nearest\" or \"bilinear\"")
  axis <- function(p, g) {
    o <- order(g); gs <- g[o]
    k <- findInterval(p, gs, all.inside = TRUE)
    t <- pmin(1, pmax(0, (p - gs[k]) / (gs[k + 1] - gs[k])))
    list(i0 = o[k], i1 = o[k + 1], w = t)
  }
  ax <- axis(px, gx); ay <- axis(py, gy)
  list(ix0 = ax$i0, ix1 = ax$i1, iy0 = ay$i0, iy1 = ay$i1, wx = ax$w, wy = ay$w)
}

# Time series in the given cells. Returns
#   $time : POSIXct UTC (no duplicates; for hours repeated between consecutive
#           files, e.g. 00 of the next day, the most recent file wins)
#   $data : list per pollutant of [time x station] matrices
#   $time is the time written to the files (see model_tz_offset in build.R).
# `vars`: vector with names = DELTA pollutant, values = NetCDF variable.
# `out_units`, `factors`: per pollutant (same names as `vars`), output unit and manual
# factor (NA = derived from the "units" attribute of the NetCDF variable).
# `cells`: output of interp_cells() (cells and weights per station).
# `x_dim`, `y_dim`, `time_dim`: dimension names; the order of the variable's dimensions
# does not matter (the others, e.g. height, are reduced to the first level).
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
      stop("The NetCDF '", basename(files[k]), "' has no time dimension '", time_dim,
           "' (present: ", paste(names(nc$dim), collapse = ", "), "): set it with model_time_dim")
    }
    tm <- .cf_hours_to_posix(as.numeric(nc$dim[[time_dim]]$vals), nc$dim[[time_dim]]$units)
    times[[k]] <- tm
    for (p in pollutants) {
      dn <- vapply(nc$var[[vars[[p]]]]$dim, function(d) d$name, character(1))
      need <- c(x_dim, y_dim, time_dim)
      if (!all(need %in% dn)) {
        stop("The variable '", vars[[p]], "' does not have the dimensions ", paste(need, collapse = ", "),
             " (it has: ", paste(dn, collapse = ", "), ")")
      }
      u <- ncdf4::ncatt_get(nc, vars[[p]], "units")
      unit_in <- if (u$hasatt) as.character(u$value) else NA_character_
      if (is.na(unit_in) && is.na(factors[[p]])) {
        stop("The variable '", vars[[p]], "' has no 'units' attribute: write model_factor for ", p,
             " in the pollutants table")
      }
      fac <- unit_factor(unit_in, out_units[[p]], factors[[p]], paste0("the model variable '", vars[[p]], "'"))
      units_seen[[p]] <- union(units_seen[[p]], unit_in)
      factor_used[[p]] <- fac[1]
      a <- ncdf4::ncvar_get(nc, vars[[p]], collapse_degen = FALSE)   # also keeps length-1 dimensions
      d <- dim(a)
      if (is.null(d)) d <- length(a)
      a <- array(a, dim = d)
      a <- aperm(a, c(match(need, dn), setdiff(seq_along(dn), match(need, dn))))
      a <- array(a, dim = dim(a)[1:3])           # drops the other dimensions (first level)
      val_at <- function(s) {
        w <- c((1 - cells$wx[s]) * (1 - cells$wy[s]), cells$wx[s] * (1 - cells$wy[s]),
               (1 - cells$wx[s]) * cells$wy[s], cells$wx[s] * cells$wy[s])
        ii <- c(cells$ix0[s], cells$ix1[s], cells$ix0[s], cells$ix1[s])
        jj <- c(cells$iy0[s], cells$iy0[s], cells$iy1[s], cells$iy1[s])
        out <- 0
        for (q in which(w > 0)) out <- out + w[q] * a[ii[q], jj[q], ]   # an NA in the cells used gives NA
        out
      }
      vals[[p]][[k]] <- fac[1] * vapply(seq_along(cells$ix0), val_at, numeric(length(tm)))
      if (length(tm) == 1) vals[[p]][[k]] <- matrix(vals[[p]][[k]], nrow = 1)
    }
    ncdf4::nc_close(nc)
  }
  time <- do.call(c, times)
  # Consecutive files share at most one hour (00 of the next day): many repeated hours
  # mean the folder holds several versions/runs of the same period.
  if (sum(duplicated(as.numeric(time))) > length(files)) {
    warning("Many hours appear in several files (", sum(duplicated(as.numeric(time))),
            " duplicates over ", length(files), " files): there are probably several model versions ",
            "in the folder; the last file in name order wins. Use model_version or model_pattern ",
            "to choose one.", call. = FALSE)
  }
  keep <- !duplicated(as.numeric(time), fromLast = TRUE)
  data <- lapply(vals, function(l) do.call(rbind, l)[keep, , drop = FALSE])
  list(time = time[keep], data = data, units = units_seen, factors = factor_used)
}
