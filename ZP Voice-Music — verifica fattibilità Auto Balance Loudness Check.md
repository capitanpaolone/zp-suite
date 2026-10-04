# ZP Voice-Music — verifica fattibilità Auto Balance / Loudness Check

## Contesto
Candidata feature per ZP Voice-Music: confrontare via ReaScript la loudness di traccia voce e traccia musica (LUFS) sfruttando le nuove azioni "dry run render" di REAPER 7.79, senza dover renderizzare davvero i file. Architettura proposta: JSFX ZP Voice-Music per il trattamento audio (ducking, presenza, spazio), ReaScript companion per misura/confronto/report, sul modello già usato in altri moduli ZP (JSFX + script di supporto).

## Domanda aperta che bloccava tutto
Le azioni native "dry run" di REAPER 7.79 restituiscono un valore leggibile da ReaScript, o mostrano il risultato solo in una finestra pensata per l'uso manuale? Prima di questa verifica non era chiaro (nessuna API `NF_AnalyzeTrackLoudness` risultava mai esistita, vedi sws-extension issue #1169).

## Verifica fatta (11 set 2026, REAPER 7.79 macOS-arm64)
Action IDs trovati in Action List (sezione Main, filtro "stereo loudness dry"):
- 43810: Calculate stereo loudness of selected tracks via dry run render
- 43811: Calculate stereo loudness of selected tracks within time selection via dry run render

Meccanismo confermato funzionante: `reaper.GetSetProjectInfo_String(0, 'RENDER_STATS', tostring(43810), false)` — passando il command ID come stringa esegue prima l'azione sulle tracce selezionate, poi restituisce in `stats` una stringa di risultati.

Con una traccia selezionata contenente audio reale, risultato ottenuto (`ok: true`, `bytes: 113`):

```
FILE:EFXCat;LENGTH:7:16.084;PEAK:-6.002294;LUFSMMAX:-14.494051;LUFSSMAX:-16.048233;LUFSI:-17.948290;LRA:6.000000
```

Campo utile per il confronto voce/musica: `LUFSI` (loudness integrata, standard broadcast). Disponibili anche `LUFSMMAX`, `LUFSSMAX` (picco momentary/short-term) e `LRA` (loudness range) — potenzialmente utili per check aggiuntivi futuri (es. dinamica del letto musicale).

Nota tecnica per il parsing: split prima su `;`, poi su `:` solo per il primo carattere trovato in ciascun campo — `LENGTH` contiene un `:` interno nel formato mm:ss.mmm ("7:16.084"), uno split ingenuo su tutti i `:` lo romperebbe. Il campo `FILE:` non sembra restituire un path reale utilizzabile — da non usare come riferimento.

Con nessuna traccia selezionata / nessun item audio preparato, la chiamata torna comunque `ok: true` ma con stringa vuota (`bytes: 0`) — non è un errore del meccanismo, semplicemente non c'è nulla da misurare.

## Esito
Fattibilità tecnica confermata: il flusso "seleziono traccia → dry run render via azione nativa → leggo LUFSI via ReaScript → confronto" è realizzabile solo con API native (no SWS, no render reali su disco). Sblocca l'intera architettura proposta per "Auto Balance / Loudness Check" in ZP Voice-Music (analisi rapporto voce/musica, preset per destinazione d'uso, checker pre-consegna).

## Prossimo passo (non ancora iniziato)
Scrivere lo script di confronto vero: seleziona traccia voce → misura LUFSI, seleziona traccia musica → misura LUFSI, calcola differenza, confronta con range per profilo (spot radio, YouTube/social, podcast, e-learning, corporate, demo voiceover).