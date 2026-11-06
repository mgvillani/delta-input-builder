# Pulizia dei nomi per lo startup.ini: ASCII, nomi originali con spazi e "/"
# ("Albiano d'Ivrea", "Reggio nell'Emilia"); accenti traslitterati ("Aglié" -> "Aglie").
# Le sostituzioni sono scritte con escape \u per non dipendere dalla codifica
# del file sorgente.
.ACCENT_MAP <- c(
  "à" = "a", "á" = "a", "â" = "a", "ä" = "a", "ã" = "a",
  "è" = "e", "é" = "e", "ê" = "e", "ë" = "e",
  "ì" = "i", "í" = "i", "î" = "i", "ï" = "i",
  "ò" = "o", "ó" = "o", "ô" = "o", "ö" = "o", "õ" = "o",
  "ù" = "u", "ú" = "u", "û" = "u", "ü" = "u",
  "ý" = "y", "ÿ" = "y", "ç" = "c", "ñ" = "n", "ß" = "ss",
  "À" = "A", "Á" = "A", "Â" = "A", "Ä" = "A", "Ã" = "A",
  "È" = "E", "É" = "E", "Ê" = "E", "Ë" = "E",
  "Ì" = "I", "Í" = "I", "Î" = "I", "Ï" = "I",
  "Ò" = "O", "Ó" = "O", "Ô" = "O", "Ö" = "O", "Õ" = "O",
  "Ù" = "U", "Ú" = "U", "Û" = "U", "Ü" = "U",
  "Ý" = "Y", "Ç" = "C", "Ñ" = "N"
)

.ACCENT_CP <- vapply(names(.ACCENT_MAP), utf8ToInt, integer(1), USE.NAMES = FALSE)

# Lavora sui codepoint Unicode (utf8ToInt), quindi non dipende dal locale della
# sessione (C, UTF-8, codepage Windows). Caratteri non mappati -> separatore.
.fold_ascii <- function(s) {
  cp <- utf8ToInt(s)
  if (!length(cp)) return("")
  out <- character(length(cp))
  ascii <- cp < 128L
  out[ascii] <- vapply(cp[ascii], intToUtf8, character(1))
  hit <- match(cp[!ascii], .ACCENT_CP)
  out[!ascii] <- ifelse(is.na(hit), " ", unname(.ACCENT_MAP)[hit])
  paste(out, collapse = "")
}

# Nomi leggibili (Region, Siting): si rispettano i nomi originali, spazi e "/" compresi.
# Accenti traslitterati, caratteri non ASCII non mappati e separatori dello startup
# (";" "*") o altri caratteri problematici sostituiti da uno spazio; spazi multipli
# ridotti. Restano lettere, cifre, spazio, "/", "-", "'", "." e ",".
clean_name <- function(x, empty = "NA") {
  x <- enc2utf8(as.character(x))
  x[is.na(x)] <- ""
  x <- vapply(x, .fold_ascii, character(1), USE.NAMES = FALSE)
  x <- gsub("[^A-Za-z0-9 /'.,-]", " ", x)
  x <- trimws(gsub("[ \t]+", " ", x))
  x[!nzchar(x)] <- empty
  x
}
