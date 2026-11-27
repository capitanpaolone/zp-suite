# Prodotti in maturazione (BETA) — Suite 2.6.9

Regola: vedi `gobbo_ricerca_battuta/ANTI_REGRESSIONE.md`, «Versioni, sincronizzazione e pubblicazione».

**Nessun prodotto è oggi in maturazione.** Decisione di Paolo, 2026-11-26: escono dalla beta ZP Clean & Paint, ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP Click & Attack Softener e ZP Speech Engine. L'etichetta BETA è stata tolta da titoli, finestre, guide IT/EN e README. ZP Magic Voice LAB mantiene il nome «LAB» per scelta di Paolo (non è un'etichetta beta).

Il registro resta per i prossimi prodotti non conclusi: si elencano qui con requisiti e cosa manca, e le modifiche ai soli beta non fanno scattare la versione della Suite.

## Usciti dalla maturazione il 2026-11-26 (requisiti e limiti da mantenere in README, guide e note di rilascio)

| Prodotto | Dove vive | Requisiti e limiti rimasti |
|---|---|---|
| ZP Montaggio Parlato (0.1.0) | `ZP Studio Suite/36_ZP_Montaggio_Parlato.lua` e `ZP_Montaggio.lua` | Richiede ZP Studio Suite e runtime ZP Speech installato dal 33. Collaudato su macOS; PDF richiede Poppler, Incolla SWS. |
| ZP BrownSlope Dynamic Guard (0.5-assist-dev) | `ZP Lab/ZP BrownSlope Dynamic Guard.jsfx` | DSP autonomo. Cue Navigator facoltativo per il pulsante di aiuto. Verificare in sessioni reali prima di una consegna. |
| ZP Click & Attack Softener (1.4) | `ZP Lab/ZP Click & Attack Softener.jsfx` | DSP autonomo (Macro Click + Micro-Click spettrale STFT a tasche locali `~940 Hz` con `Freq Skew` continuo `380 Hz–2,6 kHz` e `Micro %` automatizzabile + Attack Softener). Cue Navigator facoltativo per il pulsante di aiuto. Verificare su riprese vocali reali pre e post catena. |
| ZP Speech Engine | `speech-engine/` | Runtime installato separatamente dal Benvenuto (33), non è un pacchetto ReaPack; Windows/Linux sperimentali. |
| ZP Clean & Paint (1.0.1) | Tre Lua in `ZP Voce/`; motore nel progetto esterno `zp-voice-model-lab` | Il pacchetto ReaPack contiene le action. Motore, ambiente Python, preset e modelli non sono distribuiti con la Suite e restano in sviluppo. |

Nota: `gobbo_ricerca_battuta/` e' la cartella di lavoro e memoria degli agenti, non un prodotto.

Uscito dalla maturazione in precedenza: ZP BrownSlope Prism, per decisione di Paolo del 2026-11-13. Ora e' `ZP Misura/ZP BrownSlope Prism.jsfx` (1.1), distribuito con la 2.6.8.
