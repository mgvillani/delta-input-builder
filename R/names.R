# Name cleaning for startup.ini: ASCII, original names with spaces and "/"
# ("Albiano d'Ivrea", "Reggio nell'Emilia"); accents transliterated ("Aglié" -> "Aglie").
# The accented letters are mapped by Unicode code point, so the result does not depend on
# the encoding of the source file.
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

# Works on Unicode code points (utf8ToInt), so it does not depend on the session
# locale (C, UTF-8, Windows codepage). Unmapped characters -> separator.
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

# Readable names (Region, Siting): the original names are kept, spaces and "/" included.
# Accents are transliterated; unmapped non-ASCII characters, startup separators
# (";" "*") and other problematic characters are replaced by a space; repeated spaces
# are collapsed. Letters, digits, space, "/", "-", "'", "." and "," are kept.
clean_name <- function(x, empty = "NA") {
  x <- enc2utf8(as.character(x))
  x[is.na(x)] <- ""
  x <- vapply(x, .fold_ascii, character(1), USE.NAMES = FALSE)
  x <- gsub("[^A-Za-z0-9 /'.,-]", " ", x)
  x <- trimws(gsub("[ \t]+", " ", x))
  x[!nzchar(x)] <- empty
  x
}
