# Prodotti BETA — Suite 2.6.9 in preparazione

Regola: vedi `gobbo_ricerca_battuta/ANTI_REGRESSIONE.md`, «Versioni, sincronizzazione e pubblicazione».

Decisione di Paolo, 2026-11-21: i prodotti indicati qui si pubblicano come **BETA** per provarli con volontari. Clean & Paint, Montaggio Parlato, BrownSlope Dynamic Guard e Click & Attack Softener sono stati pubblicati come pacchetti separati ReaPack nella 2.6.8 e restano inclusi come BETA nella candidata 2.6.9. Restano in maturazione finché Paolo non decide di togliere l'etichetta. Le modifiche ai soli beta non fanno scattare la versione della Suite. I loro requisiti e limiti vanno mantenuti in README, guide IT/EN e note di rilascio.

Aggiornato: 2026-11-21.

| Prodotto | Dove vive | Stato e dipendenze | Cosa manca |
|---|---|---|---|
| ZP Montaggio Parlato (BETA 0.1.0) | `ZP Studio Suite/36_ZP_Montaggio_Parlato.lua` e `ZP_Montaggio.lua` | Pacchetto ReaPack separato; richiede ZP Studio Suite e runtime ZP Speech installato dal 33. Attualmente collaudato su macOS; PDF richiede Poppler, Incolla SWS. | Prove con progetti e copioni reali, verifica del flusso dall'analisi all'Undo. |
| ZP BrownSlope Dynamic Guard (BETA 0.5-assist-dev) | `ZP Lab/ZP BrownSlope Dynamic Guard.jsfx` | Pacchetto ReaPack separato; DSP autonomo. Cue Navigator facoltativo per il pulsante di aiuto. | Sessioni di ascolto e verifica prima di usarlo in consegna. |
| ZP Click & Attack Softener (BETA 0.1) | `ZP Lab/ZP Click & Attack Softener.jsfx` | Pacchetto ReaPack separato; DSP autonomo. Cue Navigator facoltativo per il pulsante di aiuto. | Prove su riprese vocali reali pre e post catena. |
| ZP Speech Engine | `speech-engine/` | Runtime installato separatamente dal Benvenuto (33), non è un pacchetto ReaPack; Windows/Linux sperimentali. | Proseguire il supporto e la validazione dei provider. |
| ZP Clean & Paint (BETA 1.0.1) | Tre Lua in `ZP Voce/`; motore nel progetto esterno `zp-voice-model-lab` | Pacchetto ReaPack separato per le action. Il motore, l'ambiente Python, i preset e i modelli non sono distribuiti con la Suite. | Validare il motore AI e il flusso REAPER. Nell'ambiente locale `pip check` segnala che `rvc-python 0.1.5` richiede `faiss-cpu==1.7.3` e `numpy<=1.23.5`, mentre `requirements.txt` richiede `faiss-cpu>=1.8.0` e `numpy>=1.24`; inferenza RVC non verificata. Provenienza in `docs/PROVENIENZA_2.6.8.md`. |

Nota: `gobbo_ricerca_battuta/` e' la cartella di lavoro e memoria degli agenti, non un prodotto.

Uscito dalla maturazione: ZP BrownSlope Prism, per decisione di Paolo del 2026-11-13. Ora e' `ZP Misura/ZP BrownSlope Prism.jsfx` (1.1), distribuito con la 2.6.8.
