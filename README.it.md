# delta-input-FARM-builder

*English version: [README.md](README.md)*

Strumento in R che costruisce gli **input in formato legacy del DELTA Tool (JRC)** a partire da osservazioni EEA e dati del modello FARM.

**Cosa entra**

- le osservazioni orarie EEA E1a in formato parquet (un file per sampling point);
- il CSV EEA con i metadati delle stazioni (`DataExtract.csv`);
- i NetCDF giornalieri di concentrazione del modello FARM (es. `conc_IT0_AAAAMMGG.nc`);
- i limiti amministrativi ISTAT (**obbligatori**), usati per scrivere regione e comune di ogni stazione.

**Cosa esce** (in una sottocartella di `output/` che porta l'anno, es. `output/2023/`: vedi sotto)

- `startup.ini`: l'elenco delle stazioni;
- `obs/<stazione>.csv`: i dati osservati, un file per stazione;
- `mod/<stazione>.csv`: i dati del modello nella cella di quella stazione, con lo **stesso nome** dei file di `obs/`.

> **Uso a proprio rischio.** Il software è fornito "così com'è", senza garanzie di alcun tipo e senza supporto (vedi `LICENSE`, MIT). Chi lo usa è l'unico responsabile dei risultati: controlla sempre gli output, come descritto al passo 5, prima di usarli in qualsiasi valutazione. Il pacchetto è stato sviluppato con l'ausilio di strumenti di intelligenza artificiale. Non è un prodotto ufficiale del JRC né del DELTA Tool.
>
> I messaggi stampati dagli script (avvisi, rapporto delle stazioni scartate, errori) sono in **inglese**; le tabelle sotto ne spiegano il significato in italiano.

---

## Istruzioni passo per passo

### Passo 1 - Metti i dati nelle cartelle giuste

Scarica o clona questo repository. Dentro la cartella `delta-input-builder` crea una cartella `data` (il nome usato dallo script di esempio) organizzata così:

```
delta-input-builder/
  R/                       (il codice: non toccare)
  run_example.R            (il file che modificherai)
  data/
    eea_parquet/           tutti i file .parquet delle osservazioni EEA
    farm/                  tutti i file NetCDF FARM
    DataExtract.csv        metadati stazioni EEA
    istat/                 cartella dei limiti ISTAT (OBBLIGATORIA)
      Limiti01012023.zip   uno zip ISTAT per ogni anno, come lo scarichi
      Limiti01012024.zip
```

**I limiti ISTAT sono obbligatori.** Lo script legge regione e comune di ogni stazione da qui e senza di essi si ferma con un errore. Nella cartella `istat/` metti lo zip scaricato da ISTAT (non serve estrarlo) oppure le cartelle già estratte (`Com01012023/`, `Reg01012023/`, ...). ISTAT pubblica un'edizione ogni anno e la cartella può contenerne quante vuoi: lo script usa quella **dell'anno `year`** (la riconosce dalla data nel nome, es. `Limiti01012023.zip` = 2023). Se quell'anno non c'è, usa la più recente precedente (o, se non ce ne sono, la più vecchia disponibile) e te lo segnala con un avviso. Per forzare un'altra edizione imposta `istat_year`.

La cartella `data/` è già esclusa da Git (vedi `.gitignore`, che esclude anche `output/` e i tipi di file di dati): i dati non finiscono mai nel repository.

### Passo 2 - Installa i pacchetti R (una volta sola)

```r
install.packages(c("ncdf4", "arrow", "sf"))
```

- `ncdf4` legge i file FARM;
- `arrow` legge i file parquet;
- `sf` legge i limiti ISTAT.

Per il resto si usa solo R di base (niente tidyverse, dplyr o data.table). Provato con R 4.3.3, `ncdf4` 1.22, `sf` 1.0.15. Sui sistemi condivisi e sui cluster HPC `sf` è il pacchetto più difficile da installare (servono GDAL, GEOS e PROJ): installare R e i pacchetti con conda/mamba (conda-forge: `r-base r-sf r-ncdf4 r-arrow`) evita di compilarli.

### Passo 3 - Imposta i parametri in `run_example.R`

Tutti i parametri si impostano **in un solo posto: in alto in `run_example.R`**. Il codice in `R/` non ha valori nascosti per nomi di file, cartelle, fusi orari o inquinanti. Ogni riga è commentata. I blocchi principali:

```r
## Osservazioni EEA
obs_dir     <- "data/eea_parquet"
obs_pattern <- "\\.parquet$"               # regex sul nome dei file di osservazioni
meta_csv    <- "data/DataExtract.csv"

## Modello (file di concentrazione)
model_dir      <- "data/farm"
model_pattern  <- "^conc_.*\\.nc$"         # regex sul nome dei file del modello
model_version  <- NULL                      # es. "g2": testo che il nome deve contenere
model_grid     <- "lonlat"                  # "utm" (x,y in km) oppure "lonlat" (gradi)
model_x_dim    <- "lon"                     # nome della dimensione x nei NetCDF
model_y_dim    <- "lat"
model_time_dim <- "time"
utm_lon0       <- 9                         # solo per model_grid = "utm"
model_interp   <- "bilinear"                # "nearest" oppure "bilinear"

## Limiti ISTAT (obbligatori)
istat_dir        <- "data/istat"
istat_year       <- NULL                    # NULL = edizione dell'anno `year`
istat_max_dist_m <- 2000
comune_col       <- "COMUNE"
region_col       <- "DEN_REG"
province_col      <- "DEN_UTS"              # solo per il rapporto delle stazioni scartate
province_abbr_col <- "SIGLA"

## Tabella inquinanti, uscita, periodo, fusi orari ...
year      <- 2023
tz_offset <- 1                              # tutti i file in uscita in UTC+1 (0 = UTC)
```

Più in basso nello stesso file, la chiamata `build_delta_inputs(...)` passa questi valori: non va modificata.

Cosa controllare:

- `year`: l'anno dei tuoi dati;
- i percorsi: se hai seguito il passo 1 sono già giusti. Su Windows scrivi sempre `/` e non `\` (es. `"C:/Users/nome/data/farm"`);
- `model_pattern` e `model_version`: scelgono quali file di concentrazione leggere;
- `istat_dir`: la cartella dei limiti ISTAT del passo 1. Non si può togliere;
- `tz_offset <- 1`: **tutti** i file in uscita sono in UTC+1. Per avere UTC scrivi `0`.

### Passo 4 - Prima prova su pochi giorni

Prima dell'anno intero, prova su un periodo breve per vedere subito eventuali errori. In `run_example.R` cerca `period` (`NULL` = anno intero) e sostituiscilo:

```r
period <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),
            as.POSIXct("2023-01-02 23:00", tz = "UTC"))
```

Le ore di `period` sono ore "a muro" nel fuso scelto con `tz_offset` (con `tz_offset <- 1`, UTC+1). `tz = "UTC"` è solo un'etichetta tecnica: va lasciato così.

Poi esegui lo script da R o RStudio, con la cartella `delta-input-builder` come cartella di lavoro:

```r
setwd("percorso/della/cartella/delta-input-builder")
source("run_example.R")
```

oppure da terminale nella stessa cartella: `Rscript run_example.R`.

### Passo 5 - Controlla i risultati

1. **Avvisi**: compaiono alla fine in un blocco `WARNINGS` e sono salvati per esteso in `warnings.txt` nella cartella di output (vedi "Cosa compare a schermo").
2. **Cartella di output** (es. `output/2023/`): devono esserci `startup.ini`, `obs/` e `mod/`, con gli stessi nomi di file in `obs/` e `mod/`.
3. **Un file a caso**: aprilo. La prima riga è `year;month;day;hour;NO2;PM10;...`. Il valore `-999` significa "dato mancante".
4. **Startup**: in `startup.ini` controlla che regione, comune e `GMTLag` siano quelli attesi.
5. **Un confronto veloce**, per vedere subito se osservati e modellati sono sfasati di qualche ora (cambia nome stazione e inquinante):

```r
o <- read.csv("output/2023/obs/IT0063Aa.csv", sep = ";")
m <- read.csv("output/2023/mod/IT0063Aa.csv", sep = ";")
o[o == -999] <- NA
plot(m$NO2, type = "l"); lines(o$NO2, col = "red")
```

### Passo 6 - Lancia l'anno intero

Imposta `period <- NULL` (o cancella/commenta le righe di `period`) e rilancia. Servono i file FARM di tutti i giorni dell'anno: per i giorni mancanti i valori del modello sono scritti come `-999` e un avviso riporta il numero di ore senza modello. L'anno intero si può lanciare come un solo job (per esempio un job SLURM singolo, senza array: si produce un unico `startup.ini`).

### Passo 7 - Usa i file in DELTA

- **DELTA Tool Online**: carica `startup.ini`, poi uno zip con i file di `obs/` e uno zip con i file di `mod/`.
- **DELTA Tool / DELTA Tool Light** (versioni da installare): segui la guida del tool per le cartelle in cui copiare `startup.ini` e i CSV.

---

## Convenzioni adottate (accettate da DELTA Tool Online)

| Aspetto | Scelta |
|---|---|
| Fuso | tutto in **UTC+1 fisso** (niente ora legale); `GMTLag` = `UTC+1`; `tz_offset = 1` |
| Ora delle osservazioni | il valore di [Start, End) va all'ora **di fine** (`obs_hour_label = "end"`), come i timestamp FARM a fine ora; `"start"` per convenzioni tipo PMSS. Da verificare con chi gestisce il modello |
| Modello | interpolazione bilineare (`model_interp = "bilinear"`), come `raster::extract(..., method = "bilinear")` |
| Station Code | `<Nat Code><lettera>`, es. `302006a` |
| Station Name | codice EoI + lettera, es. `IT0063Aa` |
| Region / Siting | nomi ISTAT originali (spazi e `/` ammessi), accenti traslitterati, `;` `*` `_` sostituiti da spazio |
| Area / Station Type | come nel DataExtract (es. `rural-nearcity`) |
| Coordinate | tutti i decimali |
| Validità EEA | solo `Validity == 1` (`valid_codes = 1L`) |
| Copertura | almeno 75% di ore valide per sampling point (`min_coverage = 0.75`) |
| Valori | 2 decimali, `-999` per i mancanti |
| Unità | tutti gli inquinanti in `ugm-3`, tranne CO (`mgm-3`) e As, BaP, Cd (`ngm-3`); conversioni automatiche |

**Specie**: SO2, CO, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6. **NOX è escluso**: DELTA non lo supporta (`KeyError: 'NOX'`). DELTA può rinominare le specie con i suoi nomi canonici quando legge il dataset.

---

## Come sono fatti i file in uscita

**CSV di una stazione** (stesso formato in `obs/` e `mod/`):

```
year;month;day;hour;NO2;PM10
2023;1;1;0;-999;25.00
2023;1;1;1;10.00;25.00
```

Un'ora per riga, per tutto il periodo richiesto, con le sole colonne degli inquinanti di quella stazione.

**Nome del file e lettera finale.** Il nome è il codice EEA della stazione più una lettera (`IT0063A` diventa `IT0063Aa`). La lettera cambia quando la stessa stazione misura lo stesso inquinante con **più strumenti** (più sampling point):

- `IT0469Aa`: NO2 e PM10 del primo strumento (quello con più dati validi);
- `IT0469Ab`: solo il PM10 del secondo strumento.

La lettera cambia anche quando i record della stessa stazione hanno **coordinate, `Station Type` o `Area Type` diversi** nel `DataExtract.csv` (per esempio NO2 `background` e PM10 `industrial`): ogni combinazione è un file a sé, con i valori del suo record. Le lettere si assegnano per livello (primo strumento di ogni combinazione, poi il secondo, ...) e, a parità, per ore valide totali.

**Soglia di copertura (`min_coverage`).** Frazione minima di ore valide nel periodo per ogni sampling point (stazione + inquinante). Con `0.75`, chi ha meno del 75% è scartato e compare nel rapporto delle stazioni scartate con la sua percentuale. `0` tiene tutto ciò che ha almeno un dato. Due strumenti dello stesso inquinante sono valutati separatamente.

**Come vengono trattati i dati EEA**

- Dati orari (`AggType` hour): il valore è assegnato secondo `obs_hour_label` (vedi sotto).
- Dati giornalieri (`day`) e a intervallo variabile (`var`, per esempio benzene, Pb, Cd): il valore è costante e viene ripetuto su **ogni ora** dell'intervallo, qualunque ne sia la lunghezza.
- Dati non validi diventano `-999`: valore `-9999` o codice `Validity` non presente in `valid_codes`. `valid_codes <- c(1L)` accetta solo i dati "validi" (1); `c(1L, 2L, 3L)` include anche i dati sotto il limite di rilevabilità (2 e 3, frequenti per SO2, CO, C6H6 e metalli), che alzano la copertura e quindi il numero di stazioni sopra `min_coverage`.

**Come viene preso il modello.** Il valore nella posizione della stazione si ottiene con `model_interp`: `"nearest"` (cella con il centro più vicino) oppure `"bilinear"` (interpolazione bilineare tra i centri delle 4 celle intorno; un punto tra l'ultimo centro e il bordo della griglia usa le celle di bordo; se una delle celle è `NA` il risultato è `NA`, cioè `-999`). Le stazioni fuori dalla griglia sono scartate con un avviso. Se due file giornalieri hanno in comune l'ora 00, vince il file più recente.

## Station Code, Station Name e Station abbreviation: devono essere unici

- **Station Name** e **Station abbreviation** sono il nome del file (codice EoI + lettera, es. `IT0063Aa`): unici per costruzione.
- **Station Code** è il `Nat Code` nazionale più la lettera (es. `1104213a`). Nei dati EEA lo stesso `Nat Code` può comparire in due stazioni EoI diverse, e il codice non sarebbe più unico: in quel caso lo script aggiunge il codice EoI (`1205822aIT2258A`) e lo segnala con un avviso.
- Alla fine controlla che i tre campi siano unici (anche senza distinguere maiuscole e minuscole, per i nomi dei file su Windows) e si ferma con un errore se non lo sono.

## Più versioni del modello e nome della cartella di output

L'output non va direttamente in `output/`: `startup.ini`, `obs/` e `mod/` si scrivono in una **sottocartella** di `out_dir`, il cui nome è `out_label`. Con `out_label <- NULL` (automatico) il nome è:

- `2023` (l'anno);
- `2023_d0` se imposti `model_version <- "d0"`;
- `2023_d0_20230101-20230102` se imposti anche un `period` (così una prova breve non sovrascrive l'anno intero).

Esempio con le stesse osservazioni e tre versioni del modello nella stessa cartella (`conc_..._d0_...nc`, `..._d1_...`, `..._d2_...`): lancia lo script tre volte cambiando solo `model_version` (`"d0"`, `"d1"`, `"d2"`) e ottieni `output/2023_d0/`, `output/2023_d1/`, `output/2023_d2/`. `model_version` è un testo cercato nel nome del file: scegline uno specifico (per esempio `"_d1_"` e non `"d1"`).

Se lasci `model_version <- NULL` con più versioni nella stessa cartella, i file si mescolano (vince l'ultimo in ordine di nome) e lo script lo segnala con un avviso. Con `out_label <- "mio_nome"` scegli tu il nome della sottocartella, con `""` scrivi direttamente in `out_dir`.

## Region e Siting

Nello `startup.ini` servono regione e comune di ogni stazione. Non sono nei dati EEA: si ricavano **sempre** dai limiti ISTAT (`istat_dir`), in base alla posizione della stazione.

- `Region` viene da `DEN_REG` del layer delle regioni (`Reg*`);
- `Siting` viene da `COMUNE` del layer dei comuni (`Com*`);
- se i nomi delle colonne di un'edizione ISTAT cambiano, si adattano con `region_col` e `comune_col`;
- una stazione sulla costa, appena fuori dai poligoni, prende il comune più vicino se è entro `istat_max_dist_m` metri (2000 nell'esempio); oltre, la stazione è **scartata** con un avviso, perché non esiste un valore di ripiego.

I nomi mantengono la grafia ISTAT originale, spazi e `/` compresi (es. `Valle d'Aosta/Vallee d'Aoste`, `Albiano d'Ivrea`), perché siano leggibili e funzionino su tutti i sistemi: gli accenti sono traslitterati (`Aglié` diventa `Aglie`), `;`, `*`, `_` e gli altri caratteri problematici sono sostituiti da uno spazio e gli spazi multipli sono ridotti a uno.

## Metadati della stazione: valori come nel file

Nel `DataExtract.csv` ogni stazione ha un record per inquinante e strumento, e a volte i record della stessa stazione hanno valori diversi (coordinate che differiscono di pochi metri, `Station Type` o `Area Type` diversi). **I valori restano quelli del file**: ogni file di uscita (`...a`, `...b`) riporta nello startup i valori del proprio record (se contiene più inquinanti, quelli del primo inquinante nell'ordine della tabella `pollutants`) e anche la cella del modello e il comune sono quelli di quella posizione. Quindi la stessa stazione può comparire nello startup con coordinate, tipo o area diversi tra una lettera e l'altra.

Solo quando un dato **manca** (cella vuota) si usa il valore degli altri record della stessa stazione: quello sostenuto da più ore di dati validi. Lo script scrive a video le stazioni completate così. Se mancano le coordinate e la stazione non ha altri record con coordinate, il file è scartato con un avviso.

## Abbinamento osservazioni ↔ DataExtract.csv

Il sampling point di ogni parquet (`SPO.<EoI>_<codice>_<metodo>_<data>`) viene cercato nel `DataExtract.csv` in quest'ordine: stesso SPO; stesso SPP (Process Id); stessa stazione, codice e metodo; stessa stazione e codice inquinante; solo la stazione (specie dal codice). SPO e SPP della stessa riga possono avere metodo e data diversi, e un SPO può avere più SPP: tra le righe candidate vince quella con meno dati mancanti, poi l'SPP più recente. I valori restano quelli del file; quelli mancanti sono completati con la stessa stazione (vedi sopra). Se l'abbinamento non è esatto sull'SPO, lo vedi tra i messaggi/avvisi. Un parquet con più sampling point viene diviso, non saltato. Le osservazioni di specie non selezionate sono ignorate (messaggio), non indicate come "scartate". Sono scartate solo le stazioni il cui codice EoI non è nel `DataExtract.csv`.

## Fusi orari e convenzione oraria

Un solo parametro, `tz_offset`, decide il fuso di **tutti** i file in uscita: osservati, modellati, ore di `period` e colonna `GMTLag` dello startup.

| Parametro | Cosa è | Valore nell'esempio |
|---|---|---|
| `tz_offset` | fuso dei file in uscita, in ore rispetto a UTC | `1` (UTC+1) |
| `model_tz_offset` | fuso scritto nei NetCDF FARM | `1` |
| `obs_tz_offset` | fuso delle ore EEA; se `NULL` si usa la colonna `Timezone` di ogni stazione (UTC+01 in Italia) | `NULL` |
| `gmt_lag` | testo della colonna `GMTLag`; con `NULL` è `UTC+1`, oppure `UTC` se `tz_offset = 0` | `NULL` (automatico) |

Con i valori dell'esempio non c'è sfasamento: il codice converte solo se i fusi sono diversi. Se i tuoi FARM sono in UTC, scrivi `model_tz_offset = 0`.

Le osservazioni EEA sono orologi "a muro" locali in UTC+1 fisso (niente ora legale). Se confronti con codice tuo, sottrai un'ora con `dhours(1)` o `- 3600`, non con `hours(1)` di lubridate su POSIXct in `Europe/Rome`: genera NA a marzo e un'ora doppia a ottobre.

**`obs_hour_label`** è l'ora a cui si attribuisce un valore che copre l'intervallo [`Start`, `End`): `"start"` = ora di inizio (il dato 00:00-01:00 va all'ora 0, come PMSS); `"end"` = ora di fine (va all'ora 1, come i tempi di FARM, istanti a fine ora). Osservazioni e modello devono usare la stessa convenzione; in alternativa si sposta il modello con `model_shift_h`.

## Altri parametri utili

| Parametro | Cosa fa |
|---|---|
| `scale` | valore della sezione `[MODEL]` dello startup (nell'esempio `"urban"`) |
| `pollutants`, `species` | tabella degli inquinanti (nomi e unità, vedi sotto) e selezione delle specie da preparare in questa esecuzione (`NULL` = tutte) |
| `valid_codes`, `min_coverage` | codici `Validity` accettati e copertura minima (vedi sopra) |
| `model_interp` | `"nearest"` oppure `"bilinear"` (vedi sopra) |
| `model_shift_h` | sposta di un numero di ore il modello rispetto alle osservazioni: serve solo se i due usano convenzioni orarie diverse |
| `obs_pattern`, `model_pattern` | espressione regolare sui nomi dei file se i tuoi non sono `.parquet` / `conc_...nc`; es. `model_pattern = "^conc_IT0_.*\\.nc$"` |
| `model_grid`, `model_x_dim`, `model_y_dim`, `model_time_dim` | tipo di griglia dei NetCDF (`"utm"`: x,y in km UTM; `"lonlat"`: gradi) e nomi delle dimensioni. Per vedere quali ha il tuo file: `names(ncdf4::nc_open("file.nc")$dim)`. L'ordine delle dimensioni della variabile non conta; il tempo può essere in secondi, minuti, ore o giorni dall'origine |
| `model_version` | testo che il nome del file di concentrazione deve contenere, per scegliere una versione/run quando nella cartella ce ne sono più di una; `NULL` = nessun filtro. Si somma a `model_pattern` |
| `out_label` | sottocartella di `out_dir` per l'output (vedi sopra) |
| `startup_name` | nome del file di startup (`startup.ini`) |
| `discarded_name`, `warnings_name` | nomi dei file di rapporto nella cartella di output: stazioni scartate (`discarded_stations.csv`) e avvisi completi (`warnings.txt`) |

## Inquinanti, nomi e unità di misura

Non sei limitato a NO2, O3, PM10, PM25: ogni inquinante è **una riga** della tabella `pollutants` in `run_example.R`, e puoi metterne quanti vuoi. Per ogni riga contano tre cose.

**1. Nomi.** Ci sono tre nomi diversi, da scrivere nelle colonne giuste:

| Colonna | Cosa è | Come trovarlo |
|---|---|---|
| `eea` | nome in `Air Pollutant` del `DataExtract.csv`, identico (es. `PM2.5`, `C6H6`, `BaP in PM10`, `NOX as NO2`) | `list_eea_pollutants("data/DataExtract.csv")` elenca tutti i nomi con il numero di sampling point |
| `farm` | nome della variabile nel NetCDF (es. `PM25`) | `list_model_variables("data/farm", "^conc_.*\\.nc$", NULL)` elenca variabili, unità e dimensioni |
| `delta` | il nome che vuoi nello startup e nei CSV | solo lettere e cifre, iniziando con una lettera: niente spazi, `_`, `;`, `*`, `.` (es. `PM2.5` diventa `PM25`, `BaP in PM10` diventa `BaP`). Il codice si ferma se il nome non è valido |

**Selezione delle specie.** La tabella può contenere tutte le specie che ti servono (nell'esempio: SO2, CO, NOX, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6) e in ogni esecuzione scegli quali preparare con `species`: `species <- c("NO2", "PM10")` prepara solo quelle due, `species <- NULL` le prepara tutte. Un nome che non è nella tabella ferma lo script con un errore. Con una selezione, il nome automatico della cartella di output comprende le specie (es. `output/2023_NO2-PM10/`), così selezioni diverse non si sovrascrivono. NOX resta nella tabella dell'esempio ma è escluso tramite `species`, perché DELTA non lo supporta.

**Specie senza dati.** Puoi lasciare nella tabella tutte le specie anche se nei tuoi parquet non ci sono tutte: quelle senza osservazioni non producono nulla (non finiscono nei CSV né in `[PARAMETERS]` dello startup) e lo script lo scrive a video. Le specie senza variabile nel NetCDF sono scartate con un avviso (senza modello non si può validare).

**2. Unità di misura.** `unit` è l'unità di **uscita**, scritta nello startup (es. `ugm-3`, `mgm-3`, `ngm-3`). Osservazioni e modello possono avere unità diverse e vengono portate in `unit`:

- osservazioni: l'unità è nella colonna `Unit` di ogni parquet EEA (es. `ug.m-3`, `mg.m-3`, `ng.m-3`);
- modello: l'unità è nell'attributo `units` della variabile NetCDF (es. `ug/m3`, `ug m-3`, `ng/m3`).

La conversione è **automatica** per le unità di massa su m3 (kg, g, mg, ug, ng, pg; anche `µg`); a video, per ogni specie, vedi cosa è stato fatto. Per unità non riconosciute (ppb, ppm, mol/mol, ...) il codice **si ferma** con un errore, perché la conversione dipende da massa molecolare, temperatura e pressione: scrivi tu il fattore nelle colonne facoltative `obs_factor` (osservazioni) e `model_factor` (modello). `NA` significa "automatico". Se nel NetCDF manca l'attributo `units`, il codice si ferma e chiede `model_factor`.

**3. Tipo.** `type` è `GAS` oppure `PM` (si scrive nello startup). Per metalli e idrocarburi policiclici in PM10 verifica con DELTA quale sia il valore giusto.

## Cosa compare a schermo

Lo script scrive tre tipi di righe (in inglese). Esempio con dati sintetici del test:

```
ISTAT boundaries: edition 2023
Species: NO2, O3, PM10
Observation units PM10: ug.m-3 -> ugm-3
Observations: 4 files, 0 skipped, 4 sampling points with valid data in the period
Model units NO2 (c_NO2): ug/m3 -> ugm-3
Output in: output/2023_20230101-20230102
Done: 2 station files (1 EEA stations) for 48 hours, species: NO2, PM10
```

**1. Messaggi informativi** (non richiedono azioni, servono a controllare che lo script abbia fatto quello che ti aspetti):

| La riga inizia con | Cosa significa |
|---|---|
| `ISTAT boundaries: edition ...` | edizione ISTAT usata (quella dell'anno `year`, o `istat_year`) |
| `Species: ...` | specie che verranno preparate |
| `Observation units ...` | unità trovata nei parquet e unità di uscita; se la conversione non è 1 compare il fattore |
| `Observations: N files, M skipped, K sampling points ...` | file letti; "skipped" = sampling point non nel `DataExtract.csv` (con avviso) o di specie non selezionate; ultimo numero = sampling point con almeno un dato valido nel periodo |
| `Missing metadata, filled in from the same station: ...` | stazioni con celle vuote nel `DataExtract.csv` completate con altri record della stessa stazione |
| `Model units ...` | variabile del NetCDF, sua unità e unità di uscita |
| `Output in: ...` | cartella dove sono stati scritti `startup.ini`, `obs/` e `mod/` |
| `Species without observations ...` | specie della tabella senza nessun dato osservato: non scritte |
| `Done: ...` | riepilogo finale: file scritti, stazioni EEA distinte, ore per file, specie scritte |

**2. Avvisi** (`WARNINGS`): qualcosa è stato scartato o modificato, ma lo script è andato avanti. Compaiono per esteso alla fine e **tutti** sono salvati in `warnings.txt` nella cartella di output. I più comuni:

| L'avviso inizia con | Cosa significa |
|---|---|
| `Station not in the metadata, skipped` | il codice EoI della stazione di quel parquet non è nel `DataExtract.csv`: non viene usato |
| `Variables missing in the NetCDF files, species dropped` | il modello non ha la variabile di quelle specie (colonna `farm`) |
| `Species with no sampling point in the EEA metadata` | il nome in `eea` non esiste nel `DataExtract.csv` |
| `Files outside the FARM grid, dropped` | la stazione cade fuori dal dominio del modello |
| `Files more than ... m from any ISTAT municipality, dropped` | la stazione non è in nessun comune (soglia `istat_max_dist_m`) |
| `Files without coordinates in the metadata, dropped` | lon/lat vuote e nessun altro record della stazione le ha |
| `Duplicate Station Code ... EoI appended` | lo stesso `Nat Code` in due stazioni EoI: si aggiunge l'EoI |
| `N of M hours without model data: written as -999` | mancano file del modello per parte del periodo |
| `Many hours appear in several files ...` | più versioni dello stesso periodo nella cartella del modello: usa `model_version` o `model_pattern` |
| `No ISTAT edition for ...: using edition ...` | manca l'edizione ISTAT dell'anno richiesto |
| `AggType not handled, ignored` | tipo di aggregazione EEA diverso da `hour`, `day`, `var`: ignorato |
| `Unit column missing in ...` | il parquet non ha le unità: nessuna conversione, imposta `obs_factor` se serve |
| `N sampling points matched by '...'` | l'abbinamento nel `DataExtract.csv` non era esatto sull'SPO (vedi "Abbinamento osservazioni ↔ DataExtract.csv") |

**3. Stazioni scartate.** Dopo gli avvisi compare il blocco `DISCARDED STATIONS (n)`, con una voce per ogni stazione (o sampling point) non scritta: codice EoI, elemento scartato, nome della stazione, comune, provincia e **motivo**:

```
===== DISCARDED STATIONS (1) =====
 1. EoI IT9002A | IT9002Aa | station: TEST | municipality: Example Town | province: Example Province (EP)
      reason: outside the model grid
```

Gli stessi dati sono in `discarded_stations.csv` (separatore `;`, colonne `eoi`, `item`, `station_name`, `municipality`, `province`, `reason`) nella cartella di output. I motivi possibili:

| Motivo | Quando |
|---|---|
| `EoI code not in DataExtract.csv` | la stazione del parquet non è nei metadati |
| `no valid data in the requested period` | il file esiste ma non ha dati validi nel periodo |
| `coverage X% of valid hours, below the Y% threshold` | copertura sotto `min_coverage` |
| `coordinates missing in DataExtract.csv` | lon/lat vuote e nessun altro record le ha |
| `outside the model grid` | la posizione cade fuori dal dominio dei NetCDF |
| `more than ... m from any ISTAT municipality` | la posizione non è in nessun comune ISTAT |

**Comune e provincia.** Quando la posizione è nota, comune e provincia vengono dai limiti ISTAT (comune dal layer `Com*`, provincia dal layer `ProvCM*`, con nome e sigla). Se la posizione cade fuori da ogni comune, il comune è quello del `DataExtract.csv` (colonna `Municipality`) segnato `[EEA]`, e la provincia è `-`. Il layer delle province è **facoltativo**: se nello zip ISTAT manca, la provincia è sempre `-`. I nomi delle colonne si impostano con `province_col` (nome, `DEN_UTS`; nelle edizioni vecchie `DEN_PROV`) e `province_abbr_col` (sigla, `SIGLA`).

**4. Errori**: lo script si ferma e il testo dice cosa manca. I più frequenti:

| Il messaggio inizia con | Cosa fare |
|---|---|
| `The 'arrow' package is required` | `install.packages("arrow")` |
| `The 'sf' package is required` | `install.packages("sf")` |
| `The ISTAT boundaries folder (istat_dir) is required` | crea la cartella (es. `data/istat`) e impostala in `istat_dir` |
| `No ISTAT boundaries in ...` / `... lack the layer Com*` (o `Reg*`) | copia nella cartella lo zip completo dei limiti ISTAT |
| `Column 'COMUNE' missing in the ISTAT layer` | in quell'edizione la colonna ha un altro nome: imposta `comune_col` / `region_col` (il messaggio elenca le colonne presenti) |
| `No NetCDF files in ...` | `model_dir` sbagliato, o nomi diversi da `model_pattern` / `model_version` |
| `In the NetCDF '...' I cannot find the grid dimensions ...` | i nomi della griglia sono diversi: imposta `model_x_dim`, `model_y_dim`, `model_grid` (il messaggio elenca quelli presenti) |
| `No species has a variable in the NetCDF files` | i nomi delle variabili non sono quelli della colonna `farm` (il messaggio elenca quelle presenti) |
| `No observation files in ...` | `obs_dir` sbagliato |
| `Unrecognised unit for ...` | l'unità non è di massa per m3 (es. ppb): imposta `obs_factor` / `model_factor` |
| `Invalid DELTA name` | il nome in `delta` ha spazi o simboli: usa solo lettere e cifre |
| `The model does not cover the requested period` | nessuna ora di `period` è nei file del modello: controlla `period`, `year`, `tz_offset` |
| `No valid observed data in the requested period` | nel periodo non ci sono dati validi: controlla `period` e `year` |

## Note sui dati

- Il modello può non avere alcune ore a inizio anno (es. 2023-01-01 00:00-03:00 se il primo file giornaliero parte alle 04:00): restano `-999`. `tools/check_model_time.R` elenca le ore non coperte dai file del modello.
- `tools/compare_outputs.R` confronta due cartelle di output (ciascuna con `obs/` e `mod/`): stessi nomi di file, colonne degli inquinanti abbinate per nome, ore abbinate per anno/mese/giorno/ora. Riporta le ore diverse (oltre `tol`), le ore mancanti da una parte, la differenza massima e media, e scrive `comparison_output.csv`. Usa `tol = 0.0101` per ignorare gli arrotondamenti dei mezzi valori.

## Test

`Rscript tests/test_synthetic.R` dalla radice del repository: usa solo dati inventati e controlla suffissi, fusi orari, valori `var`, nomi ripuliti, limiti ISTAT, abbinamento, copertura, interpolazione e convenzioni. Richiede `ncdf4` e `sf` e termina con `OK: all checks passed`. Di norma i dati sintetici sono temporanei; per conservarli (input e output) indica una cartella nuova: `Rscript tests/test_synthetic.R test_output`. I test non sostituiscono un controllo su dati reali.

## Licenza

MIT, vedi `LICENSE`. Dati e output (`*.nc`, `*.parquet`, `DataExtract.csv`, limiti ISTAT, `output/`) non fanno parte del repository. Vedi `CHANGELOG.md` per la storia delle versioni.
