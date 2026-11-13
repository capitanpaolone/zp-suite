## Protocollo di Pulizia Ablativa (Zero Regressioni)

Quando viene richiesta una pulizia ablativa del codice (rimozione di scorie di sviluppo senza alterare funzionalità o resa grafica), applica rigorosamente le regole seguenti:

### A. Regola Zero: Backup obbligatorio prima di ogni modifica
1. **Non modificare mai alcun file prima di aver creato una copia di sicurezza.**
2. Prima di toccare il primo file della sessione:
   - Verifica che lo stato Git sia pulito (`git status`) e annota l'hash `HEAD` corrente.
   - Crea una directory di backup fuori dal tracciamento o in area dedicata con timestamp, ad esempio:
     `mkdir -p .backup_ablativo/$(date +%Y%m%d_%H%M%S)`
   - Copia ogni file target nella cartella di backup **preservando il percorso relativo** (`rsync -R <percorso_file> .backup_ablativo/<timestamp>/`) e calcola lo `shasum -a 256` dell'originale prima di qualsiasi scrittura.
   - Aggiungi `.backup_ablativo/` a `.git/info/exclude` (senza sporcare `.gitignore` tracciato) affinché i backup restino locali e intatti.
3. Non eseguire `git commit` o `git push` senza esplicita autorizzazione dell'utente.

### B. Vincoli Funzionali e Grafici (Inviolabili)
- **Zero perdita funzionale:** Logica, gestione errori, Undo/Redo, accessibilità (OSARA/NVDA) e code asincrone devono restare identici.
- **Pixel-Perfect:** Non alterare mai coordinate, dimensioni, colori, palette, font, spaziature, chiavi di localizzazione (`ZP_Lingua.lua`, `lang/en.txt`) o blocchi `@gfx` nei JSFX.
- **Contratti di persistenza:**
  - Non rinumerare, rinominare o rimuovere slider pubblici JSFX.
  - Non modificare nomi o struttura di `ExtState`, `Project ExtState`, `P_EXT`, GUID o schema JSON v1 di ZP Speech.
  - Non rompere i caricamenti via `dofile`, `debug.getinfo`, `@provides` e `index.xml`.

### C. Perimetro dell'Ablazione (Cosa rimuovere vs Cosa lasciare)
- **Rimuovi:**
  - Funzioni locali (`local function`) e variabili locali mai lette/chiamate.
  - Rami `if false` o codice irraggiungibile.
  - Stampe di debug dimenticate (`reaper.ShowConsoleMsg`, `print` temporanei) e blocchi di codice commentato obsoleto.
  - Letture API REAPER ripetute inutilmente nello stesso frame dei cicli `reaper.defer()` o `@gfx`/`@block`.
- **Non toccare:**
  - Fallback per piattaforme diverse (Windows/macOS/Linux) o controlli di presenza per `SWS`, `js_ReaScriptAPI` e `OSARA`.
  - Non estrarre nuovi file condivisi senza richiesta esplicita.

### D. Flusso operativo per singolo file
1. Esegui il backup con hash SHA-256 del file target.
2. Esegui un'analisi statica completa e presenta la lista delle rimozioni divisa in: **Sicure**, **Ottimizzazioni locali di loop**, **Dubbie/Legacy** (chiedi conferma sulle dubbie prima di toccarle).
3. Applica le sole modifiche sicure con diff minimi.
4. Verifica la sintassi (`luac -p` per Lua, `python3 -m py_compile` e `pytest` per Python) e mostra il riepilogo `git diff --stat`.