# Confronto tra due cartelle di input DELTA (ciascuna con obs/ e mod/): stessi nomi di file,
# colonne degli inquinanti abbinate PER NOME (la posizione non conta), ore abbinate per
# year/month/day/hour. Solo R base. Lancia dalla cartella principale del progetto:
#   Rscript tools/compare_outputs.R
# Tutti i parametri sono qui sotto.

## ============================== PARAMETRI ====================================
dir_a   <- "output/2023_codice_mio"       # cartella con obs/ e mod/ (es. il tuo codice)
dir_b   <- "output/2023"                  # cartella con obs/ e mod/ (es. questo pacchetto)
kinds   <- c("obs", "mod")                # sottocartelle da confrontare
missing_value <- -999                     # valore che indica "dato mancante"
tol     <- 0.01                           # differenza assoluta oltre la quale un'ora e' "diversa"
# Nomi delle specie in A -> nomi in B, se diversi (es. i nomi canonici di DELTA). c() = nessuna.
name_map <- c(lead = "Pb", arsenic = "As", bap = "BaP", cadmium = "Cd", nickel = "Ni", benzene = "C6H6")
out_csv <- "confronto_output.csv"         # tabella completa: una riga per file e specie
hours_csv <- "confronto_ore.csv"          # una riga per ogni ora diversa (kind, file, specie, ora, valore A, valore B)
top_n   <- 20                             # righe peggiori mostrate a schermo
## =============================================================================

read_one <- function(path) {
  d <- utils::read.csv(path, sep = ";", check.names = FALSE, stringsAsFactors = FALSE)
  if (!all(c("year", "month", "day", "hour") %in% names(d))) stop("Mancano year/month/day/hour: ", path)
  d$key <- sprintf("%04d-%02d-%02d-%02d", d$year, d$month, d$day, d$hour)
  for (cn in setdiff(names(d), c("year", "month", "day", "hour", "key"))) {
    d[[cn]] <- suppressWarnings(as.numeric(d[[cn]]))
    d[[cn]][d[[cn]] %in% missing_value] <- NA
  }
  d
}

rows <- list()
hrs <- list()
only <- data.frame(kind = character(), file = character(), where = character(), stringsAsFactors = FALSE)
for (k in kinds) {
  fa <- list.files(file.path(dir_a, k), pattern = "\\.csv$")
  fb <- list.files(file.path(dir_b, k), pattern = "\\.csv$")
  for (f in setdiff(fa, fb)) only[nrow(only) + 1, ] <- c(k, f, "solo in A")
  for (f in setdiff(fb, fa)) only[nrow(only) + 1, ] <- c(k, f, "solo in B")
  for (f in intersect(fa, fb)) {
    a <- read_one(file.path(dir_a, k, f)); b <- read_one(file.path(dir_b, k, f))
    sa <- setdiff(names(a), c("year", "month", "day", "hour", "key"))
    sb <- setdiff(names(b), c("year", "month", "day", "hour", "key"))
    nm <- ifelse(sa %in% names(name_map), name_map[sa], sa)     # nome di A espresso con il nome di B
    for (s in setdiff(nm, sb)) only[nrow(only) + 1, ] <- c(k, f, paste0("specie ", s, " solo in A"))
    for (s in setdiff(sb, nm)) only[nrow(only) + 1, ] <- c(k, f, paste0("specie ", s, " solo in B"))
    for (i in which(nm %in% sb)) {
      va <- a[[sa[i]]]; names(va) <- a$key
      vb <- b[[nm[i]]]; names(vb) <- b$key
      common <- intersect(names(va), names(vb))
      x <- va[common]; y <- vb[common]
      both <- !is.na(x) & !is.na(y)
      d <- x[both] - y[both]
      dif <- (both & abs(x - y) > tol) | xor(is.na(x), is.na(y))
      dif[is.na(dif)] <- FALSE
      if (any(dif)) hrs[[length(hrs) + 1]] <- data.frame(kind = k, file = sub("\\.csv$", "", f), species = nm[i],
        hour = common[dif], A = x[dif], B = y[dif], stringsAsFactors = FALSE)
      rows[[length(rows) + 1]] <- data.frame(
        kind = k, file = sub("\\.csv$", "", f), species = nm[i],
        hours_common = length(common), hours_only_A = length(setdiff(names(va), names(vb))),
        hours_only_B = length(setdiff(names(vb), names(va))),
        valid_both = sum(both), missing_only_in_A = sum(is.na(x) & !is.na(y)),
        missing_only_in_B = sum(!is.na(x) & is.na(y)),
        hours_diff = sum(abs(d) > tol), max_abs_diff = if (length(d)) max(abs(d)) else NA_real_,
        mean_diff_AminusB = if (length(d)) mean(d) else NA_real_, stringsAsFactors = FALSE)
    }
  }
}
res <- if (length(rows)) do.call(rbind, rows) else data.frame()
if (nrow(res)) {
  res$bad <- res$hours_diff + res$missing_only_in_A + res$missing_only_in_B + res$hours_only_A + res$hours_only_B
  res <- res[order(-res$bad, -res$max_abs_diff), ]
  utils::write.csv(res, out_csv, row.names = FALSE, na = "")
}
dh <- if (length(hrs)) do.call(rbind, hrs) else data.frame()
if (nrow(dh)) utils::write.csv(dh, hours_csv, row.names = FALSE, na = "")
cat("\n===== CONFRONTO ", dir_a, " (A) con ", dir_b, " (B) =====\n", sep = "")
if (nrow(only)) {
  cat("File o specie presenti solo da una parte: ", nrow(only), "\n", sep = "")
  print(utils::head(only, top_n), row.names = FALSE)
}
if (!nrow(res)) {
  cat("Nessun file in comune da confrontare.\n")
} else {
  cat("File x specie confrontati: ", nrow(res), " (", length(unique(paste(res$kind, res$file))), " file)\n", sep = "")
  for (k in unique(res$kind)) {
    r <- res[res$kind == k, ]
    cat(sprintf("[%s] identici: %d | con differenze: %d | max differenza assoluta: %.4g\n", k,
                sum(r$bad == 0), sum(r$bad > 0), suppressWarnings(max(r$max_abs_diff, na.rm = TRUE))))
  }
  cat("\nPeggiori (A-B = differenza media sulle ore valide in entrambi):\n")
  print(utils::head(res[res$bad > 0, c("kind", "file", "species", "hours_diff", "missing_only_in_A",
                                         "missing_only_in_B", "hours_only_A", "hours_only_B", "max_abs_diff",
                                         "mean_diff_AminusB")], top_n), row.names = FALSE)
  if (all(res$bad == 0)) cat("Tutte le serie coincidono (tolleranza ", tol, ").\n", sep = "")
  if (nrow(dh)) {
    cat("\nGiorni con piu' ore diverse (kind, giorno, n. ore diverse, n. serie coinvolte):\n")
    dh$day <- substr(dh$hour, 1, 10)
    tb <- stats::aggregate(file ~ kind + day, data = dh, FUN = length); names(tb)[3] <- "ore"
    ns <- stats::aggregate(paste(file, species) ~ kind + day, data = dh, FUN = function(z) length(unique(z))); tb$serie <- ns[[3]]
    print(utils::head(tb[order(-tb$ore), ], 10), row.names = FALSE)
    cat("Elenco delle ore diverse: ", hours_csv, "\n", sep = "")
  }
  cat("Tabella completa: ", out_csv, "\n", sep = "")
}
