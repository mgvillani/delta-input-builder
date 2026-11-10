# Checks which hours of a period are NOT covered by the model NetCDF files (and which are repeated).
# Only ncdf4. Run from the main folder of the project:   Rscript tools/check_model_time.R
# Parameters below (the same as in run_example.R).

## ============================== PARAMETERS ===================================
model_dir      <- "data/farm"
model_pattern  <- "^conc_.*\\.nc$"
model_version  <- NULL                    # text the name must contain, or NULL
model_time_dim <- "time"
model_tz_offset <- 1                      # time zone of the times in the NetCDF files (hours from UTC)
tz_offset      <- 1                       # output time zone
model_shift_h  <- 0
period <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),   # period to check (wall-clock time in the output zone)
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
cat("\n===== MODEL HOURS =====\n")
cat("Files read:", length(files), "| steps per file:", paste(names(table(nsteps)), table(nsteps), sep = " x ", collapse = ", "), "\n")
cat("Hours requested:", length(grid), "| without model data:", length(miss), "\n")
if (length(miss)) {
  print(data.frame(hour = format(miss, "%Y-%m-%d %H:00", tz = "UTC")), row.names = FALSE)
  cat("\nFiles with fewer steps than usual:\n")
  usual <- as.integer(names(which.max(table(nsteps))))
  odd <- which(nsteps != usual)
  if (length(odd)) print(data.frame(file = basename(files[odd]), steps = nsteps[odd]), row.names = FALSE) else cat("none\n")
}
dup <- format(mt[duplicated(as.numeric(mt))], "%Y-%m-%d %H:00", tz = "UTC")
cat("\nHours repeated between files (normal: hour 00 of the next day):", length(dup), "\n")
