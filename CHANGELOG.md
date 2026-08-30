# Changelog — ZP Suite

Le versioni dei singoli effetti sono indipendenti: le trovi nell'intestazione di
ciascun file e nel gestore pacchetti. Questo file registra la storia della Suite
nel suo insieme.

## Non rilasciato

### Corretto
- Quattro effetti non entravano nell'indice ReaPack: Reference Tone Mirror EQ Pro,
  Oscilloscope 16ch, Harmonic Space Carver e Subliminal Presence Layer White.
  Causa: `reapack-index` riconosce come tag anche `author:` e `version:` scritti
  senza chiocciola nell'intestazione JSFX storica, e le righe di commento indentate
  che li seguivano li rendevano multilinea. Entrambi i tag devono stare su una riga
  sola. Le vecchie righe sono state rinominate in `// Autore:` e `// Versione:`:
  l'informazione resta leggibile, il conflitto sparisce.
- Stessa correzione applicata anche a Loudness Meter e Stagekeeper, che passavano
  per caso ma avevano lo stesso difetto latente.

### Aggiunto
- Repository unico per gli 11 effetti della Suite, in tre categorie: ZP Voce, ZP Master, ZP Misura.
- `LICENSE` (GPLv3) e `NOTICE.md` con la catena di attribuzioni del DSP di terzi.

### Corretto
- **ZP Voice-Music Probe**: la copia in uso nella cartella di lavoro era precedente a
  quella distribuita e non conteneva il fix *v1.1 Role Switch* (cambio ruolo
  VOICE/MUSIC a trasporto fermo, da GUI e da Chain Builder). Eletta come fonte la
  versione corretta.

### Aggiunto
- Pipeline ReaPack: `.reapack-index.conf` e due workflow GitHub Actions.
  `check` valida i pacchetti a ogni push e su ogni pull request; `deploy` rigenera
  `index.xml` a ogni push su master e lo ricommitta da solo.
- `index.xml` iniziale con il nome "ZP Suite" — e' il nome che ReaPack mostra.
  Da qui in avanti il file lo mantiene la CI: non va modificato a mano.

### Modificato
- Rinominati sette file per togliere la versione dal nome: con ReaPack il nome del file
  e' l'identita' del pacchetto e non puo' piu' cambiare dopo la pubblicazione. La versione
  vive ora solo in `@version` e nella riga `desc:`, dove puo' crescere liberamente.
  Rinomina fatta con `git mv`: la storia dei file e' conservata.
- `ZP Subliminal Presence Layer White` mantiene "White": e' un descrittore del tipo di
  layer, non un numero di versione.

### Compatibilita'
- I file gia' installati in `Effects/ZP_Paolo Balestri JSFX/` restano dove sono e non
  vengono toccati: i progetti REAPER esistenti continuano a trovarli. I pacchetti ReaPack
  si installano in una cartella propria, quindi le due serie convivono senza collisioni.

### Note
- Import iniziale con i nomi file storici. La rinomina che toglie la versione dal nome
  avviene nel passo successivo, con `git mv`, prima della prima pubblicazione.
