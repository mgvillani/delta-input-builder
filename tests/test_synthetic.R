# Test con dati interamente sintetici (nessun dato reale).
# Uso, dalla radice del repository:  Rscript tests/test_synthetic.R
for (f in list.files("R", full.names = TRUE)) source(f)
stopifnot(requireNamespace("ncdf4", quietly = TRUE), requireNamespace("sf", quietly = TRUE))

## --- Pulizia nomi ---------------------------------------------------------------
# Le lettere accentate sono costruite con intToUtf8 (stringhe marcate UTF-8 in qualunque locale,
# come quelle lette da sf o da read.csv(encoding = "UTF-8")).
e_acc <- intToUtf8(0xE9); i_acc <- intToUtf8(0xEC); a_acc <- intToUtf8(0xE0)
stopifnot(identical(
  clean_name(c(paste0("Agli", e_acc), "Albiano d'Ivrea", "Borgaro Torinese", "Reggio nell'Emilia",
               paste0("Valle d'Aosta/Vall", e_acc, "e d'Aoste"), paste0("Forl", i_acc),
               "Sant'Angelo-Lodigiano", NA, "")),
  c("Aglie", "Albiano d'Ivrea", "Borgaro Torinese", "Reggio nell'Emilia",
    "Valle d'Aosta/Vallee d'Aoste", "Forli", "Sant'Angelo-Lodigiano", "NA", "NA")))
stopifnot(identical(clean_name(c("A;B*C_D", "  x   y ")), c("A B C D", "x y")))

# Opzionale: una cartella dove CONSERVARE dati sintetici e output (altrimenti cartella temporanea,
# cancellata alla chiusura di R). Esempio:  Rscript tests/test_synthetic.R test_output
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && nzchar(args[1])) {
  tmp <- normalizePath(args[1], mustWork = FALSE)
  if (dir.exists(tmp) && length(list.files(tmp))) stop("La cartella ", tmp, " non e' vuota: indicane una nuova o vuota.")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  keep <- TRUE
} else {
  tmp <- tempfile("delta_test_"); dir.create(tmp)
  keep <- FALSE
}
mdir <- file.path(tmp, "farm"); odir <- file.path(tmp, "obs"); dir.create(mdir); dir.create(odir)

## --- Modello: griglia 4 km attorno a lon 9 / lat 45 (UTM easting 500 km, northing ~4983 km)
## I tempi dei NetCDF sono in UTC+1: file 1 = 00..24 locali del 1/1, file 2 = 00..24 del 2/1.
gx <- seq(496, 508, by = 4); gy <- seq(4980, 4992, by = 4)
make_nc <- function(path, t0, val_first) {
  tm <- t0 + 0:24
  dx <- ncdf4::ncdim_def("x", "km", gx); dy <- ncdf4::ncdim_def("y", "km", gy)
  dz <- ncdf4::ncdim_def("z", "", 20)
  dt <- ncdf4::ncdim_def("time", "hours since 1900-1-1 00:00:0.0", tm)
  vars <- lapply(c("c_NO2", "c_PM10"), function(n) ncdf4::ncvar_def(n, "ug/m3", list(dx, dy, dz, dt), -9.96921e36))
  nc <- ncdf4::nc_create(path, vars)
  v <- array(rep(10 + (0:24), each = length(gx) * length(gy)), c(length(gx), length(gy), 1, 25))
  v[, , , 1] <- val_first                      # il primo passo di ogni file e' marcato
  for (n in c("c_NO2", "c_PM10")) ncdf4::ncvar_put(nc, n, v)
  ncdf4::nc_close(nc)
}
make_nc(file.path(mdir, "FARM_conc_g2_20230101_D1.nc"), 1078200, 111)
make_nc(file.path(mdir, "FARM_conc_g2_20230102_D1.nc"), 1078224, 222)

## --- Metadati EEA: stazione A (dentro la griglia) con NO2 + due PM10; stazione B fuori griglia
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

## --- Osservazioni (ora locale UTC+01, come EEA)
write_obs <- function(spid, start, end, value, agg) {
  d <- data.frame(Samplingpoint = paste0("IT/", spid), Pollutant = 0,
                  Start = format(start, "%Y-%m-%d %H:%M:%S"), End = format(end, "%Y-%m-%d %H:%M:%S"),
                  Value = value, Unit = "ug.m-3", AggType = agg, Validity = 1L, Verification = 1L,
                  stringsAsFactors = FALSE)
  utils::write.csv(d, file.path(odir, paste0(gsub("[^A-Za-z0-9]", "_", spid), ".csv")), row.names = FALSE)
}
L0 <- as.POSIXct("2023-01-01 00:00:00", tz = "UTC")
h <- L0 + 3600 * (1:48)                                  # 01:00 locale 1/1 ... 00:00 locale 3/1
write_obs(sp[1], h, h + 3600, 1:48, "hour")              # NO2 orario: valore = indice
write_obs(sp[2], L0 + 86400 * 0:1, L0 + 86400 * 1:2, c(30, 40), "day")   # PM10 BETA, 2 giorni
write_obs(sp[3], L0, L0 + 36 * 3600, 35, "var")                          # PM10 GRAV, "var": 36 ore
write_obs(sp[4], h, h + 3600, 1:48, "hour")              # stazione fuori griglia

## --- Limiti ISTAT sintetici (layer Com*/Reg*, UTM 32N), nomi con accento, apostrofo e spazi
istat_dir <- file.path(tmp, "istat"); dir.create(istat_dir)
box <- function(e, n, r) sf::st_polygon(list(matrix(c(e - r, n - r, e + r, n - r, e + r, n + r,
                                                      e - r, n + r, e - r, n - r), ncol = 2, byrow = TRUE)))
sf::st_write(sf::st_sf(COMUNE = paste0("Citt", a_acc, " d'Esempio"), geometry = sf::st_sfc(box(5e5, 4983e3, 8e3), crs = 32632)),
             file.path(istat_dir, "Com01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_REG = "Regione di Prova/Test", geometry = sf::st_sfc(box(5e5, 4983e3, 5e4), crs = 32632)),
             file.path(istat_dir, "Reg01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_UTS = "Provincia di Prova", SIGLA = "PP", geometry = sf::st_sfc(box(5e5, 4983e3, 3e4), crs = 32632)),
             file.path(istat_dir, "ProvCM01012023_WGS84.shp"), quiet = TRUE)

# Parametri di base (nessun valore predefinito nel codice: si danno tutti); ogni caso ne sovrascrive alcuni.
pollutants <- data.frame(delta = c("NO2", "O3", "PM10", "PM25"), eea = c("NO2", "O3", "PM10", "PM2.5"),
                         farm = c("c_NO2", "c_O3", "c_PM10", "c_PM25"), type = c("GAS", "GAS", "PM", "PM"),
                         unit = "ugm-3", stringsAsFactors = FALSE)
base_args <- list(
  obs_dir = odir, obs_pattern = "\\.csv$", meta_csv = file.path(tmp, "meta.csv"),
  model_dir = mdir, model_pattern = "^FARM_conc_.*\\.nc$", model_version = NULL,
  istat_dir = istat_dir, istat_year = NULL, istat_max_dist_m = 2000,
  comune_col = "COMUNE", region_col = "DEN_REG", province_col = "DEN_UTS", province_abbr_col = "SIGLA",
  pollutants = pollutants, species = NULL,
  out_dir = NULL, out_label = "", startup_name = "startup.ini", discarded_name = "stazioni_scartate.csv", warnings_name = "avvisi.txt", year = 2023,
  period = c(as.POSIXct("2023-01-01 00:00", tz = "UTC"), as.POSIXct("2023-01-02 23:00", tz = "UTC")),
  scale = "urban", valid_codes = 1L, min_coverage = 0, eol = "\n",
  model_grid = "utm", model_x_dim = "x", model_y_dim = "y", model_time_dim = "time", utm_lon0 = 9,
  tz_offset = 1, obs_tz_offset = NULL, model_tz_offset = 1, gmt_lag = NULL, model_shift_h = 0, model_interp = "nearest", obs_hour_label = "start")
bd <- function(...) {                       # sovrascrive i parametri indicati (anche con NULL)
  ov <- list(...); a <- base_args
  for (n in names(ov)) a[n] <- list(ov[[n]])
  do.call(build_delta_inputs, a)
}
run <- function(name, istat = istat_dir, ...) {
  out <- file.path(tmp, name)
  suppressWarnings(bd(istat_dir = istat, out_dir = out, ...))
  out
}
msgs_of <- function(expr) {                 # tutti i messaggi a schermo (compreso il rapporto finale)
  m <- character()
  withCallingHandlers(try(expr, silent = TRUE), message = function(x) { m <<- c(m, conditionMessage(x)); invokeRestart("muffleMessage") })
  paste(m, collapse = "\n")
}
rd <- function(out, kind, id) utils::read.csv(file.path(out, kind, paste0(id, ".csv")), sep = ";")
last2 <- function(out) { ini <- readLines(file.path(out, "startup.ini")); ini[length(ini) - 1:0] }

## === A. Output in UTC (tz_offset = 0)
out <- run("out_utc", tz_offset = 0)
stopifnot(setequal(list.files(file.path(out, "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))  # a / b, B scartata
stopifnot(identical(list.files(file.path(out, "obs")), list.files(file.path(out, "mod"))))
oa <- rd(out, "obs", "IT9001Aa"); ob <- rd(out, "obs", "IT9001Ab"); ma <- rd(out, "mod", "IT9001Aa")
stopifnot(identical(names(oa), c("year", "month", "day", "hour", "NO2", "PM10")),
          identical(names(ob), c("year", "month", "day", "hour", "PM10")), nrow(oa) == 48)
# la prima ora UTC e' la 01:00 locale -> NO2 = 1; il PM10 giornaliero e' ripetuto; 00 locali 2/1 = 23 UTC
stopifnot(oa$NO2[1] == 1, oa$NO2[48] == 48, all(oa$PM10[1:23] == 30), oa$PM10[24] == 40)
stopifnot(all(ob$PM10[1:35] == 35), ob$PM10[36] == -999)         # "var" 36 ore = 35 ore nella finestra
# modello: riga r (ora UTC r-1) = ora locale r; 00 locale del 2/1 = riga 24 dal file piu' recente (222)
stopifnot(nrow(ma) == 48, ma$NO2[1] == 11, ma$PM10[2] == 12, ma$NO2[24] == 222, ma$NO2[25] == 11, ma$NO2[48] == 34)
stopifnot(identical(last2(out), c("7001a;IT9001Aa;IT9001Aa;100;9;45;UTC;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;NO2*PM10",
                                  "7001b;IT9001Ab;IT9001Ab;100;9;45;UTC;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;PM10")))

## === B. Default (tz_offset = 1): nessuno sfasamento
out <- run("out_local")
oa <- rd(out, "obs", "IT9001Aa"); ob <- rd(out, "obs", "IT9001Ab"); ma <- rd(out, "mod", "IT9001Aa")
stopifnot(oa$NO2[1] == -999, oa$NO2[2] == 1, oa$NO2[48] == 47)  # la riga r e' l'ora locale r-1
stopifnot(all(oa$PM10[1:24] == 30), all(oa$PM10[25:48] == 40))
stopifnot(all(ob$PM10[1:36] == 35), ob$PM10[37] == -999)
stopifnot(ma$NO2[1] == 111, ma$NO2[2] == 11, ma$NO2[24] == 33, ma$NO2[25] == 222, ma$NO2[26] == 11, ma$NO2[48] == 33)
stopifnot(identical(last2(out), c("7001a;IT9001Aa;IT9001Aa;100;9;45;UTC+1;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;NO2*PM10",
                                  "7001b;IT9001Ab;IT9001Ab;100;9;45;UTC+1;Regione di Prova/Test;traffic;rural-nearcity;Citta d'Esempio;PM10")))
## === C. I limiti ISTAT sono obbligatori e stanno in una cartella dedicata
err <- function(expr) tryCatch({ expr; "nessun errore" }, error = function(e) conditionMessage(e))
stopifnot(grepl("obbligatoria", err(run("c1", istat = NULL))))                       # non indicata
stopifnot(grepl("obbligatoria", err(run("c2", istat = file.path(tmp, "non_esiste")))))  # cartella inesistente
empty <- file.path(tmp, "istat_vuota"); dir.create(empty)
stopifnot(grepl("Nessun limite ISTAT", err(run("c3", istat = empty))))               # cartella senza dati
# cartella con lo zip ISTAT dentro (come scaricato da ISTAT)
if (nzchar(Sys.which("zip"))) {
  zdir <- file.path(tmp, "istat_zip"); dir.create(zdir)
  old <- setwd(istat_dir)
  utils::zip(file.path(zdir, "Limiti01012023.zip"), list.files("."), flags = "-q")
  setwd(old)
  out <- run("out_zip", istat = zdir)
  stopifnot(identical(last2(out), last2(file.path(tmp, "out_local"))))
} else message("(zip non disponibile: test della cartella con lo zip saltato)")
# piu' edizioni ISTAT nella stessa cartella (una per anno, come zip): si usa quella dell'anno
if (nzchar(Sys.which("zip"))) {
  mdir_i <- file.path(tmp, "istat_multi"); dir.create(mdir_i)
  mk_ed <- function(yr, nome) {
    d <- file.path(tmp, paste0("ed", yr)); dir.create(d)
    sf::st_write(sf::st_sf(COMUNE = nome, geometry = sf::st_sfc(box(5e5, 4983e3, 8e3), crs = 32632)),
                 file.path(d, paste0("Com0101", yr, "_WGS84.shp")), quiet = TRUE)
    sf::st_write(sf::st_sf(DEN_REG = "Reg", geometry = sf::st_sfc(box(5e5, 4983e3, 5e4), crs = 32632)),
                 file.path(d, paste0("Reg0101", yr, "_WGS84.shp")), quiet = TRUE)
    old <- setwd(d); on.exit(setwd(old))
    utils::zip(file.path(mdir_i, paste0("Limiti0101", yr, ".zip")), list.files("."), flags = "-q")
  }
  mk_ed(2023, "Comune2023"); mk_ed(2025, "Comune2025")
  siting <- function(out) strsplit(last2(out)[1], ";")[[1]][11]
  stopifnot(siting(run("m1", istat = mdir_i)) == "Comune2023")                      # year = 2023
  stopifnot(siting(run("m2", istat = mdir_i, istat_year = 2025)) == "Comune2025")   # esplicito
  bnd_ed <- function(y) attr(read_istat_boundaries(mdir_i, y), "edition")
  stopifnot(identical(bnd_ed(2023), 2023L), identical(bnd_ed(2025), 2025L), identical(bnd_ed(NULL), 2025L))
  w <- character()
  withCallingHandlers(ed <- bnd_ed(2024), warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  stopifnot(ed == 2023L, any(grepl("Nessuna edizione ISTAT del 2024", w)))         # ripiega sulla precedente
  suppressWarnings(stopifnot(bnd_ed(2020) == 2023L))                                # nessuna precedente: la piu' vecchia
}
# versione/pattern del modello: due run (g2 e g3) nella stessa cartella, si sceglie con model_version
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
stopifnot(grepl("versione 'g9'", err(runv("v_none", model_version = "g9"))))
# stazione senza coordinate nei metadati: scartata con avviso, il resto procede
m2 <- meta; m2[["Longitude"]][4] <- NA; m2[["Latitude"]][4] <- NA
utils::write.csv(m2, file.path(tmp, "meta_nocoord.csv"), row.names = FALSE)
rn <- bd(meta_csv = file.path(tmp, "meta_nocoord.csv"), out_dir = file.path(tmp, "nc1")); w <- rn$warnings
stopifnot(any(grepl("senza coordinate nei metadati, scartati: IT9002Aa", w)),
          setequal(list.files(file.path(tmp, "nc1", "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))
# valori diversi tra i record della stessa stazione: restano come nel file, per file (a / b)
m3 <- meta
m3[["Longitude"]][3] <- "9.0002"; m3[["Latitude"]][3] <- "45.0002"
m3[["Air Quality Station Type"]][3] <- "background"; m3[["Air Quality Station Area"]][3] <- "urban"
utils::write.csv(m3, file.path(tmp, "meta_disc.csv"), row.names = FALSE)
o3 <- file.path(tmp, "disc"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_disc.csv"), out_dir = o3))
l3 <- last2(o3)
stopifnot(grepl("^7001a;IT9001Aa;IT9001Aa;100;9;45;UTC\\+1;.*;traffic;rural-nearcity;", l3[1]),
          grepl("^7001b;IT9001Ab;IT9001Ab;100;9.0002;45.0002;UTC\\+1;.*;background;urban;", l3[2]))
# dato mancante: solo allora si usa il valore della stessa stazione (qui: quota, tipo, area, lon/lat del record 3 vuoti)
m4 <- meta
m4[["Longitude"]][3] <- NA; m4[["Latitude"]][3] <- NA; m4[["Altitude"]][3] <- NA
m4[["Air Quality Station Type"]][3] <- NA; m4[["Air Quality Station Area"]][3] <- NA
utils::write.csv(m4, file.path(tmp, "meta_na.csv"), row.names = FALSE, na = "")
w <- character(); msgs <- character()
o4 <- file.path(tmp, "na_fill")
withCallingHandlers(bd(meta_csv = file.path(tmp, "meta_na.csv"), out_dir = o4),
  message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") },
  warning = function(x) invokeRestart("muffleWarning"))
stopifnot(grepl("Dati mancanti nei metadati, completati con quelli della stessa stazione: IT9001A", paste(msgs, collapse = "")),
          grepl("^7001b;IT9001Ab;IT9001Ab;100;9;45;UTC\\+1;.*;traffic;rural-nearcity;", last2(o4)[2]))
# stessa stazione con tipo diverso per inquinante: file separati (a = PM10 traffic, il piu' coperto; b = NO2 industrial; c = secondo PM10)
m5 <- meta; m5[["Air Quality Station Type"]][1] <- "industrial"
utils::write.csv(m5, file.path(tmp, "meta_type.csv"), row.names = FALSE)
o5 <- file.path(tmp, "typesplit"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_type.csv"), out_dir = o5))
l5 <- readLines(file.path(o5, "startup.ini")); l5 <- l5[grepl("^7001", l5)]
stopifnot(length(l5) == 3,
          grepl("^7001a;IT9001Aa;.*;traffic;rural-nearcity;.*;PM10$", l5[1]),
          grepl("^7001b;IT9001Ab;.*;industrial;rural-nearcity;.*;NO2$", l5[2]),
          grepl("^7001c;IT9001Ac;.*;traffic;rural-nearcity;.*;PM10$", l5[3]))
# soglia di copertura: GRAV ha 36 ore su 48 (75%)
r75 <- bd(min_coverage = 0.75, out_dir = file.path(tmp, "cov75"))
stopifnot(setequal(list.files(file.path(tmp, "cov75", "obs")), c("IT9001Aa.csv", "IT9001Ab.csv")))
r80 <- bd(min_coverage = 0.8, out_dir = file.path(tmp, "cov80"))
stopifnot(identical(list.files(file.path(tmp, "cov80", "obs")), "IT9001Aa.csv"),
          any(grepl("sotto la soglia del 80%", r80$discarded$motivo)) || any(grepl("sotto la soglia del 80%", unlist(r80$discarded))))
stopifnot(grepl("min_coverage", err(bd(min_coverage = 1.5, out_dir = file.path(tmp, "cov_bad")))))
# codici di validita': NO2 con Validity 1 su meta' delle ore e 2 sull'altra meta'
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
# etichetta dell'ora delle osservazioni: "end" sposta di +1 h rispetto a "start"
oS <- file.path(tmp, "lab_start"); oE <- file.path(tmp, "lab_end")
suppressWarnings(bd(out_dir = oS, obs_hour_label = "start")); suppressWarnings(bd(out_dir = oE, obs_hour_label = "end"))
no_s <- rd(oS, "obs", "IT9001Aa")$NO2; no_e <- rd(oE, "obs", "IT9001Aa")$NO2
stopifnot(identical(no_e[-1][!is.na(no_s[-length(no_s)])], no_s[-length(no_s)][!is.na(no_s[-length(no_s)])]) || all(no_e[-1] == no_s[-length(no_s)]))
stopifnot(grepl("obs_hour_label", err(bd(obs_hour_label = "mid", out_dir = file.path(tmp, "lab_bad")))))
# tutti i decimali di quota, lon e lat
m6 <- meta; m6[["Longitude"]][1:3] <- "9.012345"; m6[["Latitude"]][1:3] <- "45.000123"; m6[["Altitude"]][1:3] <- "12.5"
utils::write.csv(m6, file.path(tmp, "meta_dec.csv"), row.names = FALSE)
o6 <- file.path(tmp, "dec"); suppressWarnings(bd(meta_csv = file.path(tmp, "meta_dec.csv"), out_dir = o6))
stopifnot(grepl("^7001a;IT9001Aa;IT9001Aa;12.5;9.012345;45.000123;", last2(o6)[1]))
# modello su griglia lon/lat (dimensioni time, lat decrescente, lon; tempo in secondi; nomi variabili propri)
ldir <- file.path(tmp, "lonlat"); dir.create(ldir)
glon <- seq(8.5, 9.5, by = 0.25); glat <- seq(45.5, 44.5, by = -0.25)         # 9.0 -> indice 3; 45.0 -> indice 3
dlon <- ncdf4::ncdim_def("lon", "degrees_east", glon); dlat <- ncdf4::ncdim_def("lat", "degrees_north", glat)
dtm <- ncdf4::ncdim_def("time", "seconds since 2023-01-01 00:00:00", 3600 * (0:47))
vl <- lapply(c("NO2", "PM10"), function(n) ncdf4::ncvar_def(n, "ug/m3", list(dtm, dlat, dlon), -999))  # ordine time,lat,lon
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
# interpolazione bilineare: campo lineare 1000*la + 100*lo -> a (lon 9.05, lat 45.05) vale 3120 (il piu' vicino darebbe 3300)
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
ic <- interp_cells(c(9.05), c(45.05), glon, glat, "bilinear")        # lat decrescente
stopifnot(ic$ix0 == 3, ic$ix1 == 4, abs(ic$wx - 0.2) < 1e-9, ic$iy0 == 3, ic$iy1 == 2, abs(ic$wy - 0.2) < 1e-9)
stopifnot(grepl("Variabili presenti: NO2, PM10", err(bd(model_dir = ldir, model_pattern = "^conc_.*\\.nc$", out_dir = file.path(tmp, "ll_err1")))))  # nomi variabili sbagliati
stopifnot(grepl("dimensioni presenti: time, lat, lon", err(bd(model_dir = ldir, model_pattern = "^conc_.*\\.nc$", pollutants = pol_ll,
                                                           model_grid = "utm", out_dir = file.path(tmp, "ll_err2")))))   # dimensioni x,y inesistenti
# sottocartella di output automatica: anno, versione del modello, periodo
oa <- file.path(tmp, "lab"); r1 <- suppressWarnings(bd(model_dir = mdir2, model_version = "g2", out_dir = oa, out_label = NULL))
stopifnot(basename(r1$out_dir) == "2023_g2_20230101-20230102", file.exists(file.path(r1$out_dir, "startup.ini")))
r2 <- suppressWarnings(bd(period = NULL, out_dir = oa, out_label = NULL))
stopifnot(basename(r2$out_dir) == "2023", file.exists(file.path(oa, "2023", "startup.ini")))
r3 <- suppressWarnings(bd(out_dir = oa, out_label = "mio_run"))
stopifnot(basename(r3$out_dir) == "mio_run")
# due versioni mischiate nella stessa cartella: avviso
w <- bd(model_dir = mdir2, out_dir = file.path(tmp, "mix"))$warnings
stopifnot(any(grepl("piu' versioni del modello", w)))
# --- unita' di misura -------------------------------------------------------------------
stopifnot(identical(.mass_per_unit(c("ug/m3", "ug.m-3", "mg m-3", "ugm-3", paste0(intToUtf8(181), "g/m3"), "ng/m3", "ppb", NA)),
                    c(1e-6, 1e-6, 1e-3, 1e-6, 1e-6, 1e-9, NA, NA)))
stopifnot(all.equal(unit_factor(c("mg.m-3", "ng.m-3"), "ugm-3", NA, "x"), c(1000, 0.001)))
stopifnot(unit_factor("ppb", "ugm-3", 1.88, "x") == 1.88)                           # fattore a mano
stopifnot(grepl("ppb", tryCatch(unit_factor("ppb", "ugm-3", NA, "x"), error = function(e) conditionMessage(e))))
# osservazioni NO2 in mg.m-3: ×1000; il file e' lo stesso ma con Unit diversa
odir3 <- file.path(tmp, "obs_mg"); dir.create(odir3); file.copy(list.files(odir, full.names = TRUE), odir3)
f1 <- list.files(odir3, pattern = "IT9001A_8", full.names = TRUE)
x1 <- utils::read.csv(f1); x1$Unit <- "mg.m-3"; utils::write.csv(x1, f1, row.names = FALSE)
omg <- file.path(tmp, "u_obs")
suppressWarnings(bd(obs_dir = odir3, out_dir = omg))
stopifnot(rd(omg, "obs", "IT9001Aa")$NO2[2] == 1000)                                  # 1 mg/m3 = 1000 ug/m3
# fattore a mano sulle osservazioni (colonna obs_factor)
pol_f <- pollutants; pol_f$obs_factor <- c(2, NA, NA, NA)
of <- file.path(tmp, "u_obsf"); suppressWarnings(bd(pollutants = pol_f, out_dir = of))
stopifnot(rd(of, "obs", "IT9001Aa")$NO2[2] == 2)
# modello in ng/m3 (da portare a ug/m3: ×0.001) e in ppb (errore finche' non si da' il fattore)
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
# nomi e tabella pollutants
stopifnot(grepl("Nome DELTA non valido: 'PM2.5'", err(check_pollutants(transform(pollutants, delta = c("NO2", "O3", "PM10", "PM2.5"))))))
stopifnot(grepl("Nome DELTA non valido: 'PM_10'", err(check_pollutants(transform(pollutants, delta = c("NO2", "O3", "PM_10", "PM25"))))))
stopifnot(grepl("valori ripetuti", err(check_pollutants(transform(pollutants, delta = c("NO2", "NO2", "PM10", "PM25"))))))
stopifnot(grepl("mancano le colonne", err(check_pollutants(pollutants[, c("delta", "eea")]))))
# funzioni di aiuto
lp <- list_eea_pollutants(file.path(tmp, "meta.csv")); stopifnot(setequal(lp$eea, c("NO2", "PM10")), all(lp$sampling_points == 2))
lv <- list_model_variables(dng, "^conc_.*\\.nc$", NULL); stopifnot(setequal(lv$variable, c("NO2", "PM10")), all(lv$units == "ng/m3"))
# unicita' di Station Code / Name / abbreviation: due stazioni EoI con lo stesso Nat Code (7001)
m5 <- meta; m5[["Air Quality Station Nat Code"]][4] <- "7001"; m5[["Longitude"]][4] <- "9.05"
utils::write.csv(m5, file.path(tmp, "meta_dupnat.csv"), row.names = FALSE)
o5 <- file.path(tmp, "dupnat")
w <- bd(meta_csv = file.path(tmp, "meta_dupnat.csv"), out_dir = o5)$warnings
ini5 <- readLines(file.path(o5, "startup.ini")); rows5 <- strsplit(ini5[(which(ini5 == "[MONITORING]") + 2):length(ini5)], ";")
cod5 <- vapply(rows5, `[`, "", 1); nam5 <- vapply(rows5, `[`, "", 2); abb5 <- vapply(rows5, `[`, "", 3)
stopifnot(any(grepl("Station Code duplicato", w)), length(rows5) == 3,
          !anyDuplicated(cod5), !anyDuplicated(nam5), !anyDuplicated(abb5),
          setequal(cod5, c("7001aIT9001A", "7001b", "7001aIT9002A")))
# selezione delle specie: solo PM10 (la tabella ne ha 4); specie inesistente = errore; nome cartella con le specie
osel <- file.path(tmp, "sel")
rs <- suppressWarnings(bd(species = "PM10", out_dir = osel, out_label = NULL))
stopifnot(basename(rs$out_dir) == "2023_PM10_20230101-20230102",
          identical(names(rd(rs$out_dir, "obs", "IT9001Aa")), c("year", "month", "day", "hour", "PM10")),
          !any(grepl("NO2", readLines(file.path(rs$out_dir, "startup.ini")))))
stopifnot(grepl("Specie non presenti nella tabella pollutants: XYZ", err(bd(species = c("NO2", "XYZ"), out_dir = file.path(tmp, "sel2")))))
# specie della tabella senza osservazioni (O3, PM25 non hanno parquet): non compaiono in [PARAMETERS]
ini_p <- readLines(file.path(out, "startup.ini"))
pp <- ini_p[(which(ini_p == "[PARAMETERS]") + 2):(which(ini_p == "[MONITORING]") - 1)]
stopifnot(identical(pp, c("NO2;GAS;ugm-3", "PM10;PM;ugm-3")))
# rapporto a schermo e nei file: avvisi completi e stazioni scartate con EoI, comune, provincia
m6 <- meta; m6[["Longitude"]][4] <- "8.915"                       # dentro il comune, ma fuori dalla griglia del modello
utils::write.csv(m6, file.path(tmp, "meta_rep.csv"), row.names = FALSE)
o6 <- file.path(tmp, "rep")
screen6 <- msgs_of(r6 <- bd(meta_csv = file.path(tmp, "meta_rep.csv"), out_dir = o6))
d6 <- r6$discarded
stopifnot(nrow(d6) == 1, d6$eoi == "IT9002A", d6$elemento == "IT9002Aa", grepl("^Citt", d6$comune),
          d6$provincia == "Provincia di Prova (PP)", grepl("fuori dalla griglia", d6$motivo))
stopifnot(grepl("===== AVVISI \\(", screen6), grepl("===== STAZIONI SCARTATE \\(1\\)", screen6),
          grepl("Variabili assenti nei NetCDF, specie scartate: O3, PM25", screen6), grepl("IT9002A", screen6),
          grepl("Provincia di Prova \\(PP\\)", screen6))
stopifnot(file.exists(file.path(o6, "stazioni_scartate.csv")), file.exists(file.path(o6, "avvisi.txt")),
          any(grepl("IT9002A;IT9002Aa", readLines(file.path(o6, "stazioni_scartate.csv")))))
# senza layer delle province (facoltativo) e posizione fuori dall'ISTAT: comune dal DataExtract.csv, provincia "-"
d7 <- bd(out_dir = file.path(tmp, "rep2"))$discarded                  # IT9002A a lon 12: fuori da ogni poligono
stopifnot(grepl("\\[EEA\\]$", d7$comune), is.na(d7$provincia))
# stazione lontana da ogni comune (poligono spostato di 100 km): scartata -> errore esplicito
far <- file.path(tmp, "istat_lontano"); dir.create(far)
sf::st_write(sf::st_sf(COMUNE = "Lontano", geometry = sf::st_sfc(box(6e5, 4883e3, 8e3), crs = 32632)),
             file.path(far, "Com01012023_WGS84.shp"), quiet = TRUE)
sf::st_write(sf::st_sf(DEN_REG = "Lontana", geometry = sf::st_sfc(box(6e5, 4883e3, 5e3), crs = 32632)),
             file.path(far, "Reg01012023_WGS84.shp"), quiet = TRUE)
w <- character(); 
msg <- err(bd(istat_dir = far, out_dir = file.path(tmp, "c4")))
screen <- msgs_of(bd(istat_dir = far, out_dir = file.path(tmp, "c4b")))   # il rapporto compare a schermo anche se lo script si ferma
w <- screen
stopifnot(any(grepl("da ogni comune ISTAT, scartati: IT9001Aa", w)), grepl("Nessuna stazione con comune", msg))
## --- Abbinamento parquet <-> DataExtract (SPO, SPP, stazione+codice, solo stazione)
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
m3 <- match_sampling_point("SPO.IT1_8_chemi_2010-05-05_00:00:00", mt)          # data diversa: tra i due NO2 vince quello completo
stopifnot(m3$how == "stessa stazione, codice e metodo", m3$lon == 9.5)
m4 <- match_sampling_point("SPO.IT1_5_OTHER_2001-01-01_00:00:00", mt); stopifnot(m4$how == "stessa stazione e codice", m4$pol == "PM10")
m5 <- match_sampling_point("SPO.IT1_77_X_2001-01-01_00:00:00", mt); stopifnot(m5$how == "solo stazione", is.na(m5$pol))
m6 <- match_sampling_point("SPO.IT2_5_BETA_2015-06-23_00:00:00", mt); stopifnot(is.null(m6))
m7 <- match_sampling_point("SPO.IT1_38_chemi_1999-01-01_00:00:00", mt); stopifnot(m7$how == "SPO", is.na(m7$pol))   # specie non selezionata
# POSIXct senza fuso (come i parquet letti da arrow) con la sessione R in Europe/Rome:
# l'orologio non deve spostarsi (nessun +1 h d'inverno, +2 h d'estate, nessun buco al cambio d'ora)
tz0 <- Sys.getenv("TZ", unset = NA)
Sys.setenv(TZ = "Europe/Rome")
xn <- structure(as.numeric(as.POSIXct("2023-03-25 22:00:00", tz = "UTC")) + 3600 * (0:6), class = c("POSIXct", "POSIXt"), tzone = "")
stopifnot(identical(format(.naive_utc(xn), "%Y-%m-%d %H"),
                    format(as.POSIXct("2023-03-25 22:00:00", tz = "UTC") + 3600 * (0:6), "%Y-%m-%d %H")))
xe <- structure(as.numeric(as.POSIXct("2023-07-15 10:00:00", tz = "UTC")), class = c("POSIXct", "POSIXt"), tzone = "Europe/Rome")
stopifnot(format(.naive_utc(xe), "%H") == "12")                       # fuso esplicito: orologio in quel fuso
if (is.na(tz0)) Sys.unsetenv("TZ") else Sys.setenv(TZ = tz0)
cat("abbinamento SPO/SPP: ok\n")

cat("OK: tutti i controlli superati\n")
if (keep) {
  cat("Dati sintetici e output conservati in:", tmp, "\n",
      " - farm/, obs/, meta.csv, istat/  : input sintetici\n",
      " - out_local/  : output con tz_offset = 1 (startup.ini, obs/, mod/)\n",
      " - out_utc/    : output con tz_offset = 0\n")
}
