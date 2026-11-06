# Esempio d'uso. QUI, E SOLO QUI, si impostano tutti i parametri: le funzioni in R/
# non hanno valori predefiniti nascosti per nomi di file, cartelle, fusi o tabelle.
# Adatta i valori alla tua esecuzione (i dati non sono inclusi nel repository).
#
# Lancia lo script dalla cartella principale del progetto (quella con R/ dentro).
if (!file.exists("R/build.R")) {
  stop("Lancia lo script dalla cartella principale del progetto (quella che contiene ",
       "la cartella R/ e questo file). Cartella attuale: ", getwd())
}
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

## ============================== PARAMETRI ====================================

## --- Osservazioni EEA
obs_dir     <- "dati/eea_parquet"            # un file per sampling point
obs_pattern <- "\\.parquet$"                 # regex sul nome dei file di osservazioni
meta_csv    <- "dati/DataExtract.csv"        # metadati stazioni EEA

## --- Modello (file di concentrazione)
model_dir     <- "dati/farm"                 # cartella dei NetCDF
model_pattern <- "^conc_.*\\.nc$"            # regex sul nome dei file da leggere (FARM: "^FARM_conc_.*\\.nc$")
model_version <- NULL                        # es. "g2": testo che il nome deve contenere; NULL = nessun filtro
# Griglia del modello: "utm" (x,y in km UTM, come FARM) oppure "lonlat" (gradi)
model_grid     <- "lonlat"
model_x_dim    <- "lon"                      # nome della dimensione x nei NetCDF ("x" per FARM UTM)
model_y_dim    <- "lat"                      # nome della dimensione y ("y" per FARM UTM)
model_time_dim <- "time"
model_interp   <- "bilinear"                 # dal modello alla stazione: "nearest" = cella piu' vicina; "bilinear" = interpolazione
                                             # bilineare tra le 4 celle intorno (come raster::extract(method = "bilinear"))
utm_lon0       <- 9                          # solo model_grid = "utm": meridiano centrale (9 per FARM)

## --- Limiti amministrativi ISTAT (OBBLIGATORI): uno zip per anno nella stessa cartella
istat_dir        <- "dati/istat"
istat_year       <- NULL                     # NULL = usa l'edizione dell'anno `year`
istat_max_dist_m <- 2000                     # stazioni fuori dai comuni: entro questa distanza (m) o scartate
comune_col       <- "COMUNE"                 # colonna ISTAT con il nome del comune
region_col       <- "DEN_REG"                # colonna ISTAT con il nome della regione
province_col      <- "DEN_UTS"               # layer ProvCM*: nome della provincia (edizioni vecchie: "DEN_PROV"); solo per il rapporto delle stazioni scartate
province_abbr_col <- "SIGLA"                 # layer ProvCM*: sigla della provincia

## --- Inquinanti: UNA RIGA PER SPECIE, tutte quelle che vuoi preparare
##   delta  nome scritto nello startup e nei CSV (solo lettere e cifre; niente spazi, '_', ';', '*', '.')
##   eea    nome nella colonna "Air Pollutant" del DataExtract.csv (list_eea_pollutants(meta_csv) li elenca)
##   farm   nome della variabile nel NetCDF del modello (list_model_variables(...) le elenca con le unita')
##   type   GAS oppure PM
##   unit   unita' di USCITA (quella nello startup); osservazioni e modello vengono convertite in questa
##   obs_factor, model_factor  (facoltative) fattore a mano; NA = conversione automatica dalle unita'
##                  ("Unit" dei parquet EEA, attributo "units" del NetCDF). Servono per ppb, mol/mol, ...
## Specie qui sotto: SO2, CO, NOX, NO2, O3, PM10, PM2.5, Pb, As, BaP, Cd, Ni, C6H6.
## DA VERIFICARE: la colonna `farm` (nomi delle variabili nei tuoi NetCDF: list_model_variables(...)),
## le unita' di uscita (CO in mg/m3 e metalli/BaP in ng/m3 e' una scelta mia) e il tipo GAS/PM dei metalli.
pollutants <- data.frame(
  delta = c("SO2",   "CO",    "NOX",        "NO2",   "O3",   "PM10",  "PM25",  "Pb",          "As",          "BaP",          "Cd",          "Ni",          "C6H6"),
  eea   = c("SO2",   "CO",    "NOX as NO2", "NO2",   "O3",   "PM10",  "PM2.5", "Pb in PM10",  "As in PM10",  "BaP in PM10",  "Cd in PM10",  "Ni in PM10",  "C6H6"),
  farm  = c("SO2",   "CO",    "NOX",        "NO2",   "O3",   "PM10",  "PM25",  "Pb",          "As",          "BaP",          "Cd",          "Ni",          "C6H6"),
  type  = c("GAS",   "GAS",   "GAS",        "GAS",   "GAS",  "PM",    "PM",    "PM",          "PM",          "PM",           "PM",          "PM",          "GAS"),
  unit  = c("ugm-3", "mgm-3", "ugm-3",      "ugm-3", "ugm-3", "ugm-3", "ugm-3", "ugm-3",       "ngm-3",       "ngm-3",        "ngm-3",       "ugm-3",       "ugm-3"),
  obs_factor   = NA_real_,
  model_factor = NA_real_,
  stringsAsFactors = FALSE
)

## Selezione: quali specie della tabella preparare in questa esecuzione (nomi della colonna `delta`).
## NULL = tutte. NOX e' nella tabella ma DELTA online NON lo riconosce (KeyError 'NOX' al caricamento),
## quindi per l'input DELTA va escluso con questa selezione.
species <- c("SO2", "CO", "NO2", "O3", "PM10", "PM25", "Pb", "As", "BaP", "Cd", "Ni", "C6H6")

## --- Uscita e periodo
out_dir      <- "output"                     # cartella base
out_label    <- NULL                         # sottocartella: NULL = "<anno>[_<model_version>][_<specie>][_<periodo>]"; "" = scrivi in out_dir
                                             # startup.ini, obs/ e mod/ finiscono in out_dir/out_label/
startup_name <- "startup.ini"
discarded_name <- "stazioni_scartate.csv"    # rapporto delle stazioni scartate (EoI, comune, provincia, motivo)
warnings_name  <- "avvisi.txt"               # tutti gli avvisi, per esteso
year         <- 2023
# period     <- NULL                         # NULL = anno intero
period       <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),    # test rapido su 2 giorni
                  as.POSIXct("2023-01-02 23:00", tz = "UTC"))
scale        <- "urban"                      # [MODEL] Scale nello startup
valid_codes  <- c(1L)                        # codici "Validity" EEA accettati: 1 = solo valido; c(1L, 2L, 3L) include
                                             # anche i validi sotto il limite di rilevabilita' (2 e 3)
min_coverage <- 0.75                         # copertura minima: frazione di ore valide nel periodo per ogni
                                             # sampling point (stazione + inquinante); sotto soglia e' scartato
eol          <- "\n"                         # fine riga dei file scritti

## --- Fusi orari (ore rispetto a UTC: 1 = UTC+1, 0 = UTC)
tz_offset       <- 1                         # fuso di TUTTI i file in uscita
obs_tz_offset   <- NULL                      # NULL = dalla colonna Timezone dei metadati EEA
model_tz_offset <- 1                         # fuso dei tempi nei NetCDF del modello
gmt_lag         <- NULL                      # NULL = "UTC" se tz_offset = 0, altrimenti "UTC+1", ...
obs_hour_label  <- "end"                     # ora a cui va il dato orario delle osservazioni: "start" = inizio ora (PMSS);
                                             # "end" = fine ora (FARM: tempi = istanti a fine ora). Obs e modello devono avere la stessa convenzione
model_shift_h   <- 0                         # ore da sommare al tempo di griglia (convenzione oraria)

## =============================== ESECUZIONE ==================================

res <- build_delta_inputs(
  obs_dir = obs_dir, obs_pattern = obs_pattern, meta_csv = meta_csv,
  model_dir = model_dir, model_pattern = model_pattern, model_version = model_version,
  istat_dir = istat_dir, istat_year = istat_year, istat_max_dist_m = istat_max_dist_m,
  comune_col = comune_col, region_col = region_col,
  province_col = province_col, province_abbr_col = province_abbr_col,
  pollutants = pollutants, species = species,
  out_dir = out_dir, out_label = out_label, startup_name = startup_name, discarded_name = discarded_name,
  warnings_name = warnings_name, year = year, period = period,
  scale = scale, valid_codes = valid_codes, min_coverage = min_coverage, eol = eol,
  model_grid = model_grid, model_x_dim = model_x_dim, model_y_dim = model_y_dim,
  model_time_dim = model_time_dim, utm_lon0 = utm_lon0,
  tz_offset = tz_offset, obs_tz_offset = obs_tz_offset, model_tz_offset = model_tz_offset,
  gmt_lag = gmt_lag, model_shift_h = model_shift_h, model_interp = model_interp, obs_hour_label = obs_hour_label
)
print(res$stations)
