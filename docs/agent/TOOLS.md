# TOOLS.md — Strumenti, Test, CI e Procedure Operative

> Questo documento descrive gli strumenti ausiliari, la catena di compilazione, i test e la procedura di pubblicazione della ZP Suite.

## 1. Procedura di Rilascio ReaPack
La pubblicazione di una nuova versione segue una sequenza rigorosa:

1. **Incremento di Versione**:
   - Per gli script Lua: aggiornare il metadato `@version` nel commento di testata dello script modificato (o del capofila `ZP Studio Suite`).
   - Per gli 11 JSFX: se è modificato solo il metadato (es. `@description`), non alzare la versione. Se cambia la logica audio, alzare la `@version` e aggiornare la riga `desc:` senza aggiungere suffissi di build.
2. **Aggiornamento Note di Rilascio**:
   - Aggiungere il blocco di modifiche in `CHANGELOG.md` e aggiornare la sezione in `STATO LAVORI.md`.
3. **Rigenerazione Indice Locale**:
   - Lanciare lo script `./Pubblica\ ZP\ Suite.command` (oppure `reapack-index --commit`).
   - Lo script esegue:
     - Scansione delle cartelle `ZP Voce`, `ZP Master`, `ZP Misura`, `ZP Studio Suite`.
     - Rigenerazione del file `index.xml`.
     - Validazione della coerenza dell'indice XML.
     - Creazione del commit Git locale.
4. **Push Pubblico [Esclusiva dell'Utente]**:
   - L'agente non esegue `git push`. La pubblicazione remota su GitHub avviene esclusivamente a mano dall'utente.

## 2. Requisiti di Ambiente e Compilatori
- **Python**:
  - Il generatore del sito pubblico e della documentazione richiede tassativamente **Python 3.12 o superiore** (la versione Python 3.10 non è supportata e fallisce la compilazione per incompatibilità sintattiche).
- **reapack-index**:
  - Binary CLI ufficiale di ReaPack (installato nell'ambiente di sistema dell'utente o invocato da script di build).
- **REAPER Compatibility Target**:
  - REAPER 7.77 "Lucky Seven" o superiore come ambiente di collaudo primario.

## 3. Test Statici e Validazione Sintattica
- **Verifica Sintassi Lua**:
  - Validazione statica senza REAPER via interprete standard:
    ```bash
    luac -p "ZP Studio Suite/nome_script.lua"
    ```
- **Verifica Sintassi EEL2 / JSFX**:
  - I file JSFX possono essere validati aprendoli nell'editor interno di REAPER (`Ctrl+E` / `Cmd+E`) oppure testati in runtime locale tramite l'engine YSFX.
- **Verifica Menu e Toolbar**:
  - Il file toolbar ufficiale è `ZP Studio Suite/toolbar/ZP_StudioSuite.ReaperMenu`.
  - Controllare sempre che gli ID azione registrati nella toolbar corrispondano a comandi reali registrati nel `reaper-kb.ini` di collaudo.

## 4. Strumenti Ausiliari Inclusi
- **`00_Apri_Help_ZP_Studio_Suite.lua`**: Script di apertura help HTML offline nel browser di sistema, residente in `ZP Studio Suite/help/`.
- **`27_Pulisci_Installazione_Precedente.lua`**: Utility di autodiagnosi per rimuovere file obsoleti delle vecchie versioni mantenendo intatte le preferenze utente.
- **Log Diagnostico Render**: `ZP_StudioSuite_Render_Debug.log` (generato durante i render delle sezioni per tracciare i tempi di chiusura della finestra).
