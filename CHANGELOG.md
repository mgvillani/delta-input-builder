# Changelog

Tutte le modifiche rilevanti del progetto sono elencate qui, dalla più recente.
Formato ispirato a [Keep a Changelog](https://keepachangelog.com/it/1.1.0/).

## [0.1.0] - 2026-11-05

Prima versione pubblica.

### Funzioni
- Costruzione degli input legacy del DELTA Tool (`startup.ini`, `obs/`, `mod/`) da osservazioni EEA (parquet E1a), `DataExtract.csv`, NetCDF FARM e limiti ISTAT.
- Abbinamento dei sampling point ai metadati in cascata (SPO, SPP, stessa stazione+codice+metodo, stazione+codice, stazione); valori mancanti completati con quelli degli altri record della stessa stazione.
- Stazioni divise in più file (`a`, `b`, ...) quando coordinate, area o tipo differiscono.
- Soglia di copertura (`min_coverage`) e codici di validità EEA accettati (`valid_codes`).
- Interpolazione del modello `nearest` o `bilinear` (`model_interp`).
- Convenzione oraria: fuso unico in uscita (`tz_offset`, `GMTLag` = `UTC+1`), etichetta oraria dei dati osservati (`obs_hour_label`).
- Nomi di regione e comune ISTAT mantenuti (spazi e `/` inclusi), con accenti traslitterati e caratteri problematici sostituiti.
- Unità di misura per inquinante con conversioni automatiche (osservati e modello).
- Rapporto delle stazioni scartate (`stazioni_scartate.csv`) e degli avvisi (`avvisi.txt`).
- Strumenti: `tools/compare_outputs.R` (confronto tra due cartelle di output) e `tools/check_model_time.R` (ore senza dati del modello).
- Test su dati sintetici: `tests/test_synthetic.R`.

### Language and layout
- Code comments and all screen messages are in English; the output report files are `discarded_stations.csv` and `warnings.txt` (the comparison tool writes `comparison_output.csv` and `comparison_hours.csv`).
- The example data folder is `data/` (previously `dati/`).
- README in English (`README.md`) and Italian (`README.it.md`).

### Notes
- Specie NOX non supportata da DELTA: esclusa.
- Senza garanzie e senza supporto (licenza MIT).

<!--
Per le versioni successive, aggiungi in cima una sezione come:

## [0.1.1] - AAAA-MM-GG
### Corretto
- descrizione dell'errore corretto
### Aggiunto
- nuova funzione
### Modificato
- cambiamento di comportamento
-->
