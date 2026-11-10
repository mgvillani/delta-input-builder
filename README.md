# delta-input-FARM-builder

*Versione italiana: [README.it.md](README.it.md)*

An R tool that builds the **legacy-format inputs of the JRC DELTA Tool** from EEA observations and FARM model output.

**Input**

- EEA E1a hourly observations in parquet format (one file per sampling point);
- the EEA metadata CSV (`DataExtract.csv`);
- daily FARM NetCDF concentration files (e.g. `conc_IT0_YYYYMMDD.nc`);
- ISTAT administrative boundaries (**required**), used to write the region and municipality of each station.

**Output** (in a subfolder of `output/` named after the year, e.g. `output/2023/`; see below)

- `startup.ini`: the station list;
- `obs/<station>.csv`: observed data, one file per station;
- `mod/<station>.csv`: modelled data in the grid cell of that station, with the **same file name** as in `obs/`.

> **Use at your own risk.** This software is provided "as is", without warranty of any kind and without support (see `LICENSE`, MIT). Users are solely responsible for the results: always check the outputs, as described in step 5, before using them in any assessment. The package was developed with the help of AI tools. It is not an official product of the JRC or of the DELTA Tool.

---

## Step-by-step instructions

### Step 1 - Put the data in the right folders

Download or clone this repository. Inside the `delta-input-builder` folder create a `data` folder (the name used by the example script) laid out like this:

```
delta-input-builder/
  R/                       (the code: do not edit)
  run_example.R            (the file you will edit)
  data/
    eea_parquet/           all the EEA observation .parquet files
    farm/                  all the FARM NetCDF files
    DataExtract.csv        EEA station metadata
    istat/                 folder for the ISTAT boundaries (REQUIRED)
      Limiti01012023.zip   one ISTAT zip per year, as downloaded
      Limiti01012024.zip
```

**ISTAT boundaries are required.** The script reads each station's region and municipality from them and stops with an error without them. Put the zip downloaded from ISTAT in `istat/` (no need to unzip it), or the already extracted folders (`Com01012023/`, `Reg01012023/`, ...). ISTAT publishes a new edition every year and the folder may contain as many as you like: the script uses the one **for `year`** (recognised from the date in the name, e.g. `Limiti01012023.zip` = 2023). If that year is missing it uses the latest earlier one (or, failing that, the oldest available) and prints a warning. Set `istat_year` to force another edition.

`data/` is already excluded by Git (see `.gitignore`, which also excludes `output/` and the data file types): data never ends up in the repository.

### Step 2 - Install the R packages (once)

```r
install.packages(c("ncdf4", "arrow", "sf"))
```

- `ncdf4` reads the FARM files;
- `arrow` reads the parquet files;
- `sf` reads the ISTAT boundaries.

Only base R is otherwise used (no tidyverse, dplyr or data.table). Tested with R 4.3.3, `ncdf4` 1.22, `sf` 1.0.15. On shared systems and HPC clusters `sf` is the hardest to install (it needs GDAL, GEOS and PROJ); installing R and the packages with conda/mamba (conda-forge: `r-base r-sf r-ncdf4 r-arrow`) avoids compiling them.

### Step 3 - Set the parameters in `run_example.R`

All parameters are set **in one place: the top of `run_example.R`**. The code in `R/` has no hidden values for file names, folders, time zones or pollutants. Every line is commented. The main blocks:

```r
## EEA observations
obs_dir     <- "data/eea_parquet"
obs_pattern <- "\\.parquet$"               # regex on the observation file names
meta_csv    <- "data/DataExtract.csv"

## Model (concentration files)
model_dir      <- "data/farm"
model_pattern  <- "^conc_.*\\.nc$"         # regex on the model file names
model_version  <- NULL                      # e.g. "g2": text the file name must contain
model_grid     <- "lonlat"                  # "utm" (x,y in km) or "lonlat" (degrees)
model_x_dim    <- "lon"                     # name of the x dimension in the NetCDF
model_y_dim    <- "lat"
model_time_dim <- "time"
utm_lon0       <- 9                         # only for model_grid = "utm"
model_interp   <- "bilinear"                # "nearest" or "bilinear"

## ISTAT boundaries (required)
istat_dir        <- "data/istat"
istat_year       <- NULL                    # NULL = edition of `year`
istat_max_dist_m <- 2000
comune_col       <- "COMUNE"
region_col       <- "DEN_REG"
province_col      <- "DEN_UTS"              # only for the discarded-stations report
province_abbr_col <- "SIGLA"

## Pollutants table, output, period, time zones ...
year      <- 2023
tz_offset <- 1                              # all output files in UTC+1 (0 = UTC)
```

Further down the same file, the call to `build_delta_inputs(...)` passes these values on: do not change it.

Check in particular:

- `year`: the year of your data;
- the paths: if you followed step 1 they are already right. On Windows always write `/`, never `\` (e.g. `"C:/Users/name/data/farm"`);
- `model_pattern` / `model_version`: choose which concentration files are read;
- `istat_dir`: the ISTAT folder of step 1. It cannot be removed;
- `tz_offset <- 1`: **all** output files are in UTC+1. Write `0` for UTC.

### Step 4 - First run on a few days

Before the whole year, try a short period to catch errors quickly. In `run_example.R` find `period` (`NULL` means the whole year) and replace it:

```r
period <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),
            as.POSIXct("2023-01-02 23:00", tz = "UTC"))
```

The hours of `period` are wall-clock hours in the time zone chosen with `tz_offset` (with `tz_offset <- 1`, UTC+1). `tz = "UTC"` is just a technical label: leave it as it is.

Then run the script from R/RStudio with the `delta-input-builder` folder as working directory:

```r
setwd("path/to/delta-input-builder")
source("run_example.R")
```

or from a terminal in the same folder: `Rscript run_example.R`.

### Step 5 - Check the results

1. **Warnings**: they are printed at the end in a `WARNINGS` block and saved in full in `warnings.txt` in the output folder (see "What appears on screen").
2. **Output folder** (e.g. `output/2023/`): it must contain `startup.ini`, `obs/` and `mod/`, with identical file names in `obs/` and `mod/`.
3. **Any file**: open it. The first line is `year;month;day;hour;NO2;PM10;...`. The value `-999` means "missing".
4. **Startup**: in `startup.ini` check that region, municipality and `GMTLag` are as expected.
5. **Quick comparison**, to see at once whether observations and model are shifted by some hours (change station and pollutant):

```r
o <- read.csv("output/2023/obs/IT0063Aa.csv", sep = ";")
m <- read.csv("output/2023/mod/IT0063Aa.csv", sep = ";")
o[o == -999] <- NA
plot(m$NO2, type = "l"); lines(o$NO2, col = "red")
```

### Step 6 - Run the whole year

Set `period <- NULL` (or delete/comment the `period` lines) and run again. You need the FARM files of every day of the year; for missing days the model values are written as `-999` and a warning gives the number of hours without model data. The whole year can be run as a single job (for example one SLURM job, no job array: a single `startup.ini` is produced).

### Step 7 - Use the files in DELTA

- **DELTA Tool Online**: upload `startup.ini`, then a zip with the files of `obs/` and a zip with the files of `mod/`.
- **DELTA Tool / DELTA Tool Light** (installed versions): follow the tool's guide for the folders where `startup.ini` and the CSV files go.

---

## Adopted conventions (accepted by DELTA Tool Online)

| Aspect | Choice |
|---|---|
| Time zone | everything in **fixed UTC+1** (no daylight saving); `GMTLag` = `UTC+1`; `tz_offset = 1` |
| Observation hour | the value of [Start, End) goes to the **end** hour (`obs_hour_label = "end"`), like FARM end-of-hour timestamps; `"start"` for PMSS-like conventions. To be checked with the model owners |
| Model | bilinear interpolation (`model_interp = "bilinear"`), like `raster::extract(..., method = "bilinear")` |
| Station Code | `<Nat Code><letter>`, e.g. `302006a` |
| Station Name | EoI code + letter, e.g. `IT0063Aa` |
| Region / Siting | original ISTAT names (spaces and `/` allowed), accents transliterated, `;` `*` `_` replaced by a space |
| Area / Station Type | as in the DataExtract (e.g. `rural-nearcity`) |
| Coordinates | all decimals |
| EEA validity | `Validity == 1` only (`valid_codes = 1L`) |
| Coverage | at least 75% valid hours per sampling point (`min_coverage = 0.75`) |
| Values | 2 decimals, `-999` for missing |
| Units | all pollutants in `ugm-3`, except CO (`mgm-3`) and As, BaP, Cd (`ngm-3`); conversions are automatic |

**Species**: SO2, CO, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6. **NOX is excluded**: DELTA does not support it (`KeyError: 'NOX'`). DELTA may rename species to its canonical names when it ingests the dataset.

---

## How the output files look

**Station CSV** (same layout in `obs/` and `mod/`):

```
year;month;day;hour;NO2;PM10
2023;1;1;0;-999;25.00
2023;1;1;1;10.00;25.00
```

One hour per row for the whole requested period, with only the pollutant columns of that station.

**File name and final letter.** The name is the EEA station code plus a letter (`IT0063A` becomes `IT0063Aa`). The letter changes when the same station measures the same pollutant with **several instruments** (several sampling points):

- `IT0469Aa`: NO2 and PM10 of the first instrument (the one with most valid data);
- `IT0469Ab`: PM10 only, from the second instrument.

It also changes when the records of the same station have different **coordinates, `Station Type` or `Area Type`** in `DataExtract.csv` (e.g. NO2 `background` and PM10 `industrial`): each combination is a separate file with the values of its own record. Letters are assigned by level (first instrument of each combination, then the second, ...) and, for ties, by total valid hours.

**Coverage threshold (`min_coverage`).** Minimum fraction of valid hours in the period for each sampling point (station + pollutant). With `0.75`, anything below 75% is discarded and appears in the discarded-stations report with its percentage. `0` keeps everything with at least one value. Two instruments for the same pollutant are evaluated separately.

**How EEA data are handled**

- Hourly data (`AggType` hour): the value is assigned according to `obs_hour_label` (see below).
- Daily (`day`) and variable-interval (`var`, e.g. benzene, Pb, Cd) data: the value is constant and is repeated on **every hour** of the interval, whatever its length.
- Invalid data become `-999`: value `-9999` or a `Validity` code not in `valid_codes`. `valid_codes <- c(1L)` accepts only "valid" data (1); `c(1L, 2L, 3L)` also includes data below the detection limit (2 and 3, frequent for SO2, CO, C6H6 and metals), which raise coverage and therefore the number of stations above `min_coverage`.

**How the model is taken.** The value in the station's position is obtained with `model_interp`: `"nearest"` (cell with the nearest centre) or `"bilinear"` (bilinear interpolation among the 4 surrounding cell centres; a point between the last centre and the grid edge uses the edge cells; if one of the cells is `NA` the result is `NA`, i.e. `-999`). Stations outside the model grid are discarded with a warning. If two daily files share hour 00, the most recent file wins.

## Station Code, Station Name and Station abbreviation must be unique

- **Station Name** and **Station abbreviation** are the file name (EoI code + letter, e.g. `IT0063Aa`): unique by construction.
- **Station Code** is the national `Nat Code` plus the letter (e.g. `1104213a`). In EEA data the same `Nat Code` can appear in two different EoI stations, so the code would no longer be unique: in that case the script appends the EoI code (`1205822aIT2258A`) and issues a warning.
- At the end the script checks that the three fields are unique (case-insensitively too, for Windows file names) and stops with an error otherwise.

## Several model versions and output folder name

Output does not go directly into `output/`: `startup.ini`, `obs/` and `mod/` are written in a **subfolder** of `out_dir` named `out_label`. With `out_label <- NULL` (automatic) the name is:

- `2023` (the year);
- `2023_d0` if `model_version <- "d0"`;
- `2023_d0_20230101-20230102` if you also set a `period` (so a short test does not overwrite the whole-year run).

Example with the same observations and three model versions in one folder (`conc_..._d0_...nc`, `..._d1_...`, `..._d2_...`): run the script three times changing only `model_version` (`"d0"`, `"d1"`, `"d2"`) to get `output/2023_d0/`, `output/2023_d1/`, `output/2023_d2/`. `model_version` is text searched in the file name: choose a specific one (e.g. `"_d1_"` rather than `"d1"`).

If `model_version <- NULL` and several versions are in the same folder, the files get mixed (the last in name order wins) and the script warns you. `out_label <- "my_name"` sets your own subfolder name; `""` writes directly into `out_dir`.

## Region and Siting

`startup.ini` needs region and municipality of every station. They are not in the EEA data: they are **always** derived from the ISTAT boundaries (`istat_dir`), from the station position.

- `Region` comes from `DEN_REG` of the region layer (`Reg*`);
- `Siting` comes from `COMUNE` of the municipality layer (`Com*`);
- if the column names of an ISTAT edition change, adapt `region_col` and `comune_col`;
- a coastal station just outside the polygons takes the nearest municipality if within `istat_max_dist_m` metres (2000 in the example); beyond that the station is **discarded** with a warning, since there is no fallback value.

Names keep their original ISTAT spelling, including spaces and `/` (e.g. `Valle d'Aosta/Vallee d'Aoste`, `Albiano d'Ivrea`), so that they read well and work on every system: accents are transliterated (`Aglié` becomes `Aglie`), `;`, `*`, `_` and other problematic characters are replaced by a space, and repeated spaces are collapsed.

## Station metadata: values as in the file

In `DataExtract.csv` each station has one record per pollutant and instrument, and sometimes records of the same station disagree (coordinates a few metres apart, different `Station Type` or `Area Type`). **Values stay as in the file**: each output file (`...a`, `...b`) reports in the startup the values of its own record (if it contains several pollutants, those of the first pollutant in the order of the `pollutants` table), and the model cell and municipality are those of that position. So the same station may appear in the startup with different coordinates, type or area between letters.

Only where a value is **missing** (empty cell) the value from the other records of the same station is used: the one supported by the most valid hours. The script prints the stations completed this way. If coordinates are missing and the station has no other record with coordinates, the file is discarded with a warning.

## Matching observations to DataExtract.csv

The sampling point of each parquet (`SPO.<EoI>_<code>_<method>_<date>`) is searched in `DataExtract.csv` in this order: same SPO; same SPP (Process Id); same station, code and method; same station and pollutant code; station only (species from the code). SPO and SPP of the same row may have different method and date, and an SPO may have several SPP: among candidate rows the one with fewer missing values wins, then the most recent SPP. Values stay as in the file; missing ones are completed from the same station (see above). If the match on the SPO is not exact you see it in the messages/warnings. A parquet with several sampling points is split, not skipped. Observations of non-selected species are ignored (message), not reported as "discarded". Only stations whose EoI code is not in `DataExtract.csv` are discarded.

## Time zones and hour convention

A single parameter, `tz_offset`, sets the time zone of **all** output files: observations, model, hours of `period` and the `GMTLag` column of the startup.

| Parameter | Meaning | Example value |
|---|---|---|
| `tz_offset` | time zone of the output files, hours from UTC | `1` (UTC+1) |
| `model_tz_offset` | time zone of the FARM NetCDF files | `1` |
| `obs_tz_offset` | time zone of the EEA hours; if `NULL`, the `Timezone` column of each station is used (UTC+01 in Italy) | `NULL` |
| `gmt_lag` | text of the `GMTLag` column; with `NULL` it is `UTC+1`, or `UTC` if `tz_offset = 0` | `NULL` (automatic) |

With the example values there is no offset: the code converts only if the zones differ. If your FARM files are in UTC, set `model_tz_offset = 0`.

EEA observations are naive local clock times in fixed UTC+1 (no daylight saving). If you compare with your own code, subtract one hour with `dhours(1)` or `- 3600`, not with lubridate's `hours(1)` on a POSIXct in `Europe/Rome`: that gives NA in March and a duplicated hour in October.

**`obs_hour_label`** is the hour a value covering the interval [`Start`, `End`) is assigned to: `"start"` = the starting hour (the 00:00-01:00 value goes to hour 0, as in PMSS); `"end"` = the end hour (it goes to hour 1, like FARM times, which are end-of-hour instants). Observations and model must use the same convention; alternatively shift the model with `model_shift_h`.

## Other useful parameters

| Parameter | Purpose |
|---|---|
| `scale` | value of the `[MODEL]` section of the startup (`"urban"` in the example) |
| `pollutants`, `species` | pollutant table (names and units, see below) and selection of the species prepared in this run (`NULL` = all) |
| `valid_codes`, `min_coverage` | accepted `Validity` codes and minimum coverage (see above) |
| `model_interp` | `"nearest"` or `"bilinear"` (see above) |
| `model_shift_h` | shifts the model by a number of hours with respect to observations: only if the two use different hour conventions |
| `obs_pattern`, `model_pattern` | regular expression on file names if yours are not `.parquet` / `conc_...nc`; e.g. `model_pattern = "^conc_IT0_.*\\.nc$"` |
| `model_grid`, `model_x_dim`, `model_y_dim`, `model_time_dim` | NetCDF grid type (`"utm"`: x,y in UTM km; `"lonlat"`: degrees) and dimension names. To see those of your file: `names(ncdf4::nc_open("file.nc")$dim)`. The order of the variable's dimensions does not matter; time may be in seconds, minutes, hours or days from the origin |
| `model_version` | text the concentration file name must contain, to choose a model version/run when several are in the folder; `NULL` = no filter. Combined with `model_pattern` |
| `out_label` | subfolder of `out_dir` for the output (see above) |
| `startup_name` | name of the startup file (`startup.ini`) |
| `discarded_name`, `warnings_name` | names of the report files in the output folder: discarded stations (`discarded_stations.csv`) and full warnings (`warnings.txt`) |

## Pollutants, names and units

You are not limited to NO2, O3, PM10, PM25: each pollutant is **a row** of the `pollutants` table in `run_example.R`, and you can add as many as you want. Three things matter for each row.

**1. Names.** There are three different names, to be written in the right columns:

| Column | Meaning | How to find it |
|---|---|---|
| `eea` | name in `Air Pollutant` of `DataExtract.csv`, identical (e.g. `PM2.5`, `C6H6`, `BaP in PM10`, `NOX as NO2`) | `list_eea_pollutants("data/DataExtract.csv")` lists all names with the number of sampling points |
| `farm` | variable name in the NetCDF (e.g. `PM25`) | `list_model_variables("data/farm", "^conc_.*\\.nc$", NULL)` lists variables, units and dimensions |
| `delta` | the name you want in the startup and CSV files | only letters and digits, starting with a letter: no spaces, `_`, `;`, `*`, `.` (e.g. `PM2.5` becomes `PM25`, `BaP in PM10` becomes `BaP`). The code stops if the name is invalid |

**Species selection.** The table may hold all the species you need (in the example: SO2, CO, NOX, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6) and in each run you choose which to prepare with `species`: `species <- c("NO2", "PM10")` prepares only those two, `species <- NULL` prepares all. A name that is not in the table stops the script with an error. With a selection, the automatic output folder name includes the species (e.g. `output/2023_NO2-PM10/`), so different selections do not overwrite each other. NOX stays in the table of the example but is excluded through `species`, as DELTA does not support it.

**Species without data.** You may leave all species in the table even if your parquet files do not contain all of them: those without observations produce nothing (they appear neither in the CSV files nor in `[PARAMETERS]` of the startup) and the script says so. Species without a NetCDF variable are discarded with a warning (without a model they cannot be validated).

**2. Units.** `unit` is the **output** unit written in the startup (e.g. `ugm-3`, `mgm-3`, `ngm-3`). Observations and model may have different units and are converted to `unit`:

- observations: the unit is in the `Unit` column of each EEA parquet (e.g. `ug.m-3`, `mg.m-3`, `ng.m-3`);
- model: the unit is in the `units` attribute of the NetCDF variable (e.g. `ug/m3`, `ug m-3`, `ng/m3`).

Conversion is **automatic** for mass-per-m3 units (kg, g, mg, ug, ng, pg; also `µg`); the screen shows what was done for each species. For unrecognised units (ppb, ppm, mol/mol, ...) the code **stops** with an error, because conversion depends on molecular mass, temperature and pressure: write the factor yourself in the optional `obs_factor` (observations) and `model_factor` (model) columns. `NA` means "automatic". If the NetCDF has no `units` attribute the code stops and asks for `model_factor`.

**3. Type.** `type` is `GAS` or `PM` (written in the startup). For metals and polycyclic hydrocarbons in PM10, check with DELTA which value is right.

## What appears on screen

The script prints three kinds of lines. Example with synthetic test data:

```
ISTAT boundaries: edition 2023
Species: NO2, O3, PM10
Observation units PM10: ug.m-3 -> ugm-3
Observations: 4 files, 0 skipped, 4 sampling points with valid data in the period
Model units NO2 (c_NO2): ug/m3 -> ugm-3
Output in: output/2023_20230101-20230102
Done: 2 station files (1 EEA stations) for 48 hours, species: NO2, PM10
```

**1. Informational messages** (no action needed; they let you check that the script did what you expect):

| Line starts with | Meaning |
|---|---|
| `ISTAT boundaries: edition ...` | ISTAT edition used (that of `year`, or `istat_year`) |
| `Species: ...` | species that will be prepared |
| `Observation units ...` | unit found in the parquet files and output unit; the factor is shown if the conversion is not 1 |
| `Observations: N files, M skipped, K sampling points ...` | files read; "skipped" = sampling points not in `DataExtract.csv` (with a warning) or of non-selected species; last number = sampling points with at least one valid value in the period |
| `Missing metadata, filled in from the same station: ...` | stations with empty cells in `DataExtract.csv` completed from other records of the same station |
| `Model units ...` | NetCDF variable, its unit and the output unit |
| `Output in: ...` | folder where `startup.ini`, `obs/` and `mod/` were written |
| `Species without observations ...` | species in the table with no observed data: not written |
| `Done: ...` | final summary: files written, distinct EEA stations, hours per file, species written |

**2. Warnings** (`WARNINGS`): something was discarded or modified but the script went on. They are printed in full at the end and **all** saved in `warnings.txt` in the output folder. The most common:

| Warning starts with | Meaning |
|---|---|
| `Station not in the metadata, skipped` | that parquet's station EoI code is not in `DataExtract.csv`: not used |
| `Variables missing in the NetCDF files, species dropped` | the model has no variable for those species (`farm` column) |
| `Species with no sampling point in the EEA metadata` | the `eea` name does not exist in `DataExtract.csv` |
| `Files outside the FARM grid, dropped` | the station is outside the model domain |
| `Files more than ... m from any ISTAT municipality, dropped` | the station is in no municipality (threshold `istat_max_dist_m`) |
| `Files without coordinates in the metadata, dropped` | lon/lat empty and no other record of the station has them |
| `Duplicate Station Code ... EoI appended` | same `Nat Code` in two EoI stations: the EoI is appended |
| `N of M hours without model data: written as -999` | model files are missing for part of the period |
| `Many hours appear in several files ...` | several versions of the same period in the model folder: use `model_version` or `model_pattern` |
| `No ISTAT edition for ...: using edition ...` | the ISTAT edition of the requested year is missing |
| `AggType not handled, ignored` | EEA aggregation type other than `hour`, `day`, `var`: ignored |
| `Unit column missing in ...` | the parquet has no units: no conversion, set `obs_factor` if needed |
| `N sampling points matched by '...'` | the match in `DataExtract.csv` was not exact on the SPO (see "Matching observations to DataExtract.csv") |

**3. Discarded stations.** After the warnings a `DISCARDED STATIONS (n)` block lists each station (or sampling point) not written, with EoI code, the discarded item, station name, municipality, province and **reason**:

```
===== DISCARDED STATIONS (1) =====
 1. EoI IT9002A | IT9002Aa | station: TEST | municipality: Example Town | province: Example Province (EP)
      reason: outside the model grid
```

The same data are in `discarded_stations.csv` (separator `;`, columns `eoi`, `item`, `station_name`, `municipality`, `province`, `reason`) in the output folder. Possible reasons:

| Reason | When |
|---|---|
| `EoI code not in DataExtract.csv` | the station of the parquet is not in the metadata |
| `no valid data in the requested period` | the file exists but has no valid data in the period |
| `coverage X% of valid hours, below the Y% threshold` | coverage below `min_coverage` |
| `coordinates missing in DataExtract.csv` | lon/lat empty and no other record has them |
| `outside the model grid` | position outside the NetCDF domain |
| `more than ... m from any ISTAT municipality` | position in no ISTAT municipality |

**Municipality and province.** When the position is known, both come from the ISTAT boundaries (municipality from layer `Com*`, province from layer `ProvCM*`, with name and abbreviation). If the position falls outside every municipality, the municipality is that of `DataExtract.csv` (column `Municipality`) marked `[EEA]`, and the province is `-`. The province layer is **optional**: if missing from the ISTAT zip the province is always `-`. Column names are set with `province_col` (name, `DEN_UTS`; in old editions `DEN_PROV`) and `province_abbr_col` (`SIGLA`).

**4. Errors** stop the script; the text says what is missing. The most common ones:

| Message starts with | What to do |
|---|---|
| `The 'arrow' package is required` | `install.packages("arrow")` |
| `The 'sf' package is required` | `install.packages("sf")` |
| `The ISTAT boundaries folder (istat_dir) is required` | create the folder (e.g. `data/istat`) and set `istat_dir` |
| `No ISTAT boundaries in ...` / `... lack the layer Com*` (or `Reg*`) | put the full ISTAT boundaries zip in the folder |
| `Column 'COMUNE' missing in the ISTAT layer` | in that edition the column has another name: set `comune_col` / `region_col` (the message lists the columns present) |
| `No NetCDF files in ...` | wrong `model_dir`, or names different from `model_pattern` / `model_version` |
| `In the NetCDF '...' I cannot find the grid dimensions ...` | grid names differ: set `model_x_dim`, `model_y_dim`, `model_grid` (the message lists those present) |
| `No species has a variable in the NetCDF files` | variable names differ from the `farm` column (the message lists the variables present) |
| `No observation files in ...` | wrong `obs_dir` |
| `Unrecognised unit for ...` | the unit is not mass per m3 (e.g. ppb): set `obs_factor` / `model_factor` |
| `Invalid DELTA name` | the `delta` name has spaces or symbols: use only letters and digits |
| `The model does not cover the requested period` | no hour of `period` is in the model files: check `period`, `year`, `tz_offset` |
| `No valid observed data in the requested period` | no valid data in the period: check `period` and `year` |

## Notes on the data

- The model may lack some hours at the beginning of the year (e.g. 2023-01-01 00:00-03:00 when the first daily file starts at 04:00): they stay `-999`. `tools/check_model_time.R` lists the hours not covered by the model files.
- `tools/compare_outputs.R` compares two output folders (each with `obs/` and `mod/`): same file names, pollutant columns matched by name, hours matched by year/month/day/hour. It reports differing hours (above `tol`), hours missing on one side, maximum and mean difference, and writes `comparison_output.csv`. Use `tol = 0.0101` to ignore rounding of half-values.

## Tests

`Rscript tests/test_synthetic.R` from the repository root: uses only invented data and checks suffixes, time zones, `var` values, cleaned names, ISTAT boundaries, matching, coverage, interpolation and conventions. It needs `ncdf4` and `sf` and ends with `OK: all checks passed`. By default the synthetic data are temporary; to keep them (input and output) give a new folder: `Rscript tests/test_synthetic.R test_output`. The tests do not replace a check on real data.

## License

MIT, see `LICENSE`. Data and outputs (`*.nc`, `*.parquet`, `DataExtract.csv`, ISTAT boundaries, `output/`) are not part of the repository. See `CHANGELOG.md` for the version history.
