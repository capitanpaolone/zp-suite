# Allineamento locale ZP Speech — 2026-11-10

La prerelease Suite resta 2.6.7 sul ramo locale `release/2.6.7`.
Aggiornato esclusivamente il pacchetto `zp-speech-engine` nel runtime servizio,
conservando dipendenze, ambiente OpenAI Whisper e modelli esistenti.

## Modifica verificata

Il provider riconosce i modelli `.pt` anche nella cache standard `~/.cache/whisper`.
La cartella modelli ZP ha priorità. Nessun download durante la trascrizione.

## Backup e ricostruzione

- Archivio: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Speech/2026-11-10_allineamento_cache_230448`.
- `speech-runtime-before.tar.gz`: ambiente completo precedente e LaunchAgent.
- `SHA256.json`: hash del backup e snapshot dei sorgenti modificati.
- `speech-source.patch`: differenze Speech rispetto al commit precedente.
- `runtime-after-SHA256.json`: hash dei 16 file Python installati dopo l'aggiornamento.
- `transcription-after.json`: risultato reale dell'audio sintetico di collaudo.
- Aggiornamento eseguito con il Python del runtime: `-m pip install --no-deps --no-cache-dir <checkout>/speech-engine`.
- Riavvio tramite `launchctl kickstart -k gui/501/com.zp.speech-service`.
- Per tornare indietro, fermare il servizio, conservare il runtime corrente,
  estrarre `speech` dall'archivio nella cartella `ZP/runtimes`, ripristinare il plist
  se necessario e riavviare il LaunchAgent. L'ambiente va ripristinato nel suo percorso originale.

## Risultati

- 204 test Python passati, inclusi 26 del provider OpenAI Whisper.
- I test HTTP richiedono accesso localhost; la prima esecuzione nel sandbox
  ha bloccato i socket. Ripetizione con accesso locale autorizzato: tutti passati.
- Tutti i 16 sorgenti Python del runtime coincidono byte per byte con il checkout.
- `doctor --engine openai-whisper`: provider 20250625, modello `small`, timestamp parola disponibili.
- `models`: riconosciuto `openai-whisper:small` già presente.
- Trascrizione end-to-end via servizio HTTP, audio italiano sintetico WAV,
  motore `openai-whisper`, modello `small`, schema ZP validato dal client.
- Testo ottenuto: Questa è una prova del motore di trascrizione, il servizio funziona sul computer locale.
- `git diff --check` sulle modifiche Speech: OK.

Il collaudo usa il client CLI e il servizio reale. Non costituisce una prova
interattiva del pannello di REAPER. Nessuna pubblicazione, push, tag o modifica ReaPack.
Le modifiche Gobbo preesistenti restano fuori dal commit Speech.
