# Municipality and region of each station from the ISTAT administrative boundaries.
# The ISTAT boundaries are REQUIRED and go in a dedicated folder
# (e.g. data/istat/). ISTAT publishes one edition per year (Limiti01012023.zip,
# Limiti01012024.zip, ...): the folder may hold as many as you like, as zip files
# or as already extracted folders (Com01012023/, Reg01012023/, ...). The edition is
# recognised from the date in the layer name (Com01012023_WGS84.shp -> 2023).

# Edition year from a layer name: Com01012023_WGS84.shp -> 2023 (NA if absent).
.istat_edition <- function(shp_names) {
  b <- basename(shp_names)
  ifelse(grepl("^(ProvCM|Com|Reg)[0-9]{4}[0-9]{4}", b, ignore.case = TRUE),
         suppressWarnings(as.integer(sub("^(ProvCM|Com|Reg)[0-9]{4}([0-9]{4}).*$", "\\2", b,
                                         ignore.case = TRUE))),
         NA_integer_)
}

# Chooses the edition: that of `year` if present; otherwise the latest earlier one
# (or, if there are none, the oldest later one), with a warning.
.pick_edition <- function(editions, year, dir) {
  ed <- sort(unique(editions[!is.na(editions)]))
  if (!length(ed)) return(NA_integer_)
  if (is.null(year) || year %in% ed) return(if (is.null(year)) max(ed) else as.integer(year))
  chosen <- if (any(ed < year)) max(ed[ed < year]) else min(ed)
  warning("No ISTAT edition for ", year, " in '", dir, "' (available: ",
          paste(ed, collapse = ", "), "): using edition ", chosen, ".", call. = FALSE)
  chosen
}

# Reads from folder `dir` the municipality (Com*) and region (Reg*) layers of the ISTAT
# edition of year `year` (see .pick_edition). With year = NULL it uses the latest.
read_istat_boundaries <- function(dir, year) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("The 'sf' package is required to read the ISTAT boundaries: install.packages(\"sf\")")
  }
  if (is.null(dir) || !is.character(dir) || length(dir) != 1 || !dir.exists(dir)) {
    stop("The ISTAT boundaries folder (istat_dir) is required and must exist: ",
         if (is.character(dir) && length(dir) == 1) dir else "not given")
  }
  is_layer <- function(x, prefix) grepl(paste0("^", prefix, "[0-9]"), basename(x), ignore.case = TRUE)
  shp_ext <- list.files(dir, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE,
                        ignore.case = TRUE)
  shp_ext <- shp_ext[is_layer(shp_ext, "Com") | is_layer(shp_ext, "Reg") | is_layer(shp_ext, "ProvCM")]
  zips <- list.files(dir, pattern = "\\.zip$", full.names = TRUE, ignore.case = TRUE)
  if (!length(zips) && !length(shp_ext)) {
    stop("No ISTAT boundaries in '", dir, "': copy here the zip downloaded from ISTAT ",
         "(e.g. Limiti01012023.zip) or the already extracted folders.")
  }

  # List of the available layers (without extracting anything): source, name, edition.
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
    stop("The ISTAT boundaries in '", dir, "' lack the Com* (municipalities) and Reg* (regions) layers")
  }
  lay <- do.call(rbind, parts)
  lay$kind <- ifelse(is_layer(lay$path, "Com"), "Com", ifelse(is_layer(lay$path, "ProvCM"), "ProvCM", "Reg"))
  lay$edition <- .istat_edition(lay$path)

  # Only the editions that have both Com* and Reg*.
  full <- intersect(lay$edition[lay$kind == "Com"], lay$edition[lay$kind == "Reg"])
  full <- full[!is.na(full)]
  if (length(full)) {
    ed <- .pick_edition(full, year, dir)
    lay <- lay[!is.na(lay$edition) & lay$edition == ed, , drop = FALSE]
  } else {
    ed <- NA_integer_   # names without a date: use everything available
  }

  pick <- function(prefix) {
    s <- lay[lay$kind == prefix, , drop = FALSE]
    if (!nrow(s)) stop("The ISTAT boundaries in '", dir, "' lack the layer ", prefix,
                       "* (municipalities: Com*, regions: Reg*)")
    s <- s[order(s$path, decreasing = TRUE), , drop = FALSE][1, ]
    if (is.na(s$zip)) return(s$path)
    tmp <- tempfile("istat_")
    dir.create(tmp)
    utils::unzip(s$zip, exdir = tmp)
    file.path(tmp, s$path)
  }
  # The province layer (ProvCM*) is optional: it is only used to write the province
  # in the discarded-stations report.
  prov <- if (any(lay$kind == "ProvCM")) sf::st_read(pick("ProvCM"), quiet = TRUE) else NULL
  out <- list(com = sf::st_read(pick("Com"), quiet = TRUE),
              reg = sf::st_read(pick("Reg"), quiet = TRUE), prov = prov)
  attr(out, "edition") <- ed
  out
}

# Name of the municipality, of the region and (if the ProvCM layer exists) of the province for
# each lon/lat point (WGS84). Points with NA coordinates give NA.
# A point outside every polygon (e.g. on the coast) takes the nearest polygon
# if within `max_dist_m`; beyond that the result is NA.
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
      stop("Column '", col, "' missing in the ISTAT layer (columns present: ",
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
