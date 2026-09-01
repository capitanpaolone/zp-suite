ZP Studio Suite for REAPER v1.0.5

Questa e' la cartella installata della suite.

Non modificare manualmente questi file se non sai esattamente cosa stai facendo:
gli aggiornamenti sostituiscono la cartella attiva con una copia pulita e
creano prima un backup della versione precedente.

Documentazione:
- apri help/index.html
- oppure esegui 00_Apri_Help_ZP_Studio_Suite.lua dalla Action List.

Toolbar ufficiale:
toolbar/ZP_StudioSuite.ReaperMenu

Le 23 action operative hanno icone ZP dedicate nel formato REAPER a tre stati.

L'installer copia la toolbar anche in:
MenuSets/ZP_StudioSuite.ReaperMenu

Import manuale:
Customize toolbar > Import > ZP_StudioSuite.ReaperMenu

Note v1.0.5:
- Project Viewer mostra marker e regioni su righe distinte.
- Regioni Export mostra marker e item/regioni su righe distinte.
- Regioni Export usa input nativo REAPER per rinominare le righe regione quando serve, preservando Caps Lock e testo incollato.
- Coda Render Mixdown conserva nomi regione con punti, per esempio 1.1 -> 1.1.mp3.
- Python non serve per installare.
- SRT Tools apre un convertitore HTML locale e offline dalla Action List.

Note di compatibilita':
alcune chiavi interne, metadata, nomi traccia o stringhe tecniche possono
mantenere il nome storico RythmoBand/Rythmo Band. Sono lasciate apposta per
continuare ad aprire progetti creati prima del cambio nome.


ZP Shared Bus / plugin inclusi
- ZP BUS Chain 1.2.2
- ZP Spoken Finish 3.9.7
- ZP Harmonic Space Carver v2X
- ZP Voice-Music Probe 1.1
- ZP Master Pro v2.44
- ZP Subliminal Presence Layer

I plugin sono installati in Effects/ZP_Paolo Balestri JSFX. Chain Builder prepara la catena e Probe Guard mantiene le Probe in fondo al bus. Nessun modulo applica correzioni automatiche via bus: Master Pro misura, interpreta e suggerisce.
