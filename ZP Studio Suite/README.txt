ZP Studio Suite for REAPER

Questa e' la cartella installata della suite.
La gestisce ReaPack: gli aggiornamenti arrivano da li'
(Extensions > ReaPack > Synchronize packages).

Non modificare manualmente questi file se non sai esattamente cosa stai
facendo: un aggiornamento li sostituisce.

Documentazione:
- apri help/index.html
- oppure esegui 00_Apri_Help_ZP_Studio_Suite.lua dalla Action List.

Toolbar:
toolbar/ZP_StudioSuite.ReaperMenu
Customize toolbar > Import > ZP_StudioSuite.ReaperMenu
Quattordici pulsanti, icone ZP nel formato REAPER a tre stati.
Le 23 action operative hanno un'icona dedicata.


COMPONENTI OPZIONALI

La suite funziona su un REAPER pulito, senza estensioni. Non c'e' niente da
installare prima. Le estensioni qui sotto non sono richieste: aggiungono
funzioni, e quando mancano la suite usa da sola una strada alternativa.

SWS / S&M (sws-extension.org)
  Senza: niente copia-incolla da tastiera nei campi di testo dei pannelli,
  e i pulsanti che aprono un file - l'help, il log del Probe Guard, il
  report - non aprono niente.
  Con: copia e incolla funzionano, e i file si aprono nell'applicazione
  di sistema.

js_ReaScriptAPI (da ReaPack)
  Senza: per scegliere una cartella la suite chiede il percorso a mano
  invece di aprire il pannello di sistema; la sincronizzazione con il
  Region/Marker Manager di REAPER non e' disponibile; la finestra del SOLO
  Recorder non resta sopra le altre; la lettura del tasto Caps Lock non e'
  disponibile.
  Con: pannello di sistema per le cartelle, selezione delle regioni
  sincronizzata, finestra sempre in primo piano.

OSARA (osara.reaperaccessibility.com)
  Serve alle quattro action 09, 10, 11 e 12, che fanno leggere le battute
  dallo screen reader. Il resto della suite funziona lo stesso.


NOTE DI COMPATIBILITA'

Alcune chiavi interne, metadata, nomi traccia o stringhe tecniche possono
mantenere il nome storico RythmoBand / Rythmo Band. Sono lasciate apposta
per continuare ad aprire progetti creati prima del cambio nome.


ZP SHARED BUS / PLUGIN INCLUSI

- ZP BUS Chain
- ZP Spoken Finish
- ZP Harmonic Space Carver
- ZP Voice-Music Probe
- ZP Master Pro
- ZP Subliminal Presence Layer

Si installano dallo stesso repository ReaPack e finiscono in
Effects/ZP_Paolo Balestri JSFX.

Chain Builder prepara la catena, Probe Guard tiene le Probe in fondo al bus.
Nessun modulo applica correzioni automatiche via bus: Master Pro misura,
interpreta e suggerisce.
