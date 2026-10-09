ZP Studio Suite for REAPER

Questa e' la cartella installata della suite.
La gestisce ReaPack: gli aggiornamenti arrivano da li'
(Extensions > ReaPack > Synchronize packages).

Non modificare manualmente questi file se non sai esattamente cosa stai
facendo: un aggiornamento li sostituisce.

Primi passi:
- dall'Action List apri "33 Benvenuto" (si apre anche da solo la prima volta
  che usi uno strumento ZP): dice cosa e' pronto e cosa no, con il pulsante
  per sistemarlo (toolbar ed effetti, Cue Navigator del Carver, ZP Speech,
  estensioni facoltative, interfaccia web).

Documentazione:
- apri help/index.html
- oppure esegui 00_Apri_Help_ZP_Studio_Suite.lua dalla Action List.

Toolbar:
toolbar/ZP_StudioSuite.ReaperMenu
Customize toolbar > Import > ZP_StudioSuite.ReaperMenu
Diciassette pulsanti (installali con 32 Installa toolbar), icone ZP a tre stati.
Le 23 action operative hanno un'icona dedicata.
Colori: 35 ZP Colori (pulsante tavolozza) e' una finestrella con modo Item,
Traccia o Tutto, 20 colori e Togli colore. Selezioni, clicchi un colore.
La stessa cosa come toolbar fissa (facoltativa) si installa dal 33 Benvenuto.

Set di scorciatoie: 34 ZP Set Comandi (pulsante tastiera) mostra cosa fa ogni
set, salva i tasti attuali come set e passa da un set all'altro (video, Pro Tools, Logic, tuoi). Cambia solo i tasti, con
backup automatico; il set vale dal riavvio di REAPER.


COMPONENTI OPZIONALI

La suite funziona su un REAPER pulito, senza estensioni. Non c'e' niente da
installare prima. Le estensioni qui sotto non sono richieste: aggiungono
funzioni, e quando mancano la suite usa da sola una strada alternativa.

SWS / S&M (sws-extension.org)
  Senza: niente copia-incolla da tastiera nei campi di testo dei pannelli,
  e i pulsanti che aprono un file - l'help, il log del Probe Guard, il
  report - non aprono niente.
  Con: copia e incolla funzionano, e i file si aprono nell'applicazione
  di sistema. Il SOLO Recorder regola i secondi del pre-roll (senza SWS il
  pre-roll si regola da Options > Metronome/pre-roll di REAPER).

js_ReaScriptAPI (da ReaPack)
  Senza: per scegliere una cartella la suite chiede il percorso a mano
  invece di aprire il pannello di sistema; la sincronizzazione con il
  Region/Marker Manager di REAPER non e' disponibile; la finestra del SOLO
  Recorder non resta sopra le altre; la lettura del tasto Caps Lock non e'
  disponibile.
  Con: pannello di sistema per le cartelle, selezione delle regioni
  sincronizzata, finestra sempre in primo piano.

Interfaccia web di REAPER (Preferences > Control/OSC/web > Web browser interface)
  Serve solo alla versione web del SOLO Recorder (globo in testata): la
  pagina zp_solo.html e il motore ZP_SOLO_Web_Motore li prepara il SOLO.

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
