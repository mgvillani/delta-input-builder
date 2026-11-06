# Conversione lon/lat (WGS84) -> UTM, serie di Krueger al 4o ordine.
# Per FARM sull'Italia i punti griglia sono in UTM fuso 32N "esteso"
# (meridiano centrale 9 E, easting fino a ~1400 km), quindi lon0 = 9 anche per
# stazioni fuori dal fuso 32.
lonlat_to_utm <- function(lon, lat, lon0 = 9, k0 = 0.9996, e0 = 500000) {
  a <- 6378137
  f <- 1 / 298.257223563
  n <- f / (2 - f)
  A <- a / (1 + n) * (1 + n^2 / 4 + n^4 / 64)
  alpha <- c(
    n / 2 - 2 * n^2 / 3 + 5 * n^3 / 16 + 41 * n^4 / 180,
    13 * n^2 / 48 - 3 * n^3 / 5 + 557 * n^4 / 1440,
    61 * n^3 / 240 - 103 * n^4 / 140,
    49561 * n^4 / 161280
  )
  phi <- lat * pi / 180
  dl <- (lon - lon0) * pi / 180
  c2n <- 2 * sqrt(n) / (1 + n)
  t <- sinh(atanh(sin(phi)) - c2n * atanh(c2n * sin(phi)))
  xi0 <- atan2(t, cos(dl))
  eta0 <- atanh(sin(dl) / sqrt(1 + t^2))
  xi <- xi0
  eta <- eta0
  for (j in 1:4) {
    xi <- xi + alpha[j] * sin(2 * j * xi0) * cosh(2 * j * eta0)
    eta <- eta + alpha[j] * cos(2 * j * xi0) * sinh(2 * j * eta0)
  }
  list(x = e0 + k0 * A * eta, y = k0 * A * xi)
}
