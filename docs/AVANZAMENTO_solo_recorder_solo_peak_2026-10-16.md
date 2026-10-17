# Solo Recorder — pulsante Solo e indicatore peak

Data: 2026-10-16

## Modifiche

- Aggiunto un piccolo pulsante `S` nell’angolo inferiore sinistro del pulsante REC. Attiva/disattiva il solo della traccia di registrazione attiva; in Telecomando agisce sulla prima traccia armata. Da spento usa il grigio degli altri controlli; da acceso è giallo. Le sigle S e PRE sono centrate nei rispettivi pulsanti.
- L’indicatore di peak è azzurro (rosso in clip) e viene disegnato prima delle letture bianche.
- Aggiornate le guide italiana e inglese.
- Installata la versione in `/Users/paolob/Library/Application Support/REAPER/Scripts/ZP Suite/ZP Studio Suite/`.

## Backup

- Backup pre-modifica di sorgente, guide e memoria: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/solo_recorder_solo_peak_20261016/`.
- Archivio storico pre-modifica: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/SOLO Recorder/2026-10-16_solo_peak/pre-change/`. Hash iniziali in `SHA256.pre.txt`.

## Verifica

- Verificare in REAPER il click su `S` in Sessione SOLO e Telecomando, e il contrasto della barretta peak sul meter IN.
- `luac -p` e `git diff --check` superati anche dopo la rifinitura grafica. Non è stata eseguita una prova interattiva in REAPER durante questa modifica.

## Hash finali

- Script Lua: `ddff746e5c7d10f677b24ee4031a16321737f7e4102516d525c29316af2f2b3c`
- Guida italiana: `e7519bd7d4090535b9be8d94e3cb408e04f95e1210ee14153014058a3ccd3797`
- Guida inglese: `a21e260d947bcae6e9444534f01774ded44ea24ed731532fec9dffc26df1fbc9`
- Sorgente e copia installata hanno hash identico. `luac -p` e `git diff --check` superati; nessuna prova interattiva in REAPER.
