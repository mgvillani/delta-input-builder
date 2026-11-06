# delta-input-FARM-builder
Input for the DeltaTool using EEA observations (parquet files) and the concentrations from model FARM (ITA-version)

# VERSIONE ITALIANA 

Prepara gli input del **DELTA Tool** (formato legacy) a partire da dati EEA e da un modello FARM.

**Cosa entra**

- le osservazioni delle stazioni EEA, in formato parquet (un file per sampling point);
- il CSV EEA con i metadati delle stazioni (`DataExtract.csv`);
- i NetCDF giornalieri del modello FARM (`FARM_conc_g2_AAAAMMGG_D1.nc`);
- i limiti amministrativi ISTAT, **obbligatori**, in una cartella dedicata: servono per scrivere regione e comune di ogni stazione.

**Cosa esce** (in una sottocartella di `output/` che porta l'anno e, se la imposti, la versione del modello, per esempio `output/2023_d0/`: vedi sotto)

- `startup.ini`, l'elenco delle stazioni;
- `obs/<stazione>.csv`: i dati osservati, un file per stazione;
- `mod/<stazione>.csv`: i dati del modello nella cella di quella stazione, con lo **stesso nome** dei file di `obs/`.

> **Uso a proprio rischio.** Il software e' fornito "cosi' com'e'", senza garanzie di alcun tipo e senza supporto (vedi `LICENSE`, MIT). Chi lo usa e' l'unico responsabile dei risultati: controlla sempre gli output, come descritto al passo 5, prima di usarli in qualsiasi valutazione. Il pacchetto e' stato sviluppato con l'ausilio di strumenti di intelligenza artificiale; non e' un prodotto ufficiale del JRC ne' di DELTA Tool.

---

## Istruzioni passo per passo

### Passo 1 - Metti i dati nelle cartelle giuste

Scarica o copia questo repository sul tuo computer. Dentro la cartella `delta-input-builder` crea una cartella `dati` e organizzala cosi':

```
delta-input-builder/
  R/                       (il codice: non toccare)
  run_example.R            (il file che modificherai)
  dati/
    eea_parquet/           tutti i file .parquet delle osservazioni EEA
    farm/                  tutti i file FARM_conc_..._D1.nc
    DataExtract.csv        metadati stazioni EEA
    istat/                 cartella dedicata ai limiti ISTAT (OBBLIGATORIA)
      Limiti01012023.zip   uno zip ISTAT per ogni anno, come lo scarichi
      Limiti01012024.zip
```

**I limiti ISTAT sono obbligatori.** Lo script legge regione e comune di ogni stazione da qui e senza di essi si ferma subito con un errore. Nella cartella `istat/` metti lo zip scaricato da ISTAT (non serve estrarlo) oppure le cartelle gia' estratte (`Com01012023/`, `Reg01012023/`, ...). ISTAT pubblica un'edizione ogni anno e la cartella puo' contenerne quante vuoi: lo script usa quella **dell'anno `year`** (la riconosce dalla data nel nome, es. `Limiti01012023.zip` = 2023). Se quell'anno non c'e', usa la piu' recente precedente (o, se non ce ne sono, la piu' vecchia disponibile) e te lo segnala con un avviso. Per forzare un'altra edizione imposta `istat_year`. Ogni volta lo script scrive a video l'edizione usata (`Limiti ISTAT: edizione 2023`).

La cartella `dati/` e' gia' esclusa da Git: non finira' mai nel repository.

### Passo 2 - Installa i pacchetti R (una volta sola)

Apri R o RStudio e lancia:

```r
install.packages(c("ncdf4", "arrow", "sf"))
```

- `ncdf4` legge i file FARM;
- `arrow` legge i file parquet;
- `sf` legge i limiti ISTAT (obbligatori).

### Passo 3 - Imposta i parametri in `run_example.R`

Tutti i parametri si impostano **in un solo posto: in alto in `run_example.R`**, nella sezione `PARAMETRI`. Il codice nella cartella `R/` non ha valori nascosti per nomi di file, cartelle, fusi orari o inquinanti: non devi aprirlo mai. Ogni riga e' commentata. Le parti principali:

```r
## Osservazioni EEA
obs_dir     <- "dati/eea_parquet"
obs_pattern <- "\\.parquet$"               # regex sul nome dei file di osservazioni
meta_csv    <- "dati/DataExtract.csv"

## Modello (file di concentrazione)
model_dir     <- "dati/farm"
model_pattern <- "^FARM_conc_.*\\.nc$"     # regex sul nome dei file da leggere
model_version <- NULL                        # es. "g2": testo che il nome deve contenere
model_grid     <- "lonlat"                   # "utm" (x,y in km, come FARM) oppure "lonlat" (gradi)
model_x_dim    <- "lon"                      # nome della dimensione x nei NetCDF ("x" per FARM UTM)
model_y_dim    <- "lat"                      # nome della dimensione y ("y" per FARM UTM)
model_time_dim <- "time"
utm_lon0       <- 9                          # solo per model_grid = "utm"

## Limiti ISTAT (obbligatori): uno zip per anno nella stessa cartella
istat_dir        <- "dati/istat"
istat_year       <- NULL                     # NULL = edizione dell'anno `year`
istat_max_dist_m <- 2000
comune_col       <- "COMUNE"
region_col       <- "DEN_REG"
province_col      <- "DEN_UTS"               # solo per il rapporto delle stazioni scartate
province_abbr_col <- "SIGLA"

## Inquinanti: tabella pollutants (NO2, O3, PM10, PM25), uscita, periodo, fusi orari ...
year      <- 2023
tz_offset <- 1                               # tutti i file in uscita in UTC+1 (0 = UTC)
```

Poi, piu' in basso nello stesso file, la chiamata `build_delta_inputs(...)` passa questi valori: non va modificata.

Cosa controllare:

- `year`: l'anno dei tuoi dati;
- i percorsi: se hai seguito il passo 1 sono gia' giusti. Su Windows scrivi sempre `/` e non `\` (esempio: `"C:/Users/nome/dati/farm"`);
- `model_pattern` e `model_version`: scelgono quali file di concentrazione leggere (vedi "Altri parametri utili");
- `istat_dir`: la cartella dei limiti ISTAT del passo 1. **Non si puo' togliere**. `istat_year` e' l'anno dell'edizione ISTAT; con `NULL` vale `year`;
- `tz_offset <- 1` significa che **tutti** i file in uscita sono in UTC+1. Per avere UTC scrivi `0`.

### Passo 4 - Prima prova su pochi giorni

Prima dell'anno intero, prova su un periodo breve, per vedere subito eventuali errori. In `run_example.R` cerca il parametro `period` (e' `NULL`, cioe' anno intero) e sostituiscilo cosi':

```r
period <- c(as.POSIXct("2023-01-01 00:00", tz = "UTC"),
            as.POSIXct("2023-01-02 23:00", tz = "UTC"))
```

Le ore di `period` sono ore "a muro" nel fuso scelto con `tz_offset`: con `tz_offset <- 1` sono ore italiane. Il `tz = "UTC"` e' solo un'etichetta tecnica e va lasciato cosi'.

Poi esegui lo script. Da R o RStudio, con la cartella `delta-input-builder` come cartella di lavoro:

```r
setwd("percorso/della/cartella/delta-input-builder")
source("run_example.R")
```

Oppure da terminale, nella stessa cartella: `Rscript run_example.R`.

### Passo 5 - Controlla i risultati

1. **Avvisi**: dopo l'esecuzione lancia `warnings()` e leggili (vedi "Problemi frequenti").
2. **Cartella di output** (per esempio `output/2023/`): devono esserci `startup.ini`, `obs/` e `mod/`. I file in `obs/` e in `mod/` devono avere gli stessi nomi.
3. **Un file a caso**: aprilo. La prima riga e' `year;month;day;hour;NO2;PM10;...`. Il valore `-999` significa "dato mancante".
4. **Startup**: in `startup.ini` controlla che regione, comune e `GMTLag` siano quelli attesi. Regione e comune mantengono il nome ISTAT (spazi e `/` compresi), con accenti traslitterati e `;` `*` `_` sostituiti da spazio.
5. **Un confronto veloce**: cosi' vedi subito se osservati e modellati sono sfasati di qualche ora (cambia nome stazione e inquinante):

```r
o <- read.csv("output/2023/obs/IT0063Aa.csv", sep = ";")
m <- read.csv("output/2023/mod/IT0063Aa.csv", sep = ";")
o[o == -999] <- NA
plot(m$NO2, type = "l"); lines(o$NO2, col = "red")
```

### Passo 6 - Lancia l'anno intero

Cancella (o commenta con `#`) le righe di `period` e rilancia. Servono i file FARM di tutti i giorni dell'anno: per i giorni mancanti i valori del modello sono scritti come `-999` e compare un avviso con il numero di ore senza modello.

### Passo 7 - Usa i file in DELTA

- **Delta Tool Online**: carica `startup.ini`, poi uno zip con i file di `obs/` e uno zip con i file di `mod/`.
- **Delta Tool / Delta Tool Light** (versione da installare): segui la guida del tool per le cartelle in cui copiare `startup.ini` e i CSV.

---

## Come sono fatti i file in uscita

**CSV di una stazione** (uguale per `obs/` e `mod/`):

```
year;month;day;hour;NO2;PM10
2023;1;1;0;-999;25.00
2023;1;1;1;10.00;25.00
```

Un'ora per riga, per tutto il periodo richiesto, con le sole colonne degli inquinanti di quella stazione.

**Nome del file e lettera finale.** Il nome e' il codice EEA della stazione piu' una lettera (`IT0063A` diventa `IT0063Aa`). La lettera cambia quando la stessa stazione misura lo stesso inquinante con **piu' strumenti** (piu' sampling point):

- `IT0469Aa`: NO2 e PM10 del primo strumento (quello con piu' dati validi);
- `IT0469Ab`: solo il PM10 del secondo strumento.

La lettera cambia anche quando i record della stessa stazione hanno **coordinate, `Station Type` o `Area Type` diversi** nel `DataExtract.csv` (per esempio NO2 `background` e PM10 `industrial`): ogni combinazione e' un file a se', con i valori del suo record. Le lettere si assegnano per livello (primo strumento di ogni combinazione, poi il secondo, ...) e, a parita', per ore valide totali. `Area Type` resta come nel file (`rural-nearcity`, `rural-remote`, ...); lon, lat e quota sono scritte con tutti i decimali.

**Soglia di copertura (`min_coverage`).** In `run_example.R`: frazione minima di ore valide nel periodo per ogni sampling point (stazione + inquinante). Con `0.75`, chi ha meno del 75% di ore valide e' scartato e compare nel rapporto delle stazioni scartate con la sua percentuale. `0` tiene tutto cio' che ha almeno un dato. Vale per ogni sampling point: due strumenti dello stesso inquinante sono valutati separatamente.

Per ogni file `obs/` esiste un file `mod/` con lo stesso nome: il modello e' quello della stessa cella, limitato agli stessi inquinanti.

**Come vengono trattati i dati EEA**

- Dati orari: il valore va all'ora di inizio.
- Dati giornalieri (`day`) e a intervallo variabile (`var`, per esempio benzene, Pb, Cd): il valore e' costante e viene ripetuto su **ogni ora** dell'intervallo, qualunque ne sia la lunghezza.
- Dati non validi diventano `-999`: valore `-9999` o codice `Validity` non presente in `valid_codes`. In `run_example.R` `valid_codes <- c(1L)` accetta solo i dati "validi" (1); `c(1L, 2L, 3L)` include anche i validi sotto il limite di rilevabilita' (2 e 3, frequenti per SO2, CO, C6H6 e metalli), che alzano la copertura e quindi il numero di stazioni sopra `min_coverage`.

**Come viene preso il modello.** Cella FARM piu' vicina alla stazione. Le stazioni fuori dalla griglia FARM sono scartate, con un avviso. Se due file giornalieri hanno in comune l'ora 00, vince il file piu' recente.

## Station Code, Station Name e Station abbreviation: devono essere unici

- **Station Name** e **Station abbreviation** sono il nome del file (codice EEA + lettera, es. `IT0063Aa`): sono unici per costruzione, perche' ogni file ha il suo.
- **Station Code** e' il `Nat Code` nazionale della stazione piu' la lettera (es. `1104213a`). Nei dati EEA lo stesso `Nat Code` puo' comparire in due stazioni EoI diverse (nel tuo `DataExtract.csv` succede in 4 casi): il codice non sarebbe piu' unico. In quel caso lo script aggiunge il codice EoI (`1205822aIT2258A`) e lo segnala con un avviso.
- Alla fine controlla che i tre campi siano unici (anche senza distinguere maiuscole e minuscole, per i nomi dei file su Windows) e si ferma con un errore se non lo sono.

## Piu' versioni del modello e nome della cartella di output

L'output non va direttamente in `output/`: `startup.ini`, `obs/` e `mod/` si scrivono in una **sottocartella** di `out_dir`, il cui nome e' `out_label`. Con `out_label <- NULL` (automatico) il nome e':

- `2023` (l'anno);
- `2023_d0` se imposti `model_version <- "d0"`;
- `2023_d0_20230101-20230102` se imposti anche un `period` (cosi' una prova breve non sovrascrive l'anno intero).

Esempio con le stesse osservazioni e tre versioni del modello nella stessa cartella (`conc_..._d0_...nc`, `..._d1_...`, `..._d2_...`): lancia lo script tre volte cambiando solo `model_version` (`"d0"`, `"d1"`, `"d2"`) e ottieni `output/2023_d0/`, `output/2023_d1/`, `output/2023_d2/`, senza sovrascritture. `model_version` e' un testo cercato nel nome del file: scegline uno specifico (per esempio `"_d1_"` e non `"d1"`) per non confonderlo con altre parti del nome.

Se lasci `model_version <- NULL` con piu' versioni nella stessa cartella, i file si mescolano (vince l'ultimo in ordine di nome) e lo script lo segnala con un avviso. Con `out_label <- "mio_nome"` scegli tu il nome della sottocartella, con `""` scrivi direttamente in `out_dir`. Alla fine lo script scrive a video la cartella usata (`Output in: ...`).

## Region e Siting

Nello `startup.ini` servono la regione e il comune di ogni stazione. Non sono nei dati EEA: si ricavano **sempre** dai limiti ISTAT (`istat_dir`, obbligatorio), in base alla posizione della stazione.

- `Region` viene dalla colonna `DEN_REG` del layer delle regioni (`Reg*`);
- `Siting` viene dalla colonna `COMUNE` del layer dei comuni (`Com*`);
- se i nomi delle colonne dell'edizione ISTAT cambiano, si adattano con `region_col` e `comune_col`;
- una stazione sulla costa, appena fuori dai poligoni, prende il comune piu' vicino se e' entro `istat_max_dist_m` metri (2000 nell'esempio); oltre, la stazione e' **scartata** con un avviso, perche' non esiste un valore di ripiego.

I nomi sono ripuliti: niente accenti, apostrofi, spazi, trattini e barre; le parole sono unite con la maiuscola iniziale. Esempi: `Borgaro Torinese` diventa `BorgaroTorinese`, `Albiano d'Ivrea` diventa `AlbianoDIvrea`, `Aglié` diventa `Aglie`.

## Metadati della stazione: valori come nel file

Nel `DataExtract.csv` ogni stazione ha un record per inquinante e strumento, e a volte i record della stessa stazione hanno valori diversi (coordinate che differiscono di pochi metri, `Station Type` o `Area Type` diversi). **I valori restano quelli del file**, senza uniformarli: ogni file di uscita (`...a`, `...b`) riporta nello startup i valori del proprio record (se contiene piu' inquinanti, quelli del primo inquinante nell'ordine della tabella `pollutants`) e anche la cella FARM e il comune sono quelli di quella posizione. Quindi la stessa stazione puo' comparire nello startup con coordinate, tipo o area diversi tra una lettera e l'altra.

Solo quando un dato **manca** (cella vuota nel `DataExtract.csv`) si usa il valore degli altri record della stessa stazione: quello sostenuto da piu' ore di dati validi. Lo script scrive a video le stazioni completate cosi'. Se mancano le coordinate e la stazione non ha altri record con coordinate, il file e' scartato con un avviso.

## Fusi orari

Un solo parametro, `tz_offset`, decide il fuso di **tutti** i file in uscita: osservati, modellati, ore di `period` e colonna `GMTLag` dello startup.

| Parametro | Cosa e' | Valore nell'esempio |
|---|---|---|
| `tz_offset` | fuso dei file in uscita, in ore rispetto a UTC | `1` (UTC+1) nell'esempio |
| `model_tz_offset` | fuso scritto nei NetCDF FARM | `1` |
| `obs_tz_offset` | fuso delle ore EEA; se non lo scrivi si usa la colonna `Timezone` di ogni stazione (UTC+01 in Italia) | `NULL` |
| `gmt_lag` | testo della colonna `GMTLag`; con `NULL` e' `UTC+1`, oppure `UTC` se `tz_offset = 0` | `NULL` (automatico) |

Con i valori dell'esempio non c'e' nessuno sfasamento. Il codice converte solo se i fusi sono diversi. Se i tuoi FARM sono in UTC, scrivi `model_tz_offset = 0`.

## Altri parametri utili

| Parametro | Cosa fa |
|---|---|
| `scale` | valore della sezione `[MODEL]` dello startup (nell'esempio `"urban"`) |
| `pollutants`, `species` | tabella degli inquinanti, nomi e unita' (vedi la sezione sopra) e selezione delle specie da preparare in questa esecuzione (`NULL` = tutte) |
| `obs_hour_label` | ora a cui si attribuisce il dato orario delle osservazioni EEA, che copre l'intervallo [`Start`, `End`): `"start"` = ora di inizio (il dato 00:00-01:00 va all'ora 0, come PMSS); `"end"` = ora di fine (va all'ora 1, come i tempi di FARM, istanti a fine ora). Vale anche per i dati giornalieri e a intervallo variabile. Osservazioni e modello devono usare la stessa convenzione: in alternativa si sposta il modello con `model_shift_h` |
| `model_interp` | come si passa dalla griglia del modello alla stazione: `"nearest"` = valore della cella con il centro piu' vicino; `"bilinear"` = interpolazione bilineare tra i centri delle 4 celle intorno (come `raster::extract(..., method = "bilinear")`). Un punto tra l'ultimo centro e il bordo della griglia usa le celle di bordo; se una delle celle usate e' `NA`, il valore e' `NA` (`-999`). Le celle sono quelle della posizione di ogni file di uscita |
| `model_shift_h` | sposta di un numero di ore il modello rispetto alle osservazioni: serve solo se osservazione e modello usano convenzioni orarie diverse (inizio o fine ora) |
| `obs_pattern`, `model_pattern` | (in `run_example.R`) schema (espressione regolare) dei nomi dei file, se i tuoi non sono `.parquet` / `FARM_conc_...nc`; es. `model_pattern = "^FARM_conc_g2_.*_D1\\.nc$"` |
| `model_grid`, `model_x_dim`, `model_y_dim`, `model_time_dim` | tipo di griglia dei NetCDF (`"utm"`: coordinate x,y in km UTM come FARM; `"lonlat"`: gradi) e nomi delle dimensioni. Per vedere quali ha il tuo file: `names(ncdf4::nc_open("file.nc")$dim)`. L'ordine delle dimensioni della variabile non conta; il tempo puo' essere in secondi, minuti, ore o giorni dall'origine |
| `model_version` | testo che il nome del file di concentrazione deve contenere, per scegliere una versione/run del modello quando nella cartella ce ne sono piu' di una (es. `"g2"`, `"v5"`); `NULL` = nessun filtro. Si somma a `model_pattern` |
| `out_label` | sottocartella di `out_dir` per l'output: `NULL` = `<anno>[_<model_version>][_<periodo>]`, una stringa = quel nome, `""` = direttamente in `out_dir` |
| `startup_name` | nome del file di startup (nell'esempio `startup.ini`) |
| `discarded_name`, `warnings_name` | nomi dei file di rapporto nella cartella di output: stazioni scartate (`stazioni_scartate.csv`) e avvisi completi (`avvisi.txt`) |

## Inquinanti, nomi e unita' di misura

Non sei limitato a NO2, O3, PM10, PM25: ogni inquinante e' **una riga** della tabella `pollutants` in `run_example.R`, e puoi metterne quanti vuoi (benzene, CO, SO2, metalli, ...). Per ogni riga attenzione a tre cose.

**1. Nomi.** Ci sono tre nomi diversi, da scrivere nelle colonne giuste:

| Colonna | Cosa e' | Come trovarlo |
|---|---|---|
| `eea` | nome in `Air Pollutant` del `DataExtract.csv`, identico (es. `PM2.5`, `C6H6`, `BaP in PM10`, `NOX as NO2`) | `list_eea_pollutants("dati/DataExtract.csv")` elenca tutti i nomi con il numero di sampling point |
| `farm` | nome della variabile nel NetCDF (es. `PM25`) | `list_model_variables("dati/farm", "^conc_.*\\.nc$", NULL)` elenca variabili, unita' e dimensioni |
| `delta` | il nome che vuoi nello startup e nei CSV | solo lettere e cifre, iniziando con una lettera: niente spazi, `_`, `;`, `*`, `.` (es. `PM2.5` diventa `PM25`, `BaP in PM10` diventa `BaP`). Il codice si ferma se il nome non e' valido |

**Selezione delle specie.** La tabella puo' contenere tutte le specie che ti servono (nell'esempio: SO2, CO, NOX, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6) e in ogni esecuzione scegli quali preparare con `species`: `species <- c("NO2", "PM10")` prepara solo quelle due, `species <- NULL` le prepara tutte. Un nome che non e' nella tabella ferma lo script con un errore. Con una selezione, il nome automatico della cartella di output comprende le specie (es. `output/2023_NO2-PM10/`), cosi' selezioni diverse non si sovrascrivono.

**Specie senza dati.** Puoi lasciare nella tabella tutte le specie anche se nei tuoi parquet non ci sono tutte: quelle senza osservazioni non producono nulla (non finiscono nei CSV ne' in `[PARAMETERS]` dello startup) e lo script lo scrive a video (`Specie senza osservazioni (non scritte nello startup): ...`).

Le specie senza variabile nel NetCDF sono scartate con un avviso (senza modello non si puo' validare). Non so quali specie e quali nomi DELTA accetti: verificalo.

**2. Unita' di misura.** `unit` e' l'unita' di **uscita**, scritta nello startup (es. `ugm-3`, `mgm-3`, `ngm-3`). Osservazioni e modello possono avere unita' diverse e vengono portate in `unit`:

- osservazioni: l'unita' e' nella colonna `Unit` di ogni parquet EEA (es. `ug.m-3`, `mg.m-3`, `ng.m-3`); il CO e' tipicamente in mg/m3, metalli e idrocarburi policiclici in ng/m3;
- modello: l'unita' e' nell'attributo `units` della variabile NetCDF (es. `ug/m3`, `ug m-3`, `ng/m3`).

La conversione e' **automatica** per le unita' di massa su m3 (kg, g, mg, ug, ng, pg; anche `µg`). A video, per ogni specie, vedi cosa e' stato fatto: `Unita' osservazioni CO: mg.m-3 -> mgm-3` e `Unita' modello CO (CO): ug/m3 -> mgm-3 (x0.001)`. Per unita' non riconosciute (ppb, ppm, mol/mol, ...) il codice **si ferma** con un errore, perche' la conversione dipende da massa molecolare, temperatura e pressione: scrivi tu il fattore nelle colonne facoltative `obs_factor` (osservazioni) e `model_factor` (modello). `NA` significa "automatico". Se nel NetCDF manca l'attributo `units`, il codice si ferma e chiede `model_factor`.

**3. Tipo.** `type` e' `GAS` oppure `PM` (si scrive nello startup): per i metalli e gli idrocarburi policiclici in PM10 il valore giusto per DELTA non lo conosco, verificalo.

## Cosa compare a schermo

Lo script scrive tre tipi di righe. Esempio reale (dati sintetici del test):

```
Limiti ISTAT: edizione 2023
Specie: NO2, O3, PM10
Unita' osservazioni PM10: ug.m-3 -> ugm-3
Unita' osservazioni NO2: ug.m-3 -> ugm-3
Osservazioni: 4 file, 0 saltati, 4 sampling point con dati validi nel periodo
Unita' modello NO2 (c_NO2): ug/m3 -> ugm-3
Unita' modello PM10 (c_PM10): ug/m3 -> ugm-3
Output in: output/2023_20230101-20230102
Fatto: 2 file di stazione (1 stazioni EEA) per 48 ore, specie: NO2, PM10
Warning messages:
1: ... Variabili assenti nei NetCDF, specie scartate: O3
2: ... File fuori dalla griglia FARM, scartati: IT9002Aa
```

**1. Messaggi informativi** (compaiono man mano; non richiedono azioni, servono a controllare che lo script abbia fatto quello che ti aspetti), nell'ordine in cui appaiono:

| Riga | Cosa significa |
|---|---|
| `Limiti ISTAT: edizione 2023` | edizione dei limiti ISTAT usata (quella dell'anno `year`, o `istat_year`) |
| `Specie: NO2, O3, PM10` | specie che verranno preparate (tabella `pollutants` filtrata da `species`) |
| `Unita' osservazioni NO2: ug.m-3 -> ugm-3` | unita' trovata nei parquet e unita' di uscita. Se la conversione non e' 1 compare il fattore: `(x1000)` |
| `Osservazioni: 4 file, 0 saltati, 4 sampling point con dati validi nel periodo` | file letti in `obs_dir`; "saltati" = parquet il cui sampling point non e' nel `DataExtract.csv` (con avviso); ultimo numero = sampling point con almeno un dato valido nel periodo |
| `Dati mancanti nei metadati, completati con quelli della stessa stazione: ...` | stazioni con celle vuote nel `DataExtract.csv` (coordinate, quota, area, tipo) completate con i valori degli altri record della stessa stazione |
| `Unita' modello NO2 (c_NO2): ug/m3 -> ugm-3` | variabile del NetCDF, sua unita' e unita' di uscita (con fattore se diverso da 1) |
| `Output in: ...` | cartella dove sono stati scritti `startup.ini`, `obs/` e `mod/` |
| `Specie senza osservazioni (non scritte nello startup): ...` | specie della tabella per cui non c'e' nessun dato osservato: non compaiono nei file ne' in `[PARAMETERS]` |
| `Fatto: 2 file di stazione (1 stazioni EEA) per 48 ore, specie: NO2, PM10` | riepilogo finale: file scritti (uno per stazione e lettera, sia in `obs/` sia in `mod/`), stazioni EEA distinte, ore per file, specie scritte |

**2. Avvisi**: qualcosa e' stato scartato o modificato, ma lo script e' andato avanti. Lo script li raccoglie e li **scrive per esteso a schermo alla fine**, nel blocco `===== AVVISI (n) =====` (numerati, fino a 60 righe a schermo), e li salva **tutti** nel file `avvisi.txt` dentro la cartella di output. Non servono piu' `warnings()` ne' il messaggio `Ci sono 50 o piu' avvertimenti`. Il blocco compare anche se lo script si ferma con un errore. Gli avvisi piu' comuni:

| Avviso | Cosa significa |
|---|---|
| `Sampling point non in metadati ... saltato: <file>` | quel parquet non e' nel `DataExtract.csv` (o e' di una specie non nella tabella): non viene usato |
| `Variabili assenti nei NetCDF, specie scartate: ...` | il modello non ha la variabile di quelle specie (colonna `farm`): non si possono validare |
| `Specie senza nessun sampling point nei metadati EEA` | il nome in `eea` non esiste nel `DataExtract.csv` |
| `File fuori dalla griglia FARM, scartati: ...` | la stazione cade fuori dal dominio del modello |
| `File a piu' di ... m da ogni comune ISTAT, scartati: ...` | la stazione non e' in nessun comune (soglia `istat_max_dist_m`) |
| `File senza coordinate nei metadati, scartati: ...` | lon/lat vuote e nessun altro record della stazione le ha |
| `Station Code duplicato ... aggiunto l'EoI: ...` | lo stesso `Nat Code` in due stazioni EoI: al codice si aggiunge l'EoI |
| `N ore su M senza modellato: scritte come -999` | mancano dei file del modello per parte del periodo |
| `Molte ore compaiono in piu' file ...` | nella cartella del modello ci sono piu' versioni dello stesso periodo: usa `model_version` o `model_pattern` |
| `Nessuna edizione ISTAT del ...: uso l'edizione ...` | manca l'edizione ISTAT dell'anno richiesto |
| `AggType non gestito, ignorato: ...` | tipo di aggregazione EEA diverso da `hour`, `day`, `var`: quei dati sono ignorati |
| `Colonna Unit assente in ...` | il parquet non ha le unita': nessuna conversione, imposta `obs_factor` se serve |

**3. Stazioni scartate.** Subito dopo gli avvisi compare il blocco `===== STAZIONI SCARTATE (n) =====`, con una voce per ogni stazione (o sampling point) non scritta:

```
===== STAZIONI SCARTATE (1) =====
 1. EoI IT9002A | IT9002Aa | stazione: TEST | comune: Citta' d'Esempio | provincia: Provincia di Prova (PP)
      motivo: fuori dalla griglia del modello
```

Ogni voce riporta il **codice EoI**, l'elemento scartato (nome del file di uscita, sampling point o file parquet), il nome della stazione, il **comune**, la **provincia** e il **motivo**. Gli stessi dati sono nel file `stazioni_scartate.csv` (separatore `;`) nella cartella di output. I motivi possibili:

| Motivo | Quando |
|---|---|
| `sampling point non presente nel DataExtract.csv (o piu' di uno nel file)` | il parquet non ha un sampling point nei metadati: EoI ricavato dal nome del sampling point; comune e provincia non sono noti |
| `nessun dato valido nel periodo richiesto` | il sampling point ha il file ma nessun dato valido nel periodo |
| `coordinate mancanti nel DataExtract.csv` | lon/lat vuote e nessun altro record della stazione le ha |
| `fuori dalla griglia del modello` | la posizione cade fuori dal dominio dei NetCDF |
| `a piu' di ... m da ogni comune ISTAT` | la posizione non e' in nessun comune ISTAT (soglia `istat_max_dist_m`) |

**Comune e provincia.** Quando la posizione e' nota, comune e provincia vengono dai limiti ISTAT (comune dal layer `Com*`, provincia dal layer `ProvCM*`, con nome e sigla). Se la posizione cade fuori da ogni comune ISTAT, il comune e' quello del `DataExtract.csv` (colonna `Municipality`) segnato `[EEA]`, e la provincia e' `-`. Il layer delle province e' **facoltativo**: se nello zip ISTAT manca, la provincia e' sempre `-`. I nomi delle colonne si impostano con `province_col` (nome, `DEN_UTS`; nelle edizioni vecchie `DEN_PROV`) e `province_abbr_col` (sigla, `SIGLA`); se una colonna non esiste non c'e' nessun errore, la provincia resta `-`.

**4. Errori** (`Errore in ...` / `Error in ...`): lo script si ferma. Il testo dice cosa manca; i piu' frequenti sono nella tabella "Problemi frequenti" qui sotto.

## Pacchetti R usati

| Pacchetto | A cosa serve | Quando serve | Da installare? |
|---|---|---|---|
| `ncdf4` | leggere i NetCDF del modello (griglia, tempo, variabili, unita') | sempre | si': `install.packages("ncdf4")` |
| `sf` | leggere i limiti ISTAT (shapefile), trovare comune e regione di ogni stazione | sempre (i limiti ISTAT sono obbligatori) | si': `install.packages("sf")` |
| `arrow` | leggere i file `.parquet` delle osservazioni EEA | solo se `obs_pattern` seleziona file `.parquet` | si': `install.packages("arrow")` |
| `stats`, `utils` | funzioni di base di R (mediana, lettura CSV, unzip) | sempre | no, sono inclusi in R |

Non ci sono altre dipendenze: nessun `tidyverse`, `dplyr`, `data.table` o simili. Il test (`tests/test_synthetic.R`) richiede `ncdf4` e `sf`; per il solo passaggio sullo zip ISTAT usa anche il comando `zip` del sistema se c'e' (altrimenti salta quel controllo). Versioni con cui ho provato: R 4.3.3, `ncdf4` 1.22, `sf` 1.0.15. `arrow` non era installabile nel mio ambiente di prova, quindi la lettura dei `.parquet` l'ho verificata solo su esportazioni CSV con le stesse colonne: provala sui tuoi file veri.

## Problemi frequenti

| Messaggio | Cosa significa | Cosa fare |
|---|---|---|
| `Per leggere i file parquet serve il pacchetto 'arrow'` | `arrow` non e' installato | `install.packages("arrow")` |
| `Serve il pacchetto 'sf' per leggere i limiti ISTAT` | `sf` non e' installato | `install.packages("sf")` |
| `La cartella dei limiti ISTAT (istat_dir) e' obbligatoria e deve esistere` | manca `istat_dir` o il percorso e' sbagliato | crea la cartella (es. `dati/istat`) e indicala in `istat_dir` |
| `Nessun limite ISTAT in '...'` | la cartella esiste ma e' vuota o senza i layer dei comuni e delle regioni | copia nella cartella lo zip ISTAT (`Limiti01012023.zip`) o le cartelle `Com*` e `Reg*` |
| `Nei limiti ISTAT in '...' manca il layer Com*` (o `Reg*`) | lo zip non contiene i layer dei comuni o delle regioni | scarica da ISTAT il pacchetto completo dei limiti amministrativi |
| `Colonna 'COMUNE' assente nel layer ISTAT` | in quell'edizione ISTAT la colonna ha un altro nome | guarda l'elenco delle colonne nel messaggio e imposta `comune_col` / `region_col` |
| `Nessuna edizione ISTAT del ...: uso l'edizione ...` | nella cartella manca l'edizione dell'anno richiesto | e' solo un avviso; per usare quella giusta scarica da ISTAT lo zip dell'anno e mettilo in `istat/` |
| `File a piu' di ... m da ogni comune ISTAT, scartati` | la posizione del file non cade in nessun comune | controlla le coordinate nel `DataExtract.csv` o aumenta `istat_max_dist_m` |
| `Nessun file NetCDF in ...` | percorso `model_dir` sbagliato, o nomi diversi da `FARM_conc_...nc` | controlla il percorso, imposta `model_pattern` o verifica che `model_version` compaia nei nomi |
| `Nel NetCDF '...' non trovo le dimensioni '...' e '...'` | i nomi della griglia nei tuoi NetCDF sono diversi | il messaggio elenca le dimensioni presenti: scrivi i nomi giusti in `model_x_dim` e `model_y_dim` (e `model_grid`) |
| `Nessuna specie con variabile nei NetCDF. Variabili presenti: ...` | i nomi delle variabili non sono quelli della colonna `farm` di `pollutants` | copia i nomi elencati nella colonna `farm` |
| `Nessun file osservazioni in ...` | percorso `obs_dir` sbagliato | controlla il percorso |
| `Unita' non riconosciuta per ...` | l'unita' (osservazioni o modello) non e' di massa per m3, es. ppb | scrivi `obs_factor` o `model_factor` nella tabella `pollutants` |
| `Nome DELTA non valido` | il nome in `delta` ha spazi o simboli | usa solo lettere e cifre (niente `_`) |
| `Sampling point non in metadati ... saltato` | quel parquet non e' nel `DataExtract.csv`, oppure e' di un inquinante non nella tabella | normale per gli inquinanti non gestiti; altrimenti scarica un `DataExtract.csv` piu' completo |
| `File fuori dalla griglia FARM, scartati` | la posizione del file non cade nel dominio del modello | normale per stazioni fuori dominio |
| `File senza coordinate nei metadati, scartati` | lon/lat vuote e nessun altro record della stazione le ha | completa il `DataExtract.csv` |
| `... ore su ... senza modellato: scritte come -999` | mancano file FARM per parte del periodo | controlla di avere tutti i giorni |
| `Il modellato non copre il periodo richiesto` | nessuna ora di `period` e' nei file FARM | controlla `period`, `year` e `tz_offset` |
| `Nessun dato osservato valido nel periodo richiesto` | nel periodo non ci sono dati validi | controlla `period` e `year` |

## Assunzioni da verificare

1. **Convenzione oraria**: l'osservazione e' etichettata con l'ora di inizio; il tempo del modello e' usato cosi' com'e'. Se serve uno sfasamento: `model_shift_h`.
2. **Specie**: tutte quelle della tabella `pollutants`, con unita' convertite come descritto in "Inquinanti, nomi e unita' di misura".
3. **Griglia FARM**: coordinate `x` e `y` in km UTM, fuso 32N esteso (meridiano centrale 9 E), valori al centro cella.

## Test

`Rscript tests/test_synthetic.R` dalla radice del repository: usa solo dati inventati e controlla suffissi, fusi orari, valori `var`, nomi ripuliti e limiti ISTAT. Di norma i dati sintetici sono temporanei; per conservarli (input e output) indica una cartella nuova: `Rscript tests/test_synthetic.R test_output`.

## Licenza

MIT, vedi `LICENSE`. Dati e output (`*.nc`, `*.parquet`, `DataExtract.csv`, limiti ISTAT, `output/`) non fanno parte del repository.

## Abbinamento osservazioni ↔ DataExtract.csv

Il sampling point di ogni parquet (`SPO.<EoI>_<codice>_<metodo>_<data>`) viene cercato nel
DataExtract.csv in quest'ordine: stesso SPO; stesso SPP (Process Id); stessa stazione, codice
e metodo; stessa stazione e codice inquinante; solo la stazione (specie dal codice). SPO e SPP
della stessa riga possono avere metodo e data diversi, e un SPO puo' avere piu' SPP: tra le
righe candidate vince quella con meno dati mancanti, poi l'SPP piu' recente. I valori restano
quelli del file; quelli mancanti sono completati con la stessa stazione (vedi sopra). Se
l'abbinamento non e' esatto sull'SPO, lo vedi tra i messaggi/avvisi. Un parquet con piu'
sampling point viene diviso, non saltato. Le osservazioni di specie non selezionate sono
ignorate (messaggio), non indicate come "scartate". Sono scartate solo le stazioni il cui
codice EoI non e' nel DataExtract.csv.

## Confronto tra due cartelle di input

`tools/compare_outputs.R` confronta due cartelle di uscita (ciascuna con `obs/` e `mod/`): stessi nomi di file, colonne degli inquinanti abbinate per nome (la posizione non conta), ore abbinate per anno/mese/giorno/ora. Per ogni file e specie riporta ore diverse (oltre `tol`), ore mancanti solo da una parte, differenza massima e media. I nomi delle specie di una delle due parti possono essere mappati con `name_map` (per esempio i nomi canonici di DELTA). Parametri in testa allo script; scrive anche `confronto_output.csv`.

## Convenzioni adottate (accettate da DELTA online)

| Aspetto | Scelta |
|---|---|
| Fuso | tutto in **UTC+1 fisso** (niente ora legale); `GMTLag` = `UTC+1`; `tz_offset = 1` |
| Ora osservazioni | il valore di [Start, End) va all'ora **di fine** (`obs_hour_label = "end"`), come i timestamp FARM a fine ora; `"start"` per PMSS. Convenzione da verificare con chi gestisce il modello |
| Modello | cella interpolata in modo bilineare (`model_interp = "bilinear"`), come `raster::extract` |
| Codice stazione | `<Nat Code><lettera>`, es. `302006a` |
| Nome stazione | come nel DataExtract |
| Region / Siting | nomi ISTAT originali (spazi e `/` ammessi), accenti traslitterati, `;` `*` `_` sostituiti da spazio |
| Area/Type | come nel DataExtract (es. `rural-nearcity`) |
| Coordinate | tutti i decimali |
| Validità EEA | solo `Validity == 1` (`valid_codes = 1L`) |
| Copertura | almeno 75% di ore valide per sampling point (`min_coverage = 0.75`) |
| Valori | 2 decimali, `-999` per i mancanti |
| Unità | tutti gli inquinanti in `ugm-3`, tranne CO (`mgm-3`) e As, BaP, Cd (`ngm-3`); conversioni automatiche |

**Specie**: SO2, CO, NO2, O3, PM10, PM25, Pb, As, BaP, Cd, Ni, C6H6. **NOX è escluso** (DELTA non lo supporta: `KeyError: 'NOX'`).

## Corrispondenza osservazioni-metadati

Il DataExtract non è completo. Ogni sampling point del parquet viene cercato in cascata: stesso SPO, poi stesso SPP, poi stessa stazione+codice+metodo, poi stazione+codice, infine solo stazione. Le informazioni mancanti (NA) si riempiono con il valore più sostenuto dalle ore valide delle altre righe della stessa stazione. Se la stessa stazione ha coordinate, area o tipo diversi, viene **divisa in più file** (`a`, `b`, ...) ordinati per livello strumentale e ore valide.

## Cose da sapere

- Il modello ha 4 ore senza dati a inizio anno (2023-01-01 00:00-03:00: il file del 1° gennaio parte alle 04:00). Accettato: restano `-999`.
- I dati orari EEA sono in UTC+1 senza DST. Attenzione, se usi codice proprio, a sottrarre un'ora con `dhours(1)` o `- 3600` e non con `hours(1)` di lubridate su POSIXct in `Europe/Rome`: genera NA a marzo e un'ora doppia a ottobre.
- Aggregazioni EEA `day`/`var` (benzene, metalli): il valore è ripetuto su ogni ora dell'intervallo.
- Tutti gli avvisi per esteso sono in `avvisi.txt`; le stazioni non scritte, con il motivo, in `stazioni_scartate.csv`.

## Note sui dati

- Le ore 00:00-03:00 del 1 gennaio possono mancare nei file FARM (il primo file parte alle 04:00): restano `-999`; `tools/check_model_time.R` elenca le ore senza modello.
- Se confronti con codice tuo: i dati orari EEA sono in UTC+1 senza ora legale; sottrai un'ora con `dhours(1)` o `- 3600`, non con `hours(1)` di lubridate su POSIXct in `Europe/Rome` (NA a marzo, ora doppia a ottobre).
- `tools/compare_outputs.R` confronta due cartelle di output (usa tolleranza `0.0101` per gli arrotondamenti).


