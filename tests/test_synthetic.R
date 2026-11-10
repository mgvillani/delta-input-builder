# Test with entirely synthetic data (no real data).
# Usage, from the repository root:  Rscript tests/test_synthetic.R
for (f in list.files("R", full.names = TRUE)) source(f)
stopifnot(requireNamespace("ncdf4", quietly = TRUE), requireNamespace("sf", quietly = TRUE))

## --- Name cleaning ---------------------------------------------------------------
# The accented letters are built with intToUtf8 (strings marked UTF-8 in any locale,
# like those read by sf or by read.csv(encoding = "UTF-8")).
e_acc <- intToUtf8(0xE9); i_acc <- intToUtf8(0xEC); a_acc <- intToUtf8(0xE0)
stopifnot(identical(
  clean_name(c(paste0("Agli", e_acc), "Albiano d'Ivrea", "Borgaro Torinese", "Reggio nell'Emilia",
               paste0("Valle d'Aosta/Vall", e_acc, "e d'Aoste"), paste0("Forl", i_acc),
               "Sant'Angelo-Lodigiano", NA, "")),
  c("Aglie", "Albiano d'Ivrea", "Borgaro Torinese", "Reggio nell'Emilia",
    "Valle d'Aosta/Vallee d'Aoste", "Forli", "Sant'Angelo-Lodigiano", "NA", "NA")))
stopifnot(identical(clean_name(c("A;B*C_D", "  x   y ")), c("A B C D", "x y")))

# Optional: a folder where to KEEP the synthetic data and outputs (otherwise a temporary folder,
# deleted when R closes). Example:  Rscript tests/test_synthetic.R test_output
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && nzchar(args[1])) {
  tmp <- normalizePath(args[1], mustWork = FALSE)
  if (dir.exists(tmp) && length(list.files(tmp))) stop("The folder ", tmp, " is not empty: give a new or empty one.")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  keep <- TRUE
} else {
  tmp <- tempfile("delta_test_"); dir.create(tmp)
  keep <- FALSE
}
mdir <- file.path(tmp, "farm"); odir <- file.path(tmp, "obs"); dir.create(mdir); dir.create(odir)

## --- Model: 4 km grid around lon 9 / lat 45 (UTM easting 500 km, northing ~4983 km)
## The NetCDF times are in UTC+1: file 1 = 00..24 local of 1/1, file 2 = 00..24 of 2/1.
gx <- seq(496, 508, by = 4); gy <- seq(4980, 4992, by = 4)
make_nc <- function(path, t0, val_first) {
  tm <- t0 + 0:24
  dx <- ncdf4::ncdim_def("x", "km", gx); dy <- ncdf4::ncdim_def("y", "km", gy)
  dz <- ncdf4::ncdim_def("z", "", 20)
  dt <- ncdf4::ncdim_def("time", "hours since 1900-1-1 00:00:0.0", tm)
  vars <- lapply(c("c_NO2", "c_PM10"), function(n) ncdf4::ncvar_def(n, "ug/m3", list(dx, dy, dz, dt), -9.96921e36))
  nc <- ncdf4::nc_create(path, vars)
  v <- array(rep(10 + (0:24), each = length(gx) * length(gy)), c(length(gx), length(gy), 1, 25))
  v[, , , 1] <- val_first                      # the first step of each file is marked
  for (n in c("c_NO2", "c_PM10")) ncdf4::ncvar_put(nc, n, v)
  ncdf4::nc_close(nc)
}
make_nc(file.path(mdir, "FARM_conc_g2_20230101_D1.nc"), 1078200, 111)
make_nc(file.path(mdir, "FARM_conc_g2_20230102_D1.nc"), 1078224, 222)

## --- EEA metadata: station A (inside the grid) with NO2 + two PM10; station B outside the grid
sp <- c("SPO.IT9001A_8_chemi_2000-01-01_00:00:00", "SPO.IT9001A_5_BETA_2000-01-01_00:00:00",
        "SPO.IT9001A_5_GRAV_2000-01-01_00:00:00", "SPO.IT9002A_8_chemi_2000-01-01_00:00:00")
meta_cols <- c("Sampling Point Id", "Air Quality Station EoI Code", "Air Quality Station Nat Code",
               "Air Quality Station Name", "Air Pollutant", "Longitude", "Latitude", "Altitude",
               "Air Quality Station Area", "Air Quality Station Type", "Municipality",
               "Air Quality Network", "Timezone")
meta <- data.frame(sp, c("IT9001A", "IT9001A", "IT9001A", "IT9002A"),
                   c("7001", "7001", "7001", "7002"), "TEST", c("NO2", "PM10", "PM10", "NO2"),
                   c("9.0", "9.0", "9.0", "12.0"), "45.0", "100", "rural-nearcity", "traffic",
                   "VIA ROMA - Torino (TO)", "NET.IT001A", "UTC+01", stringsAsFactors = FALSE)
names(meta) <- meta_cols
utils::write.csv(meta, file.path(tmp, "meta.csv"), row.names = FALSE)

## --- Observations (local time UTC+01, as EEA)
write_obs <- function(spid, start, end, value, agg) {
  d <- data.frame(Samplingpoint = paste0("IT/", spid), Pollutant = 0,
                  Start = format(start, "%Y-%m-%d %H:%M:%S"), End = format(end, "%Y-%m-%d %H:%M:%S"),
                  Value = value, Unit = "ug.m-3", AggType = agg, Validity = 1L, Verification = 1L,
                  stringsAsFactors = FALSE)
  utils::write.csv(d, file.path(odir, paste0(gsub("[^A-Za-z0-9]", "_", spid), ".csv")), row.names = FALSE)
}
L0 <- as.POSIXct("2023-01-01 00:00:00", tz = "UTC")
h <- L0 + 3600 * (1:48)                                  # 01:00 local 1/1 ... 00:00 local 3/1
write_obs(sp[1], h, h + 3600, 1:48, "hour")              # hourly NO2: value = index
write_obs(sp[2], L0 + 86400 * 0:1, L0 + 86400 * 1:2, c(30, 40), "day")   # PM10 BETA, 2 days
write_obs(sp[3], L0, L0 + 36 * 3600, 35, "var")                          # PM10 GRAV, "var": 36 hours
write_obs(sp[4], h, h + 3600, 1:48, "hour")              # station outside the grid

## --- Synthetic ISTAT boundaries (Com*/Reg* layers, UTM 32N), names with accent, apostrophe and spaces
istat_dir <- file.path(tmp, "istat"); dir.create(istat_dir)
box <- function(e, n, r) sf::st_polygon(list(matrix(c(e - r, n - r, e + r, n - r, e + r, n + r,
                                                      e - r, n + r, e - r, n - r), ncol = 2, byrow = TRUE)))
sf::st_write(sf::st_sf(COMUNE = paste0("Citt", a_acc, " d'Esempio"), geometry = sf::st_sfc(box(5e5, 4983e3, 8e3), crs = 32632)),
             file.path(istat_dir, "Com01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_REG = "Regione di Prova/Test", geometry = sf::st_sfc(box(5e5, 4983e3, 5e4), crs = 32632)),
             file.path(istat_dir, "Reg01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_UTS = "Provincia di Prova", SIGLA = "PP", geometry = sf::st_sfc(box(5e5, 4983e3, 3e4), crs = 32632)),
             file.path(istat_dir, "ProvCM01012023_WGS84.shp"), quiet = TRUE)

# Base parameters (no default values in the code: all are given); each case overrides some.
pollutants <- data.frame(delta = c("NO2", "O3", "PM10", "PM25"), eea = c("NO2", "O3", "PM10", "PM2.5"),
                         farm = c("c_NO2", "c_O3", "c_PM10", "c_PM25"), type = c("GAS", "GAS", "PM", "PM"),
                         unit = "ugm-3", stringsAsFactors = FALSE)
base_args <- list(
  obs_dir = odir, obs_pattern = "\\.csv$", meta_csv = file.path(tmp, "meta.csv"),
  model_dir = mdir, model_pattern = "^FARM_conc_.*\\.nc$", model_version = NULL,
  istat_dir = istat_dir, istat_year = NULL, istat_max_dist_m = 2000,
  comune_col = "COMUNE", region_col = "DEN_REG", province_col = "DEN_UTS", province_abbr_col = "SIGLA",
  pollutants = pollutants, species = NULL,
  out_dir = NULL, out_label = "", startup_name = "startup.ini", discarded_name = "discarded_stations.csv", warnings_name = "warnings.txt", year = 2023,
  period = c(as.POSIXct("2023-01-01 00:00", tz = "UTC"), as.POSIXct("2023-01-02 23:00", tz = "UTC")),
  scale = "urban", valid_codes = 1L, min_coverage = 0, eol = "\n",
  model_grid = "utm", model_x_dim = "x", model_y_dim = "y", model_time_dim = "time", utm_lon0 = 9,
  tz_offset = 1, obs_tz_offset = NULL, model_tz_offset = 1, gmt_lag = NULL, model_shift_h = 0, model_interp = "nearest", obs_hour_label = "start")
bd <- function(...) {                       # overrides the given parameters (also with NULL)
  ov <- list(...); a <- base_args
  for (n in names(ov)) a[n] <- list(ov[[n]])
  do.call(build_delta_inputs, a)
}
run <- function(name, istat = istat_dir, ...) {
  out <- file.path(tmp, name)
  suppressWarnings(bd(istat_dir = istat, out_dir = out, ...))
  out
}
msgs_of <- function(expr) {                 # all the screen messages (including the final report)
  m <- character()
  withCallingHandlers(try(expr, silent = TRUE), message = function(x) { m <<- c(m, conditionMessage(x)); invokeRestart("muffleMessage") })
  paste(m, collapse = "\n")
}
rd <- function(out, kind, id) utils::read.csv(file.path(out, kind, paste0(id, ".csv")), sep = ";")
last2 <- function(out) { ini <- readLines(file.path(out, "startup.ini")); ini[length(ini) - 1:0] }

## === A. Output in UTC (tz_offset = 0)
out <- run("out_utc", tz_offset = 0)
stopifnot(setequal(list.files(file.path(out, "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))  # a / b, B dropped
stopifnot(identical(list.files(file.path(out, "obs")), list.files(file.path(out, "mod"))))
oa <- rd(out, "obs", "IT9001Aa"); ob <- rd(out, "obs", "IT9001Ab"); ma <- rd(out, "mod", "IT9001Aa")
stopifnot(identical(names(oa), c("year", "month", "day", "hour", "NO2", "PM10")),
          identical(names(ob), c("year", "month", "day", "hour", "PM10")), nrow(oa) == 48)
# the first UTC hour is 01:00 local -> NO2 = 1; the daily PM10 is repeated; 00 local 2/1 = 23 UTC
stopifnot(oa$NO2[1] == 1, oa$NO2[48] == 48, all(oa$PM10[1:23] == 30), oa$PM10[24] == 40)
stopifnot(all(ob$PM10[1:35] == 35), ob$PM10[36] == -999)         # "var" 36 hours = 35 hours in the window
# model: row r (UTC hour r-1) = local hour r; 00 local of 2/1 = row 24 from the most recent file (222)
stopifnot(nrow(ma) == 48, ma$NO2[1] == 11, ma$PM10[2] == 12, ma$NO2[24] == 222, ma$NO2[25] == 11, ma$NO2[48] == 34)
stopifnot(identical(last2(out), c("7001a;IT9001Aa;IT9001Aa;100;9;45;UTC;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;NO2*PM10",
                                  "7001b;IT9001Ab;IT9001Ab;100;9;45;UTC;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;PM10")))

## === B. Default (tz_offset = 1): no offset
out <- run("out_local")
oa <- rd(out, "obs", "IT9001Aa"); ob <- rd(out, "obs", "IT9001Ab"); ma <- rd(out, "mod", "IT9001Aa")
stopifnot(oa$NO2[1] == -999, oa$NO2[2] == 1, oa$NO2[48] == 47)  # row r is local hour r-1
stopifnot(all(oa$PM10[1:24] == 30), all(oa$PM10[25:48] == 40))
stopifnot(all(ob$PM10[1:36] == 35), ob$PM10[37] == -999)
stopifnot(ma$NO2[1] == 111, ma$NO2[2] == 11, ma$NO2[24] == 33, ma$NO2[25] == 222, ma$NO2[26] == 11, ma$NO2[48] == 33)
stopifnot(identical(last2(out), c("7001a;IT9001Aa;IT9001Aa;100;9;45;UTC+1;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;NO2*PM10",
                                  "7001b;IT9001Ab;IT9001Ab;100;9;45;UTC+1;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;PM10")))
## === C. The ISTAT boundaries are required and live in a dedicated folder
err <- function(expr) tryCatch({ expr; "no error" }, error = function(e) conditionMessage(e))
stopifnot(grepl("required", err(run("c1", istat = NULL))))                       # not given
stopifnot(grepl("required", err(run("c2", istat = file.path(tmp, "does_not_exist")))))  # nonexistent folder
empty <- file.path(tmp, "istat_empty"); dir.create(empty)
stopifnot(grepl("No ISTAT boundaries", err(run("c3", istat = empty))))               # folder without data
# folder with the ISTAT zip inside (as downloaded from ISTAT)
if (nzchar(Sys.which("zip"))) {
  zdir <- file.path(tmp, "istat_zip"); dir.create(zdir)
  old <- setwd(istat_dir)
  utils::zip(file.path(zdir, "Limiti01012023.zip"), list.files("."), flags = "-q")
  setwd(old)
  out <- run("out_zip", istat = zdir)
  stopifnot(identical(last2(out), last2(file.path(tmp, "out_local"))))
} else message("(zip not available: zip folder test skipped)")
# several ISTAT editions in the same folder (one per year, as zip): the one of the year is used
if (nzchar(Sys.which("zip"))) {
  mdir_i <- file.path(tmp, "istat_multi"); dir.create(mdir_i)
  mk_ed <- function(yr, name) {
    d <- file.path(tmp, paste0("ed", yr)); dir.create(d)
    sf::st_write(sf::st_sf(COMUNE = name, geometry = sf::st_sfc(box(5e5, 4983e3, 8e3), crs = 32632)),
                 file.path(d, paste0("Com0101", yr, "_WGS84.shp")), quiet = TRUE)
    sf::st_write(sf::st_sf(DEN_REG = "Reg", geometry = sf::st_sfc(box(5e5, 4983e3, 5e4), crs = 32632)),
                 file.path(d, paste0("Reg0101", yr, "_WGS84.shp")), quiet = TRUE)
    old <- setwd(d); on.exit(setwd(old))
    utils::zip(file.path(mdir_i, paste0("Limiti0101", yr, ".zip")), list.files("."), flags = "-q")
  }
  mk_ed(2023, "Comune2023"); mk_ed(2025, "Comune2025")
  siting <- function(out) strsplit(last2(out)[1], ";")[[1]][11]
  stopifnot(siting(run("m1", istat = mdir_i)) == "Comune2023")                      # year = 2023
  stopifnot(siting(run("m2", istat = mdir_i, istat_year = 2025)) == "Comune2025")   # explicit
  bnd_ed <- function(y) attr(read_istat_boundaries(mdir_i, y), "edition")
  stopifnot(identical(bnd_ed(2023), 2023L), identical(bnd_ed(2025), 2025L), identical(bnd_ed(NULL), 2025L))
  w <- character()
  withCallingHandlers(ed <- bnd_ed(2024), warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  stopifnot(ed == 2023L, any(grepl("No ISTAT edition for 2024", w)))         # falls back to the previous one
  suppressWarnings(stopifnot(bnd_ed(2020) == 2023L))                                # none earlier: the oldest
}
# model version/pattern: two runs (g2 and g3) in the same folder, chosen with model_version
mdir2 <- file.path(tmp, "farm2"); dir.create(mdir2)
file.copy(list.files(mdir, full.names = TRUE), mdir2)
for (f in list.files(mdir2, full.names = TRUE)) file.rename(f, sub("_g2_", "_g3_", f))
make_nc(file.path(mdir2, "FARM_conc_g2_20230101_D1.nc"), 1078200, 555)
make_nc(file.path(mdir2, "FARM_conc_g2_20230102_D1.nc"), 1078224, 666)
runv <- function(name, ...) {
  out <- file.path(tmp, name)
  suppressWarnings(bd(model_dir = mdir2, out_dir = out, ...))
  out
}
stopifnot(rd(runv("v_g2", model_version = "g2"), "mod", "IT9001Aa")$NO2[1] == 555)   # run g2
stopifnot(rd(runv("v_g3", model_version = "g3"), "mod", "IT9001Aa")$NO2[1] == 111)   # run g3
stopifnot(rd(runv("v_pat", model_pattern = "^FARM_conc_g3_.*_D1\\.nc$"), "mod", "IT9001Aa")$NO2[1] == 111)
stopifnot(grepl("version 'g9'", err(runv("v_none", model_version = "g9"))))
# station without coordinates in the metadata: dropped with a warning, the rest goes on
m2 <- meta; m2[["Longitude"]][4] <- NA; m2[["Latitude"]][4] <- NA
utils::write.csv(m2, file.path(tmp, "meta_nocoord.csv"), row.names = FALSE)
rn <- bd(meta_csv = file.path(tmp, "meta_nocoord.csv"), out_dir = file.path(tmp, "nc1")); w <- rn$warnings
stopifnot(any(grepl("without coordinates in the metadata, dropped: IT9002Aa", w)),
          setequal(list.files(file.path(tmp, "nc1", "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))
# different values between the records of the same station: they stay as in the file, per file (a / b)
m3 <- meta
m3[["Longitude"]][3] <- "9.0002"; m3[["Latitude"]][3] <- "45.0002"
m3[["Air Quality Station Type"]][3] <- "background"; m3[["Air Quality Station Area"]][3] <- "urban"
utils::write.csv(m3, file.path(tmp, "meta_disc.csv"), row.names = FALSE)
o3 <- file.path(tmp, "disc"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_disc.csv"), out_dir = o3))
l3 <- last2(o3)
stopifnot(grepl("^7001a;IT9001Aa;IT9001Aa;100;9;45;UTC\\+1;.*;traffic;rural-nearcity;", l3[1]),
          grepl("^7001b;IT9001Ab;IT9001Ab;100;9.0002;45.0002;UTC\\+1;.*;background;urban;", l3[2]))
# missing value: only then the value of the same station is used (here: altitude, type, area, lon/lat of record 3 empty)
m4 <- meta
m4[["Longitude"]][3] <- NA; m4[["Latitude"]][3] <- NA; m4[["Altitude"]][3] <- NA
m4[["Air Quality Station Type"]][3] <- NA; m4[["Air Quality Station Area"]][3] <- NA
utils::write.csv(m4, file.path(tmp, "meta_na.csv"), row.names = FALSE, na = "")
w <- character(); msgs <- character()
o4 <- file.path(tmp, "na_fill")
withCallingHandlers(bd(meta_csv = file.path(tmp, "meta_na.csv"), out_dir = o4),
  message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") },
  warning = function(x) invokeRestart("muffleWarning"))
stopifnot(grepl("Missing metadata, filled in from the same station: IT9001A", paste(msgs, collapse = "")),
          grepl("^7001b;IT9001Ab;IT9001Ab;100;9;45;UTC\\+1;.*;traffic;rural-nearcity;", last2(o4)[2]))
# same station with a different type per pollutant: separate files (a = PM10 traffic, the most covered; b = NO2 industrial; c = second PM10)
m5 <- meta; m5[["Air Quality Station Type"]][1] <- "industrial"
utils::write.csv(m5, file.path(tmp, "meta_type.csv"), row.names = FALSE)
o5 <- file.path(tmp, "typesplit"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_type.csv"), out_dir = o5))
l5 <- readLines(file.path(o5, "startup.ini")); l5 <- l5[grepl("^7001", l5)]
stopifnot(length(l5) == 3,
          grepl("^7001a;IT9001Aa;.*;traffic;rural-nearcity;.*;PM10$", l5[1]),
          grepl("^7001b;IT9001Ab;.*;industrial;rural-nearcity;.*;NO2$", l5[2]),
          grepl("^7001c;IT9001Ac;.*;traffic;rural-nearcity;.*;PM10$", l5[3]))
# coverage threshold: GRAV has 36 hours out of 48 (75%)
r75 <- bd(min_coverage = 0.75, out_dir = file.path(tmp, "cov75"))
stopifnot(setequal(list.files(file.path(tmp, "cov75", "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))
r80 <- bd(min_coverage = 0.8, out_dir = file.path(tmp, "cov80"))
stopifnot(identical(list.files(file.path(tmp, "cov80", "obs")), "IT9001Aa.csv"),
          any(grepl("below the 80% threshold", r80$discarded$reason)) || any(grepl("below the 80% threshold", unlist(r80$discarded))))
stopifnot(grepl("min_coverage", err(bd(min_coverage = 1.5, out_dir = file.path(tmp, "cov_bad")))))
# validity codes: NO2 with Validity 1 on half of the hours and 2 on the other half
vd <- file.path(tmp, "vobs"); dir.create(vd)
dv <- utils::read.csv(file.path(odir, list.files(odir)[grepl("IT9001A_8", list.files(odir))][1]))
dv$Validity <- rep(c(1L, 2L), length.out = nrow(dv))
utils::write.csv(dv, file.path(vd, "no2.csv"), row.names = FALSE)
for (f in list.files(odir)[!grepl("IT9001A_8", list.files(odir))]) file.copy(file.path(odir, f), vd)
c1 <- suppressWarnings(bd(obs_dir = vd, valid_codes = 1L, out_dir = file.path(tmp, "vc1")))
c123 <- suppressWarnings(bd(obs_dir = vd, valid_codes = c(1L, 2L, 3L), out_dir = file.path(tmp, "vc123")))
n1 <- sum(rd(file.path(tmp, "vc1"), "obs", "IT9001Aa")$NO2 != -999)
n3 <- sum(rd(file.path(tmp, "vc123"), "obs", "IT9001Aa")$NO2 != -999)
stopifnot(n3 == 2 * n1 || n3 == 2 * n1 - 1 || n3 == 2 * n1 + 1, n3 > n1)
# observation hour label: "end" shifts by +1 h with respect to "start"
oS <- file.path(tmp, "lab_start"); oE <- file.path(tmp, "lab_end")
suppressWarnings(bd(out_dir = oS, obs_hour_label = "start")); suppressWarnings(bd(out_dir = oE, obs_hour_label = "end"))
no_s <- rd(oS, "obs", "IT9001Aa")$NO2; no_e <- rd(oE, "obs", "IT9001Aa")$NO2
stopifnot(identical(no_e[-1][!is.na(no_s[-length(no_s)])], no_s[-length(no_s)][!is.na(no_s[-length(no_s)])]) || all(no_e[-1] == no_s[-length(no_s)]))
stopifnot(grepl("obs_hour_label", err(bd(obs_hour_label = "mid", out_dir = file.path(tmp, "lab_bad")))))
# all the decimals of altitude, lon and lat
m6 <- meta; m6[["Longitude"]][1:3] <- "9.012345"; m6[["Latitude"]][1:3] <- "45.000123"; m6[["Altitude"]][1:3] <- "12.5"
utils::write.csv(m6, file.path(tmp, "meta_dec.csv"), row.names = FALSE)
o6 <- file.path(tmp, "dec"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_dec.csv"), out_dir = o6))
stopifnot(grepl("^7001a;IT9001Aa;IT9001Aa;12.5;9.012345;45.000123;", last2(o6)[1]))
# model on a lon/lat grid (dimensions time, decreasing lat, lon; time in seconds; own variable names)
ldir <- file.path(tmp, "lonlat"); dir.create(ldir)
glon <- seq(8.5, 9.5, by = 0.25); glat <- seq(45.5, 44.5, by = -0.25)         # 9.0 -> index 3; 45.0 -> index 3
dlon <- ncdf4::ncdim_def("lon", "degrees_east", glon); dlat <- ncdf4::ncdim_def("lat", "degrees_north", glat)
dtm <- ncdf4::ncdim_def("time", "seconds since 2023-01-01 00:00:00", 3600 * (0:47))
vl <- lapply(c("NO2", "PM10"), function(n) ncdf4::ncvar_def(n, "ug/m3", list(dtm, dlat, dlon), -999))  # order time,lat,lon
ncl <- ncdf4::nc_create(file.path(ldir, "conc_IT0_20230101.nc"), vl)
arr <- array(0, c(48, length(glat), length(glon)))
for (t in 1:48) for (la in seq_along(glat)) for (lo in seq_along(glon)) arr[t, la, lo] <- 1000 * la + 100 * lo + (t - 1)
for (n in c("NO2", "PM10")) ncdf4::ncvar_put(ncl, n, arr)
ncdf4::nc_close(ncl)
pol_ll <- pollutants; pol_ll$farm <- c("NO2", "O3", "PM10", "PM25")
ol <- file.path(tmp, "out_ll")
suppressWarnings(bd(model_dir = ldir, model_pattern = "^conc_.*\\.nc$", model_grid = "lonlat",
                    model_x_dim = "lon", model_y_dim = "lat", pollutants = pol_ll, out_dir = ol))
mll <- rd(ol, "mod", "IT9001Aa")
stopifnot(nrow(mll) == 48, mll$NO2[1] == 3300, mll$NO2[48] == 3347, mll$PM10[2] == 3301)
# bilinear interpolation: linear field 1000*la + 100*lo -> at (lon 9.05, lat 45.05) it is 3120 (nearest would give 3300)
m7 <- meta; m7[["Longitude"]][1:3] <- "9.05"; m7[["Latitude"]][1:3] <- "45.05"
utils::write.csv(m7, file.path(tmp, "meta_bil.csv"), row.names = FALSE)
ob <- file.path(tmp, "out_bil")
suppressWarnings(bd(meta_csv = file.path(tmp, "meta_bil.csv"), model_dir = ldir, model_pattern = "^conc_.*\\.nc$", model_grid = "lonlat",
                    model_x_dim = "lon", model_y_dim = "lat", pollutants = pol_ll, model_interp = "bilinear", out_dir = ob))
mb <- rd(ob, "mod", "IT9001Aa")
stopifnot(abs(mb$NO2[1] - 3120) < 1e-6, abs(mb$NO2[48] - 3167) < 1e-6)
on <- file.path(tmp, "out_nea")
suppressWarnings(bd(meta_csv = file.path(tmp, "meta_bil.csv"), model_dir = ldir, model_pattern = "^conc_.*\\.nc$", model_grid = "lonlat",
                    model_x_dim = "lon", model_y_dim = "lat", pollutants = pol_ll, model_interp = "nearest", out_dir = on))
stopifnot(rd(on, "mod", "IT9001Aa")$NO2[1] == 3300)
stopifnot(grepl("model_interp", err(bd(model_interp = "cubic", out_dir = file.path(tmp, "interp_bad")))))
ic <- interp_cells(c(9.05), c(45.05), glon, glat, "bilinear")        # decreasing lat
stopifnot(ic$ix0 == 3, ic$ix1 == 4, abs(ic$wx - 0.2) < 1e-9, ic$iy0 == 3, ic$iy1 == 2, abs(ic$wy - 0.2) < 1e-9)
stopifnot(grepl("Variables present: NO2, PM10", err(bd(model_dir = ldir, model_pattern = "^conc_.*\\.nc$", out_dir = file.path(tmp, "ll_err1")))))  # wrong variable names
stopifnot(grepl("dimensions present: time, lat, lon", err(bd(model_dir = ldir, model_pattern = "^conc_.*\\.nc$", pollutants = pol_ll,
                                                           model_grid = "utm", out_dir = file.path(tmp, "ll_err2")))))   # nonexistent x,y dimensions
# automatic output subfolder: year, model version, period
oa <- file.path(tmp, "lab"); r1 <- suppressWarnings(bd(model_dir = mdir2, model_version = "g2", out_dir = oa, out_label = NULL))
stopifnot(basename(r1$out_dir) == "2023_g2_20230101-20230102", file.exists(file.path(r1$out_dir, "startup.ini")))
r2 <- suppressWarnings(bd(period = NULL, out_dir = oa, out_label = NULL))
stopifnot(basename(r2$out_dir) == "2023", file.exists(file.path(oa, "2023", "startup.ini")))
r3 <- suppressWarnings(bd(out_dir = oa, out_label = "my_run"))
stopifnot(basename(r3$out_dir) == "my_run")
# two versions mixed in the same folder: warning
w <- bd(model_dir = mdir2, out_dir = file.path(tmp, "mix"))$warnings
stopifnot(any(grepl("several model versions", w)))
# --- units of measure -------------------------------------------------------------------
stopifnot(identical(.mass_per_unit(c("ug/m3", "ug.m-3", "mg m-3", "ugm-3", paste0(intToUtf8(181), "g/m3"), "ng/m3", "ppb", NA)),
                    c(1e-6, 1e-6, 1e-3, 1e-6, 1e-6, 1e-9, NA, NA)))
stopifnot(all.equal(unit_factor(c("mg.m-3", "ng.m-3"), "ugm-3", NA, "x"), c(1000, 0.001)))
stopifnot(unit_factor("ppb", "ugm-3", 1.88, "x") == 1.88)                           # manual factor
stopifnot(grepl("ppb", tryCatch(unit_factor("ppb", "ugm-3", NA, "x"), error = function(e) conditionMessage(e))))
# NO2 observations in mg.m-3: x1000; the file is the same but with a different Unit
odir3 <- file.path(tmp, "obs_mg"); dir.create(odir3); file.copy(list.files(odir, full.names = TRUE), odir3)
f1 <- list.files(odir3, pattern = "IT9001A_8", full.names = TRUE)
x1 <- utils::read.csv(f1); x1$Unit <- "mg.m-3"; utils::write.csv(x1, f1, row.names = FALSE)
omg <- file.path(tmp, "u_obs")
suppressWarnings(bd(obs_dir = odir3, out_dir = omg))
stopifnot(rd(omg, "obs", "IT9001Aa")$NO2[2] == 1000)                                  # 1 mg/m3 = 1000 ug/m3
# manual factor on the observations (obs_factor column)
pol_f <- pollutants; pol_f$obs_factor <- c(2, NA, NA, NA)
of <- file.path(tmp, "u_obsf"); suppressWarnings(bd(pollutants = pol_f, out_dir = of))
stopifnot(rd(of, "obs", "IT9001Aa")$NO2[2] == 2)
# model in ng/m3 (to bring to ug/m3: x0.001) and in ppb (error until the factor is given)
mk_ll <- function(dirname, unit) {
  d <- file.path(tmp, dirname); dir.create(d)
  v <- lapply(c("NO2", "PM10"), function(n) ncdf4::ncvar_def(n, unit, list(dtm, dlat, dlon), -999))
  nc <- ncdf4::nc_create(file.path(d, "conc_IT0_20230101.nc"), v)
  for (n in c("NO2", "PM10")) ncdf4::ncvar_put(nc, n, arr)
  ncdf4::nc_close(nc); d
}
dng <- mk_ll("ll_ng", "ng/m3"); dppb <- mk_ll("ll_ppb", "ppb")
llargs <- list(model_pattern = "^conc_.*\\.nc$", model_grid = "lonlat", model_x_dim = "lon", model_y_dim = "lat", pollutants = pol_ll)
o_ng <- file.path(tmp, "u_ng"); suppressWarnings(do.call(bd, c(llargs, list(model_dir = dng, out_dir = o_ng))))
stopifnot(all.equal(rd(o_ng, "mod", "IT9001Aa")$NO2[1], 3.3))
stopifnot(grepl("ppb", err(do.call(bd, c(llargs, list(model_dir = dppb, out_dir = file.path(tmp, "u_ppb")))))))
pol_m <- pol_ll; pol_m$model_factor <- c(2, NA, 2, NA)
o_pm <- file.path(tmp, "u_ppbf"); suppressWarnings(do.call(bd, c(llargs[-5], list(pollutants = pol_m, model_dir = dppb, out_dir = o_pm))))
stopifnot(rd(o_pm, "mod", "IT9001Aa")$NO2[1] == 6600, rd(o_pm, "mod", "IT9001Aa")$PM10[1] == 6600)
# names and pollutants table
stopifnot(grepl("Invalid DELTA name: 'PM2.5'", err(check_pollutants(transform(pollutants, delta = c("NO2", "O3", "PM10", "PM2.5"))))))
stopifnot(grepl("Invalid DELTA name: 'PM_10'", err(check_pollutants(transform(pollutants, delta = c("NO2", "O3", "PM_10", "PM25"))))))
stopifnot(grepl("repeated values", err(check_pollutants(transform(pollutants, delta = c("NO2", "NO2", "PM10", "PM25"))))))
stopifnot(grepl("missing columns", err(check_pollutants(pollutants[, c("delta", "eea")]))))
# helper functions
lp <- list_eea_pollutants(file.path(tmp, "meta.csv")); stopifnot(setequal(lp$eea, c("NO2", "PM10")), all(lp$sampling_points == 2))
lv <- list_model_variables(dng, "^conc_.*\\.nc$", NULL); stopifnot(setequal(lv$variable, c("NO2", "PM10")), all(lv$units == "ng/m3"))
# uniqueness of Station Code / Name / abbreviation: two EoI stations with the same Nat Code (7001)
m5 <- meta; m5[["Air Quality Station Nat Code"]][4] <- "7001"; m5[["Longitude"]][4] <- "9.05"
utils::write.csv(m5, file.path(tmp, "meta_dupnat.csv"), row.names = FALSE)
o5 <- file.path(tmp, "dupnat")
w <- bd(meta_csv = file.path(tmp, "meta_dupnat.csv"), out_dir = o5)$warnings
ini5 <- readLines(file.path(o5, "startup.ini")); rows5 <- strsplit(ini5[(which(ini5 == "[MONITORING]") + 2):length(ini5)], ";")
cod5 <- vapply(rows5, `[`, "", 1); nam5 <- vapply(rows5, `[`, "", 2); abb5 <- vapply(rows5, `[`, "", 3)
stopifnot(any(grepl("Duplicate Station Code", w)), length(rows5) == 3,
          !anyDuplicated(cod5), !anyDuplicated(nam5), !anyDuplicated(abb5),
          setequal(cod5, c("7001aIT9001A", "7001b", "7001aIT9002A")))
# species selection: PM10 only (the table has 4); nonexistent species = error; folder name with the species
osel <- file.path(tmp, "sel")
rs <- suppressWarnings(bd(species = "PM10", out_dir = osel, out_label = NULL))
stopifnot(basename(rs$out_dir) == "2023_PM10_20230101-20230102",
          identical(names(rd(rs$out_dir, "obs", "IT9001Aa")), c("year", "month", "day", "hour", "PM10")),
          !any(grepl("NO2", readLines(file.path(rs$out_dir, "startup.ini")))))
stopifnot(grepl("Species not in the pollutants table: XYZ", err(bd(species = c("NO2", "XYZ"), out_dir = file.path(tmp, "sel2")))))
# table species without observations (O3, PM25 have no parquet): they do not appear in [PARAMETERS]
ini_p <- readLines(file.path(out, "startup.ini"))
pp <- ini_p[(which(ini_p == "[PARAMETERS]") + 2):(which(ini_p == "[MONITORING]") - 1)]
stopifnot(identical(pp, c("NO2;GAS;ugm-3", "PM10;PM;ugm-3")))
# report on screen and in the files: full warnings and discarded stations with EoI, municipality, province
m6 <- meta; m6[["Longitude"]][4] <- "8.915"                       # inside the municipality, but outside the model grid
utils::write.csv(m6, file.path(tmp, "meta_rep.csv"), row.names = FALSE)
o6 <- file.path(tmp, "rep")
screen6 <- msgs_of(r6 <- bd(meta_csv = file.path(tmp, "meta_rep.csv"), out_dir = o6))
d6 <- r6$discarded
stopifnot(nrow(d6) == 1, d6$eoi == "IT9002A", d6$item == "IT9002Aa", grepl("^Citt", d6$municipality),
          d6$province == "Provincia di Prova (PP)", grepl("outside the model grid", d6$reason))
stopifnot(grepl("===== WARNINGS \\(", screen6), grepl("===== DISCARDED STATIONS \\(1\\)", screen6),
          grepl("Variables missing in the NetCDF files, species dropped: O3, PM25", screen6), grepl("IT9002A", screen6),
          grepl("Provincia di Prova \\(PP\\)", screen6))
stopifnot(file.exists(file.path(o6, "discarded_stations.csv")), file.exists(file.path(o6, "warnings.txt")),
          any(grepl("IT9002A;IT9002Aa", readLines(file.path(o6, "discarded_stations.csv")))))
# without the province layer (optional) and position outside ISTAT: municipality from DataExtract.csv, province "-"
d7 <- bd(out_dir = file.path(tmp, "rep2"))$discarded                  # IT9002A at lon 12: outside every polygon
stopifnot(grepl("\\[EEA\\]$", d7$municipality), is.na(d7$province))
# station far from every municipality (polygon moved by 100 km): dropped -> explicit error
far <- file.path(tmp, "istat_far"); dir.create(far)
sf::st_write(sf::st_sf(COMUNE = "Far", geometry = sf::st_sfc(box(6e5, 4883e3, 8e3), crs = 32632)),
             file.path(far, "Com01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_REG = "Faraway", geometry = sf::st_sfc(box(6e5, 4883e3, 5e3), crs = 32632)),
             file.path(far, "Reg01012023_WGS84.shp"), quiet = TRUE)
w <- character(); 
msg <- err(bd(istat_dir = far, out_dir = file.path(tmp, "c4")))
screen <- msgs_of(bd(istat_dir = far, out_dir = file.path(tmp, "c4b")))   # the report appears on screen even if the script stops
w <- screen
stopifnot(any(grepl("from any ISTAT municipality, dropped: IT9001Aa", w)), grepl("No station with an ISTAT municipality", msg))
## --- Parquet <-> DataExtract matching (SPO, SPP, station+code, station only)
mk <- function(sp, spp, eoi, pol, lon = 9, lat = 45) data.frame(
  sp = sp, spp = spp, sp_eoi = eoi, code = sub("^SPO\\.[^_]+_([^_]+)_.*$", "\\1", sp),
  method = sub("^SPO\\.[^_]+_[^_]+_([^_]+)_.*$", "\\1", sp), pol_eea = pol, eoi = eoi, nat = "n", name = "S", pol = pol,
  lon = lon, lat = lat, alt = 1, area = "urban", type = "background",
  tz_offset = 1L, muni = NA_character_, stringsAsFactors = FALSE)
mt <- rbind(
  mk("SPO.IT1_5_BETA_2015-06-23_00:00:00", "SPP.IT1_5_LIGHT-SCAT_2022-01-01_00:00:00", "IT1", "PM10"),
  mk("SPO.IT1_8_chemi_1999-01-01_00:00:00", "SPP.IT1_8_chemi_1999-01-01_00:00:00", "IT1", "NO2", NA, NA),
  mk("SPO.IT1_8_chemi_2005-01-01_00:00:00", "SPP.IT1_8_chemi_2005-01-01_00:00:00", "IT1", "NO2", 9.5, 45.5),
  mk("SPO.IT1_38_chemi_1999-01-01_00:00:00", "SPP.IT1_38_chemi_1999-01-01_00:00:00", "IT1", NA))
m1 <- match_sampling_point("SPO.IT1_5_BETA_2015-06-23_00:00:00", mt); stopifnot(m1$how == "SPO")
m2 <- match_sampling_point("SPP.IT1_5_LIGHT-SCAT_2022-01-01_00:00:00", mt); stopifnot(m2$how == "SPP", m2$pol == "PM10")
m3 <- match_sampling_point("SPO.IT1_8_chemi_2010-05-05_00:00:00", mt)          # different date: between the two NO2 records the complete one wins
stopifnot(m3$how == "same station, code and method", m3$lon == 9.5)
m4 <- match_sampling_point("SPO.IT1_5_OTHER_2001-01-01_00:00:00", mt); stopifnot(m4$how == "same station and code", m4$pol == "PM10")
m5 <- match_sampling_point("SPO.IT1_77_X_2001-01-01_00:00:00", mt); stopifnot(m5$how == "station only", is.na(m5$pol))
m6 <- match_sampling_point("SPO.IT2_5_BETA_2015-06-23_00:00:00", mt); stopifnot(is.null(m6))
m7 <- match_sampling_point("SPO.IT1_38_chemi_1999-01-01_00:00:00", mt); stopifnot(m7$how == "SPO", is.na(m7$pol))   # species not selected
# POSIXct without time zone (like the parquet files read by arrow) with the R session in Europe/Rome:
# the clock must not shift (no +1 h in winter, +2 h in summer, no gap at the clock change)
tz0 <- Sys.getenv("TZ", unset = NA)
Sys.setenv(TZ = "Europe/Rome")
xn <- structure(as.numeric(as.POSIXct("2023-03-25 22:00:00", tz = "UTC")) + 3600 * (0:6), class = c("POSIXct", "POSIXt"), tzone = "")
stopifnot(identical(format(.naive_utc(xn), "%Y-%m-%d %H"),
                    format(as.POSIXct("2023-03-25 22:00:00", tz = "UTC") + 3600 * (0:6), "%Y-%m-%d %H")))
xe <- structure(as.numeric(as.POSIXct("2023-07-15 10:00:00", tz = "UTC")), class = c("POSIXct", "POSIXt"), tzone = "Europe/Rome")
stopifnot(format(.naive_utc(xe), "%H") == "12")                       # explicit zone: clock in that zone
if (is.na(tz0)) Sys.unsetenv("TZ") else Sys.setenv(TZ = tz0)
cat("SPO/SPP matching: ok\n")

cat("OK: all checks passed\n")
if (keep) {
  cat("Synthetic data and outputs kept in:", tmp, "\n",
      " - farm/, obs/, meta.csv, istat/  : synthetic inputs\n",
      " - out_local/  : output with tz_offset = 1 (startup.ini, obs/, mod/)\n",
      " - out_utc/    : output with tz_offset = 0\n")
}
