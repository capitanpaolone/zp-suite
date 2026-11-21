# Prodotti in maturazione (beta) — NON inclusi nella versione pubblicata

Regola: vedi `gobbo_ricerca_battuta/ANTI_REGRESSIONE.md`, «Versioni, sincronizzazione e pubblicazione».

**Dal 2026-11-21 (regola di Paolo):** questi prodotti si committano e, alla pubblicazione, escono anche online
segnalati come **Beta**, invece di restare fuori. Decisione di Paolo (2026-11-21): la 2.6.8 esce senza le beta; nella **2.6.9** si preparano come
pacchetti Beta (oggi sono `@noindex` o esclusi dall'indice) e si toglie l'aggiunta a parte in `tools/beta_in_prova.txt`.
Questi prodotti non fanno parte dell'avanzamento: le loro modifiche non fanno scattare la versione e non vanno
nel `@provides` del 00. Prima di ogni pubblicazione rileggere questo elenco, aggiornarlo e riportarlo in README e
note di rilascio come «Non incluso in questa versione». Esce da qui solo per decisione di Paolo.

Aggiornato: 2026-10-18 (compilato da Claude dai file del repo; stato e «cosa manca» da confermare con Paolo)

| Prodotto | Dove vive | Perche' non e' nella release | Cosa manca |
|---|---|---|---|
| 36 ZP Montaggio Parlato (+ `ZP_Montaggio.lua`) | `ZP Studio Suite/36_ZP_Montaggio_Parlato.lua` (`@noindex`) | Prototipo «prova, Fase 0+1»: sgrossatore del parlato; non distribuito | Da confermare. Progetto in `docs/PROGETTO_22_Centrale_Montaggio_Parlato.md` |
| ZP BrownSlope Dynamic Guard | `ZP Lab/` (esclusa dall'indice ReaPack) | LEGGIMI di ZP Lab: «non e' ancora una beta», non pubblicare finche' non regge una verifica | Da confermare. Vedi `ZP Lab/LEGGIMI.txt` |
| ZP Click & Attack Softener | `ZP Lab/ZP Click & Attack Softener.jsfx` (`@noindex`, `v0.1`) | Prototipo di laboratorio per de-click lingua/saliva pre-catena e arrotondamento attacchi post-catena con lookahead 6,5 ms (PDC) | Da provare in REAPER su riprese vocali reali pre e post Magic Voice |
| ZP Speech Engine | `speech-engine/` (esclusa dall'indice) | Fase 1 con MacWhisper in lavorazione; OpenAI Whisper su Windows/Linux sperimentale; si installa dal Benvenuto (33) o a parte con `install_macos.sh` / `install_windows.ps1` | Da confermare. Vedi `docs/ZP_Speech_Engine_Project.md` |
| ZP Clean & Paint (beta 1.0.1) | Tre Lua in ZP Voce/ (tutti @noindex); motore esterno nel progetto locale zp-voice-model-lab | Candidata 2.6.9 (come Beta); il motore AI resta in sviluppo e fuori dal pacchetto ReaPack | Validazione completa del motore e del flusso REAPER; provenienza in docs/PROVENIENZA_2.6.8.md |

Nota: `gobbo_ricerca_battuta/` e' la cartella di lavoro e memoria degli agenti, non un prodotto.

Uscito dalla maturazione: ZP BrownSlope Prism, per decisione di Paolo del 2026-11-13. Ora e' `ZP Misura/ZP BrownSlope Prism.jsfx` (1.0), nella candidata 2.6.7.
