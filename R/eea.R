# Reading the EEA metadata (DataExtract.csv) and the observations (E1a parquet).

# All the records of DataExtract.csv (one per Sampling Point Id + Process Id: the same
# SPO may appear with several SPP). No record is dropped: `pol` is the DELTA name
# if "Air Pollutant" is in the `eea` column of the `pollutants` table (see units.R),
# NA otherwise (species not selected); `pol_eea` is the original EEA name.
# `code`/`method`/`sp_eoi` are derived from "SPO.<EoI>_<code>_<method>_<date>".
read_eea_metadata <- function(csv, pollutants) {
  # The EEA CSV is UTF-8 (with a few characters already corrupted upstream): no
  # fileEncoding, which would make the read fail at the first invalid byte.
  raw <- utils::read.csv(csv, encoding = "UTF-8", colClasses = "character",
                         check.names = FALSE, na.strings = "")
  need <- c("Sampling Point Id", "Air Quality Station EoI Code",
            "Air Quality Station Nat Code", "Air Quality Station Name",
            "Air Pollutant", "Longitude", "Latitude", "Altitude",
            "Air Quality Station Area", "Air Quality Station Type", "Timezone")
  miss <- setdiff(need, names(raw))
  if (length(miss)) stop("Missing columns in the EEA CSV: ", paste(miss, collapse = ", "))

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
    area = tolower(raw[["Air Quality Station Area"]]),   # designation of the DataExtract (e.g. rural-nearcity)
    type = tolower(raw[["Air Quality Station Type"]]),
    tz_offset = tz_off,
    muni = if ("Municipality" %in% names(raw)) raw[["Municipality"]] else NA_character_,
    stringsAsFactors = FALSE
  )
}

# Looks up in the DataExtract the record of an observation sampling point
# ("SPO.<EoI>_<code>_<method>_<date>"). In order:
#   1. same SPO; 2. same SPP (Process Id); 3. same station, code and method
#      (the date or the method of the process may have changed); 4. same station and code;
#   5. station only: record built with the values of the other records of the station and
#      species taken from the code (see below).
# Several candidate rows: the one with fewer missing values, then the last in SPP order.
# Returns NULL if the station is not in the DataExtract, otherwise a row of `meta`
# with `sp` = the observation sampling point and `how` = the criterion used.
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
  if (length(i)) return(pick(i, "same station, code and method"))
  i <- which(st & meta$code %in% code)
  if (length(i)) return(pick(i, "same station and code"))
  i <- which(st)
  if (!length(i)) return(NULL)
  r <- pick(i, "station only")
  # species from the code, as in the rest of the DataExtract
  k <- which(meta$code %in% code)
  r$code <- code
  r$pol <- if (length(k)) meta$pol[k[1]] else NA_character_
  r$pol_eea <- if (length(k)) meta$pol_eea[k[1]] else NA_character_
  r
}

read_obs_file <- function(f) {
  if (grepl("\\.parquet$", f, ignore.case = TRUE)) {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("The 'arrow' package is required to read parquet files.")
    }
    as.data.frame(arrow::read_parquet(f))
  } else {
    utils::read.csv(f, stringsAsFactors = FALSE)  # CSV export with the same columns
  }
}

# Wall-clock time as POSIXct UTC. The number stored in the parquet IS the clock (no zone):
# if the object has no time zone (tzone NULL or ""), it must be read in UTC and NOT in the
# R session zone (e.g. TZ=Europe/Rome, which would add 1 hour in winter and 2 in summer); if it
# has an explicit zone, the clock is read in that zone.
.naive_utc <- function(x) {
  if (is.character(x)) return(as.POSIXct(x, tz = "UTC"))  # CSV export
  tz <- attr(x, "tzone")
  if (is.null(tz) || !nzchar(tz[1])) tz <- "UTC"
  as.POSIXct(format(x, "%Y-%m-%d %H:%M:%S", tz = tz[1]), tz = "UTC")
}

# Hourly UTC series from an EEA parquet.
#  - AggType "hour": the value goes to the start hour (Start).
#  - AggType "day" and "var": the value is constant over the whole interval
#    [Start, End) and is repeated on every hour of the interval, whatever its
#    length (day, week, ...: benzene, Pb, Cd, ...).
#  - Other AggType: ignored with a warning.
# Start/End are local station time (fixed zone, e.g. UTC+01): tz_offset is
# subtracted to get UTC.
obs_to_hourly <- function(d, tz_offset, valid_codes, factor) {
  start <- .naive_utc(d$Start)
  end <- .naive_utc(d$End)
  val <- as.numeric(d$Value)
  ok <- !is.na(val) & val > -900 & d$Validity %in% valid_codes
  val <- val * factor   # unit conversion (after excluding -9999); factor: scalar or per row
  agg <- tolower(d$AggType)
  other <- setdiff(unique(agg), c("hour", "day", "var"))
  if (length(other)) warning("AggType not handled, ignored: ", paste(other, collapse = ", "))

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

# EEA metadata values are left as they are, record by record (the same station
# may have different coordinates, type or area across its sampling points, and the startup
# reports them as such). ONLY where a value is missing (NA) the value of the other records of
# the same station (EoI) is used: for each group of columns `cols` (together, e.g. lon+lat),
# the one supported by the most hours of valid data (sum of `cov`); for ties the first in
# alphabetical order. A record with all values present is never touched.
# `tab` must have `eoi` and `cov`. Returns the table and (attribute "filled") the EoIs touched.
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
