# Gestore Progetto: bozza nomi non applicata

Data: 2026-10-18

## Comportamento

- I nomi digitati nell'anteprima sono modifiche in bozza finché non si usa `Crea Selez.` o `Crea Regioni`.
- `Crea Selez.` aggiorna le regioni esistenti o crea quelle mancanti soltanto per le righe selezionate; senza righe selezionate, `Crea Regioni` opera su tutte le righe di regione.
- `Salva` applica soltanto i nomi in bozza alle rispettive regioni: aggiorna quelle esistenti e crea solo le regioni mancanti per le righe con un nome da applicare. Non ricrea le altre regioni e non aggiunge marker.
- Se si chiude con nomi non applicati, `Sì` li applica e salva il progetto prima di uscire; `No` torna al Gestore. La bozza resta salvata mentre si torna alla finestra.

## File e impronte

- Script: `ZP Studio Suite/17_Crea_Regioni_Export_da_Item_Nominati.lua`
- Help: `ZP Studio Suite/help/index.html` e `ZP Studio Suite/help/en/index.html`
- Runtime REAPER: `/Users/paolob/Library/Application Support/REAPER/Scripts/ZP Suite/ZP Studio Suite/`
- Backup pre-modifica e snapshot aggiornato: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gestore Progetto/unapplied_draft_warning_20261018/`
- Backup locale REAPER: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gestore_progetto_unapplied_draft_warning_20261018/`

## Verifica

- `git diff --check` senza segnalazioni. Questa estensione non è stata collaudata in REAPER.
- L'installazione runtime non è stata aggiornata: la copia installata differisce da `HEAD` per modifiche di lavoro precedenti; regola di `ANTI_REGRESSIONE.md`, confronto installato/HEAD/working tree prima di sostituire.
- Non sono stati modificati progetti REAPER.
