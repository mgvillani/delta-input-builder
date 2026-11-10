# Building the DELTA inputs (legacy format): startup.ini + one CSV per station
# for the observations and one for the model, with the same file name.

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
  fmt <- function(x) as.character(x)   # all the decimals present in the metadata
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

# ALL the parameters are given at once, at the start (see run_example.R): no function in
# the R/ files has default values for file names, folders, time zones or tables.
# Description of the parameters:
#
# Input data
#   obs_dir        folder with the EEA observation files (one per sampling point)
#   obs_pattern    regular expression on the NAME of those files (e.g. "\\.parquet$")
#   meta_csv       EEA DataExtract.csv (station metadata)
#   model_dir      folder with the model NetCDF files (concentrations)
#   model_pattern  regular expression on the NAME of the concentration files to read
#                  (e.g. "^conc_.*\\.nc$" or "^FARM_conc_g2_.*_D1\\.nc$")
#   model_version  text the file name must contain to choose a model version/run
#                  (e.g. "g2", "v5"); NULL = no filter. Combined with model_pattern.
#   istat_dir      folder dedicated to the ISTAT boundaries, holding one zip per year (e.g.
#                  Limiti01012023.zip) or the already extracted folders. Region and Siting of
#                  each station come from here, cleaned of accents and special characters.
#   istat_year     year of the ISTAT edition to use; NULL = `year`. If that year is missing
#                  the latest earlier one is used, with a warning.
#   istat_max_dist_m  maximum distance (m) from the nearest municipality for stations outside
#                  every polygon; beyond it the station is dropped with a warning
#   comune_col, region_col  ISTAT columns with the municipality and region names
#   province_col, province_abbr_col  columns of the ISTAT province layer (ProvCM*) with the
#                  province name and abbreviation: only used by the discarded-stations report
#   pollutants     pollutant table: one row per species, ALL the ones you may want to prepare
#                  (columns delta, eea, farm, type, unit; optional obs_factor, model_factor).
#                  Names and units: see R/units.R. Mass-per-m3 units (ug/m3, mg/m3, ng/m3, ...)
#                  are converted automatically; otherwise give the factor by hand.
#   species        which species of the table to prepare: vector of `delta` names (e.g. c("NO2",
#                  "PM10")); NULL = all. With a selection the automatic output folder name
#                  (out_label = NULL) includes the species.
#
# Output and period
#   out_dir        base output folder
#   out_label      subfolder of `out_dir` where startup.ini, obs/, mod/ are written, so that
#                  different runs do not overwrite each other. NULL = automatic: "<year>", plus
#                  "_<model_version>" if given, plus "_<start>-<end>" if `period` is set (e.g.
#                  "2023_d0", "2023_d0_20230101-20230102"). A string = that name; "" = directly in out_dir
#   startup_name   name of the startup file
#   discarded_name name of the CSV file (in out_dir/out_label) with the discarded stations
#   warnings_name  name of the text file (in out_dir/out_label) with all the warnings
#   year           year of the hourly grid
#   period         NULL = whole year; or c(start, end) as wall-clock time in the
#                  `tz_offset` zone (POSIXct with tz = "UTC" used only as a container)
#   scale          scale written in the startup (e.g. "urban")
#   eol            line ending of the written files ("\n" or "\r\n")
#
# Observation quality
#   valid_codes    codes of the EEA Validity column accepted as valid: c(1) = only "valid";
#                  c(1, 2, 3) also includes data valid below the detection limit
#   min_coverage   minimum fraction (0-1) of valid hours in the period for a sampling point
#                  (station + pollutant) to be used: e.g. 0.75 = at least 75% of the hours.
#                  Below the threshold it is dropped and appears in the discarded-stations report.
#
# Geography
#   model_grid     model grid type: "utm" (x,y in UTM km, as FARM) or
#                  "lonlat" (longitude/latitude in degrees)
#   model_x_dim, model_y_dim, model_time_dim  dimension names in the NetCDF files (e.g. "x", "y",
#                  "time" for FARM; "lon", "lat", "time" for a lon/lat grid)
#   utm_lon0       UTM central meridian of the model coordinates (only model_grid = "utm";
#                  9 for FARM)
#
# Time zones (hours from UTC; 1 = UTC+1, 0 = UTC):
#   tz_offset        time zone of ALL the output files (observed, modelled, hourly
#                    grid) and of the startup GMTLag label
#   obs_tz_offset    time zone of the EEA hours; NULL = the Timezone column of each
#                    station (UTC+01 for Italy)
#   model_tz_offset  time zone written in the model NetCDF files
#   gmt_lag          text of the GMTLag column; NULL = "UTC" if tz_offset = 0,
#                    otherwise "UTC+1", "UTC-2", ...
#   obs_hour_label   hour to which an hourly observation (EEA interval [Start, End)) is assigned:
#                    "start" = starting hour (the 00:00-01:00 value goes to hour 0, as PMSS);
#                    "end" = end hour (it goes to hour 1, like FARM times, which are end-of-hour instants).
#                    Applies to all observations (hourly, daily and variable interval)
#   model_interp     "nearest" = nearest cell; "bilinear" = bilinear interpolation among the
#                    4 cells around the station (as raster::extract(method = "bilinear"))
#   model_shift_h    hours added to the grid time to read the model
#                    (hour convention only, not time zone)
build_delta_inputs <- function(obs_dir, obs_pattern, meta_csv,
                               model_dir, model_pattern, model_version,
                               istat_dir, istat_year, istat_max_dist_m, comune_col, region_col, province_col, province_abbr_col,
                               pollutants, species,
                               out_dir, out_label, startup_name, discarded_name, warnings_name, year, period, scale,
                               valid_codes, min_coverage, eol,
                               model_grid, model_x_dim, model_y_dim, model_time_dim, utm_lon0,
                               tz_offset, obs_tz_offset, model_tz_offset, gmt_lag, model_shift_h, model_interp, obs_hour_label) {
  # Logs for the final report: warnings and discarded stations. Warnings are collected
  # (they do not appear at once) and written in full at the end, even if the script stops.
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
  # The ISTAT boundaries are required: if missing we stop at once, before reading
  # any heavy data.
  bnd <- read_istat_boundaries(istat_dir, if (is.null(istat_year)) year else istat_year)
  message("ISTAT boundaries: edition ", attr(bnd, "edition"))
  if (is.null(gmt_lag)) gmt_lag <- if (tz_offset == 0) "UTC" else sprintf("UTC%+g", tz_offset)
  # Hourly grid = wall-clock time in the tz_offset zone (whole year or `period`).
  grid_t <- if (is.null(period)) {
    seq(ISOdatetime(year, 1, 1, 0, 0, 0, tz = "UTC"),
        ISOdatetime(year, 12, 31, 23, 0, 0, tz = "UTC"), by = "hour")
  } else seq(period[1], period[2], by = "hour")

  if (!is.numeric(min_coverage) || length(min_coverage) != 1 || is.na(min_coverage) ||
      min_coverage < 0 || min_coverage > 1) {
    stop("min_coverage must be a number between 0 and 1 (e.g. 0.75 = at least 75% valid hours)")
  }
  pollutants <- check_pollutants(pollutants)
  if (!is.null(species)) {
    unk <- setdiff(species, pollutants$delta)
    if (length(unk)) {
      stop("Species not in the pollutants table: ", paste(unk, collapse = ", "),
           " (available: ", paste(pollutants$delta, collapse = ", "), ")")
    }
    pollutants <- pollutants[pollutants$delta %in% species, , drop = FALSE]   # table order
  }
  message("Species: ", paste(pollutants$delta, collapse = ", "))
  # Species without a variable in the NetCDF files cannot be validated, so they are dropped.
  have <- farm_varnames(farm_files(model_dir, model_pattern, model_version)[1])
  no_var <- !pollutants$farm %in% have
  if (any(no_var)) {
    warning("Variables missing in the NetCDF files, species dropped: ",
            paste(pollutants$delta[no_var], collapse = ", "))
    pollutants <- pollutants[!no_var, , drop = FALSE]
  }
  if (!nrow(pollutants)) {
    stop("No species has a variable in the NetCDF files. Variables present: ", paste(have, collapse = ", "),
         ". Set the `farm` column of the pollutants table to these names.")
  }

  meta <- read_eea_metadata(meta_csv, pollutants)
  nometa <- setdiff(pollutants$delta, meta$pol)
  if (length(nometa)) {
    warning("Species with no sampling point in the EEA metadata (check the name in `eea`): ",
            paste(nometa, collapse = ", "), call. = FALSE)
  }

  ## 1. Observations: one hourly series (tz_offset zone) per sampling point ----
  files <- list.files(obs_dir, pattern = obs_pattern, full.names = TRUE)
  if (!length(files)) stop("No observation files in ", obs_dir)
  parts <- list()
  recs <- list()       # one metadata record per observation sampling point
  skipped <- 0L
  nsel <- character()  # species present in the observations but not selected
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
        warning("Station not in the metadata, skipped: ", sp, " (", basename(f), ")", call. = FALSE)
        skipped <- skipped + 1L
        .disc[[length(.disc) + 1]] <- .disc_row(
          eoi = sub("^SP[OP]\\.([A-Za-z0-9]+)_.*$", "\\1", sp), element = basename(f), name = NA,
          lon = NA, lat = NA, muni = NA,
          reason = "EoI code not in DataExtract.csv")
        next
      }
      if (is.na(r$pol)) {
        nsel <- union(nsel, if (is.na(r$pol_eea)) paste0("code ", r$code) else r$pol_eea)
        skipped <- skipped + 1L
        next
      }
      if (r$how != "SPO") how[[sp]] <- r$how
      off <- if (is.null(obs_tz_offset)) r$tz_offset else obs_tz_offset
      if (is.na(off)) stop("Unrecognised EEA time zone for ", sp, ": set obs_tz_offset")
      prow <- pollutants[match(r$pol, pollutants$delta), ]
      if ("Unit" %in% names(d)) {
        f_u <- unit_factor(d$Unit, prow$unit, prow$obs_factor,
                           paste0("the observations of ", prow$delta, " (", basename(f), ")"))
        obs_units[[prow$delta]] <- union(obs_units[[prow$delta]], unique(as.character(d$Unit)))
      } else if (!is.na(prow$obs_factor)) {
        f_u <- prow$obs_factor
      } else {
        warning("Unit column missing in ", basename(f), ": no unit conversion (",
                prow$delta, "); set obs_factor if needed", call. = FALSE)
        f_u <- 1
      }
      obs_factors[[prow$delta]] <- f_u[1]
      s <- obs_to_hourly(d, off - tz_offset, valid_codes, f_u)   # from the EEA zone to tz_offset
      if (obs_hour_label == "end") s$time <- s$time + 3600       # the [Start, End) value goes to the end hour
      parts[[sp]] <- rbind(parts[[sp]], s)
      recs[[sp]] <- r
    }
  }
  if (length(nsel)) {
    message("Observations of non-selected species (ignored): ", paste(nsel, collapse = ", "))
  }
  if (length(how)) {
    message("Observation sampling points matched to the metadata without an exact SPO match: ")
    for (h in unique(how)) {
      message("  ", h, ": ", sum(how == h), " (e.g. ", names(how)[how == h][1], ")")
      warning(sum(how == h), " sampling points matched by '", h, "', e.g. ", names(how)[how == h][1],
              call. = FALSE)
    }
  }
  for (pn in names(obs_units)) {
    message("Observation units ", pn, ": ", paste(obs_units[[pn]], collapse = ", "), " -> ",
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
  message("Observations: ", length(files), " files, ", skipped, " skipped, ", sum(sp_tab$cov > 0),
          " sampling points with valid data in the period")
  sp_tab$frac <- sp_tab$cov / length(grid_t)
  nodata <- sp_tab[sp_tab$cov == 0, ]
  if (nrow(nodata)) {
    .disc[[length(.disc) + 1]] <- .disc_row(nodata$eoi, nodata$sp, nodata$name, nodata$lon, nodata$lat,
                                            nodata$muni, "no valid data in the requested period")
  }
  low <- sp_tab$cov > 0 & sp_tab$frac < min_coverage
  if (any(low)) {
    lw <- sp_tab[low, ]
    .disc[[length(.disc) + 1]] <- .disc_row(lw$eoi, lw$sp, lw$name, lw$lon, lw$lat, lw$muni,
      sprintf("coverage %.0f%% of valid hours, below the %.0f%% threshold (%s)", 100 * lw$frac,
              100 * min_coverage, lw$pol))
    message("Sampling points below the ", format(100 * min_coverage), "% coverage threshold: ", sum(low))
  }
  sp_tab <- sp_tab[sp_tab$cov > 0 & !low, ]
  if (!nrow(sp_tab)) stop("No valid observed data in the requested period")

  # Metadata values are left as they are, record by record (the same station may have
  # different coordinates, type or area across its sampling points). Only where a value is
  # missing the one from the other records of the same station is used (see fill_missing_by_station).
  filled <- character()
  for (cols in list(c("lon", "lat"), "alt", "area", "type")) {
    sp_tab <- fill_missing_by_station(sp_tab, cols)
    filled <- c(filled, attr(sp_tab, "filled"))
  }
  if (length(filled)) message("Missing metadata, filled in from the same ",
                              "station: ", paste(unique(filled), collapse = ", "))

  ## 2. One file per (station, position/type/area, level): letters a, b, c ... ----
  # The same EoI station is split into several files if its records have DIFFERENT
  # coordinates, type or area (values as in the DataExtract, after filling the missing data).
  # Within each (station, values, pollutant) the same pollutant from several sampling points
  # takes successive levels: the one with the most valid data first. The files of a station
  # are then ordered by level and, for ties, by total valid data.
  chr <- function(x) ifelse(is.na(x), "NA", as.character(x))
  sp_tab$key <- paste(chr(sp_tab$lon), chr(sp_tab$lat), chr(sp_tab$area), chr(sp_tab$type), sep = "|")
  sp_tab <- sp_tab[order(sp_tab$eoi, sp_tab$key, sp_tab$pol, -sp_tab$cov, sp_tab$sp), ]
  sp_tab$level <- stats::ave(seq_len(nrow(sp_tab)), sp_tab$eoi, sp_tab$key, sp_tab$pol, FUN = seq_along)
  sp_tab$slot <- paste(sp_tab$eoi, sp_tab$key, sp_tab$level, sep = "#")
  slots <- sp_tab[!duplicated(sp_tab$slot), c("eoi", "key", "level", "slot")]
  slots$tot <- as.numeric(tapply(sp_tab$cov, sp_tab$slot, sum)[slots$slot])
  slots <- slots[order(slots$eoi, slots$level, -slots$tot, slots$key), ]
  slots$n <- stats::ave(seq_len(nrow(slots)), slots$eoi, FUN = seq_along)
  if (max(slots$n) > 26) stop("More than 26 files for the same EoI station")
  sp_tab$id <- paste0(sp_tab$eoi, letters[slots$n[match(sp_tab$slot, slots$slot)]])
  nsplit <- sum(tapply(slots$n, slots$eoi, max) > 1)
  if (nsplit) message("EEA stations split into several files (different coordinates, type, area or sampling points): ", nsplit)

  ## 3. One file per id (station + letter): position, FARM cell, municipality -----------
  # The file takes the metadata of its first pollutant (in the order of the table); the
  # FARM cell and the municipality are those of THAT position, even if another letter
  # of the same station has different coordinates.
  ord_pol <- match(sp_tab$pol, pollutants$delta)
  sp_tab <- sp_tab[order(sp_tab$id, ord_pol), ]
  ft <- sp_tab[!duplicated(sp_tab$id), c("id", "eoi", "nat", "lon", "lat", "alt", "type", "area", "name", "muni")]
  nocoord <- is.na(ft$lon) | is.na(ft$lat)
  if (any(nocoord)) {
    warning("Files without coordinates in the metadata, dropped: ", paste(ft$id[nocoord], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[nocoord], ft$id[nocoord], ft$name[nocoord], NA, NA,
                                            ft$muni[nocoord], "coordinates missing in DataExtract.csv")
    ft <- ft[!nocoord, ]
  }
  if (!nrow(ft)) stop("No station with coordinates in the metadata")
  if (!obs_hour_label %in% c("start", "end")) stop("obs_hour_label must be \"start\" or \"end\"")
  if (!model_interp %in% c("nearest", "bilinear")) stop("model_interp must be \"nearest\" or \"bilinear\"")
  if (!model_grid %in% c("utm", "lonlat")) stop("model_grid must be \"utm\" or \"lonlat\"")
  g <- farm_grid(farm_files(model_dir, model_pattern, model_version)[1], model_x_dim, model_y_dim)
  if (model_grid == "utm") {
    utm <- lonlat_to_utm(ft$lon, ft$lat, lon0 = utm_lon0)
    cell <- nearest_cell(utm$x / 1000, utm$y / 1000, g$x, g$y)   # grid in km
  } else {
    cell <- nearest_cell(ft$lon, ft$lat, g$x, g$y)                # grid in degrees
  }
  outside <- is.na(cell$ix)
  if (any(outside)) {
    warning("Files outside the FARM grid, dropped: ", paste(ft$id[outside], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[outside], ft$id[outside], ft$name[outside], ft$lon[outside],
                                            ft$lat[outside], ft$muni[outside], "outside the model grid")
  }
  ft <- ft[!outside, ]
  ft$ix <- cell$ix[!outside]
  ft$iy <- cell$iy[!outside]
  if (!nrow(ft)) stop("No station inside the FARM grid")

  # Region and municipality from the ISTAT boundaries. Without them the startup cannot
  # be written, so files far from every municipality are dropped.
  geo <- istat_lookup(bnd, ft$lon, ft$lat, comune_col, region_col, istat_max_dist_m,
                      province_col, province_abbr_col)
  no_geo <- is.na(geo$comune) | is.na(geo$region)
  if (any(no_geo)) {
    warning("Files more than ", istat_max_dist_m, " m from any ISTAT municipality, dropped: ",
            paste(ft$id[no_geo], collapse = ", "))
    .disc[[length(.disc) + 1]] <- .disc_row(ft$eoi[no_geo], ft$id[no_geo], ft$name[no_geo], ft$lon[no_geo],
                                            ft$lat[no_geo], ft$muni[no_geo],
                                            paste0("more than ", istat_max_dist_m, " m from any ISTAT municipality"))
  }
  ft <- ft[!no_geo, ]
  ft$region <- geo$region[!no_geo]
  ft$comune <- geo$comune[!no_geo]
  if (!nrow(ft)) stop("No station with an ISTAT municipality and region")
  sp_tab <- sp_tab[sp_tab$id %in% ft$id, ]

  ## 4. Model in the station cells -----------------------------------------------
  used <- intersect(pollutants$delta, unique(sp_tab$pol))
  # Cells and weights for the remaining stations (same grid and coordinates as the match above).
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
    message("Model units ", pn, " (", pollutants$farm[match(pn, pollutants$delta)], "): ",
            paste(mod$units[[pn]], collapse = ", "), " -> ", pollutants$unit[match(pn, pollutants$delta)],
            if (!is.na(mod$factors[[pn]]) && mod$factors[[pn]] != 1) paste0(" (x", format(mod$factors[[pn]], digits = 6), ")") else "")
  }
  # The NetCDF files are in the model_tz_offset zone: bring them to tz_offset like the observations.
  mod_t <- mod$time + (tz_offset - model_tz_offset) * 3600
  mi <- match(as.numeric(grid_t + model_shift_h * 3600), as.numeric(mod_t))
  if (all(is.na(mi))) stop("The model does not cover the requested period")
  if (anyNA(mi)) {
    nm <- grid_t[is.na(mi)]
    warning(sum(is.na(mi)), " of ", length(mi), " hours without model data: written as -999 (",
            paste(format(utils::head(nm, 8), "%Y-%m-%d %H:00"), collapse = ", "),
            if (length(nm) > 8) ", ..." else "", ")", call. = FALSE)
  }

  ## 5. Writing -----------------------------------------------------------------
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
      id = id, code = paste0(gsub("[^A-Za-z0-9]", "", m$nat), substr(id, nchar(id), nchar(id))),   # letters and digits only
      alt = ifelse(is.na(m$alt), 0, m$alt), lon = m$lon, lat = m$lat,
      region = clean_name(m$region), type = m$type, area = m$area,
      siting = clean_name(m$comune),
      vars = paste(sel$pol, collapse = "*"), eoi = m$eoi, stringsAsFactors = FALSE)
  }
  st <- do.call(rbind, stations)
  # Station Code, Station Name and Station abbreviation must be UNIQUE. Name and abbreviation
  # are the id (EoI code + letter), unique by construction. The code is "<Nat Code><letter>",
  # but the same Nat Code may be in several EoI stations: in that case the EoI is appended.
  dupc <- st$code %in% st$code[duplicated(st$code)]
  if (any(dupc)) {
    warning("Duplicate Station Code (same Nat Code in different EoI stations), EoI appended: ",
            paste(unique(st$code[dupc]), collapse = ", "), call. = FALSE)
    st$code[dupc] <- paste0(st$code[dupc], st$eoi[dupc])
  }
  if (anyDuplicated(st$code) || anyDuplicated(st$id) || anyDuplicated(tolower(st$id))) {
    stop("Station Code, Station Name or Station abbreviation are not unique: ",
         paste(unique(c(st$code[duplicated(st$code)], st$id[duplicated(tolower(st$id))])), collapse = ", "))
  }
  # [PARAMETERS] lists only the species that actually have data in at least one file.
  noobs <- setdiff(pollutants$delta, sp_tab$pol)
  if (length(noobs)) message("Species without observations (not written to the startup): ", paste(noobs, collapse = ", "))
  pollutants <- pollutants[pollutants$delta %in% sp_tab$pol, , drop = FALSE]
  write_startup(st, file.path(out_dir, startup_name), year, pollutants, gmt_lag, scale, eol)
  message("Done: ", nrow(st), " station files (", length(unique(st$eoi)), " EEA stations) for ",
          length(grid_t), " hours, species: ", paste(pollutants$delta, collapse = ", "))
  list(stations = st, sampling_points = sp_tab, out_dir = out_dir)
  }, warning = function(w) {
    .wlog <<- c(.wlog, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  # Report files: full warnings and discarded stations (with municipality and province).
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
