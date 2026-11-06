# Controlla quali ore di un periodo NON sono coperte dai NetCDF del modello (e quali sono ripetute).
# Solo ncdf4. Lancia dalla cartella principale del progetto:   Rscript tools/check_model_time.R
# Parametri qui sotto (gli stessi di run_example.R).

## ============================== PARAMETRI ====================================
model_dir      <- "dati/farm"
model_pattern  <- "^conc_.*\\.nc$"
model_version  <- NULL                    # testo che il nome deve contenere, o NULL
model_time_dim <- "time"
model_tz_offset <- 1                      # fuso dei tempi nei NetCDF (ore rispetto a UTC)
tz_offset      <- 1                       # fuso di uscita
model_shift_h  <- 0
period <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),   # periodo da controllare (orologio nel fuso di uscita)
            as.POSIXct("2023-12-31 23:00", tz = "UTC"))
## =============================================================================

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
files <- farm_files(model_dir, model_pattern, model_version)
tm <- list(); nsteps <- integer(length(files))
for (i in seq_along(files)) {
  nc <- ncdf4::nc_open(files[i])
  t <- .cf_hours_to_posix(as.numeric(nc$dim[[model_time_dim]]$vals), nc$dim[[model_time_dim]]$units)
  ncdf4::nc_close(nc)
  tm[[i]] <- t; nsteps[i] <- length(t)
}
mt <- do.call(c, tm) + (tz_offset - model_tz_offset) * 3600
grid <- seq(period[1], period[2], by = "hour")
need <- grid + model_shift_h * 3600
miss <- grid[!as.numeric(need) %in% as.numeric(mt)]
cat("\n===== ORE DEL MODELLO =====\n")
cat("File letti:", length(files), "| passi per file:", paste(names(table(nsteps)), table(nsteps), sep = " x ", collapse = ", "), "\n")
cat("Ore richieste:", length(grid), "| senza modellato:", length(miss), "\n")
if (length(miss)) {
  print(data.frame(ora = format(miss, "%Y-%m-%d %H:00", tz = "UTC")), row.names = FALSE)
  # file piu' vicini a ciascuna ora mancante
  cat("\nFile con meno passi del solito:\n")
  usual <- as.integer(names(which.max(table(nsteps))))
  odd <- which(nsteps != usual)
  if (length(odd)) print(data.frame(file = basename(files[odd]), passi = nsteps[odd]), row.names = FALSE) else cat("nessuno\n")
}
dup <- format(mt[duplicated(as.numeric(mt))], "%Y-%m-%d %H:00", tz = "UTC")
cat("\nOre ripetute tra file (normale: l'ora 00 del giorno dopo):", length(dup), "\n")
