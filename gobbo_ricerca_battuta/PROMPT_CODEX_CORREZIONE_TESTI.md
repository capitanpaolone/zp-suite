Sei il collaboratore di Paolo Balestri sulla ZP Studio Suite. Rispondi in italiano, testi chiari e diretti. Lavoro breve e preciso: correggi SOLO quello che e' elencato qui.

REPO: ~/Documents/ZP/zp-suite. Leggi le ultime 15 righe di gobbo_ricerca_battuta/MEMORIA.md e la sezione "REAPER" di ANTI_REGRESSIONE.md.
REGOLE: niente commit/push/bump. Mai `git stash`. Backup in gobbo_ricerca_battuta/backup/<file>_prima_testi_2026-10-09.lua prima di toccare ogni file. Una riga nel registro di MEMORIA.md alla fine.

OBIETTIVO: 36 testi passati a T("...") non hanno traduzione in ZP Studio Suite/lang/en.txt, quindi in inglese restano in italiano. In ITALIANO ogni frase deve uscire IDENTICA a oggi (stessi spazi, punteggiatura, a capo).

REGOLA PER LE FRASI SPEZZATE: quando una frase e' fatta di pezzi incollati attorno a un valore (nome, numero, versione, slot), riscrivila come UNA frase con segnaposto:
  prima:  T("Toolbar \"ZP Studio Suite\" nella ") .. dove .. T(" (Switch toolbar o View > Toolbars); ...")
  dopo:   string.format(T("Toolbar \"ZP Studio Suite\" nella %s (Switch toolbar o View > Toolbars); ..."), dove)
Nel catalogo va la frase intera con %s/%d, tradotta intera (in inglese l'ordine delle parole puo' cambiare). Il valore inserito (es. "toolbar principale") se e' un testo va tradotto a parte con T.

ELENCO (file:riga, testo attuale fra apici; i numeri di riga possono essersi spostati di poco):
02_Gobbo_Verticale.lua:1926 e 03_Gobbo_Orizzontale.lua:1351  'Testo (usa \n per andare a capo):,extrawidth=700'
   -> nel catalogo la chiave ha la barra rovesciata raddoppiata: correggi la riga del catalogo (la chiave deve coincidere col testo che T riceve; "\n" qui e' letterale, due caratteri). Tieni ",extrawidth=700" identico anche nella traduzione.
33_Benvenuto_Controllo_Installazione.lua (riga Toolbar ed effetti, ~414-433):
   'toolbar principale' | 'Toolbar "ZP Studio Suite" nella ' + ' (Switch toolbar o View > Toolbars); catene di effetti e preset al loro posto.' (unire con %s)
   'Scritta nella ' + '. Ultimo passo: chiudi e riapri REAPER. Fino ad allora non aprire Customize toolbars (la scrittura andrebbe persa).' (unire con %s)
   'Da installare: toolbar "ZP Studio Suite" (pronta dopo un riavvio di REAPER), catene di effetti del SOLO Recorder e preset del Chain Builder.'
   ', aperta o chiusa.' (fa parte di un messaggio OSARA: unisci la frase intera con %s) | 'Come si fa'
33 (riga Toolbar ZP Colori, ~443-455): 'Nella Floating toolbar ' + ': modo Item/Traccia/Tutto, 20 colori, Togli.' (unire con %s) | 'Chiesta: lancia Installa (32) e riavvia REAPER.' |
   "Non serve per forza: i colori ci sono gia' nella finestrella ZP Colori (tavolozza nella toolbar ZP). Installala se vuoi i colori sempre a vista, per esempio accanto al trasporto." | 'Come si usa'
33 (riga Cue Navigator, ~463-479): "Non serve: il Harmonic Space Carver non e' installato (pacchetto ZP Voce)." | 'Acceso, e parte da solo a ogni apertura di REAPER.' |
   "Parte a ogni apertura di REAPER, ma adesso e' spento: avvialo ora." | "Acceso adesso, ma alla prossima apertura di REAPER non ripartira': mettilo all'avvio." | 'Avvia ora' | 'A ogni apertura'
33 (riga ZP Speech, ~492-509): "Solo su Mac. Altrove crea l'SRT con il tuo whisper e parti da Abbina." | "Installato: 29 Trascrivi crea l'SRT dal WAV con whisper (MacWhisper)." |
   'Installato, ma per trascrivere serve MacWhisper in Applicazioni (aprilo una volta).' | 'Facoltativo, serve a Trascrivi (29). Prima di installarlo serve: ' + <elenco> (unire con %s) |
   'Facoltativo, serve a Trascrivi (29). Installa: il Terminale scarica e installa tutto da solo.' | 'Aggiorna'
33 (righe SWS e js_ReaScriptAPI, ~522-533): 'Installata (' + versione + ')' (unire: "Installata (%s).") |
   'Consigliata: copia-incolla nei pannelli, file che si aprono, secondi del pre-roll del SOLO.' | 'Consigliata: scelta cartelle di sistema, finestra del SOLO sempre sopra. Si installa da ReaPack.'
34_ZP_Set_Comandi.lua: ~351 '" e\' gia\' in uso.' (con il nome del set prima: frase intera '"%s" e\' gia\' in uso.') |
   ~392 ' scorciatoie.' (parte di 'Salvato "%s" con %d scorciatoie.': frase intera) |
   ~445-446 '" in archivio?\n\nNon si cancella: va nella cartella KeyMaps/Archivio ' + 'e sparisce da questo elenco. Per riaverlo, rimettilo in KeyMaps (Apri cartella).' (frase intera 'Metto "%s" in archivio?\n\n...') |
   ~492 "Mando SOLO l'elenco delle " (parte della domanda di Spiega con l'AI: frase intera con %d e i nomi dell'agente come %s)
   Controlla che le voci vecchie a pezzi rimaste nel catalogo e non piu' usate vengano tolte.

CONTROLLO AUTOMATICO (da aggiungere in gobbo_ricerca_battuta/test/test_catalogo_en.lua): per ogni file .lua di ZP Studio Suite trova i T("...") con testo letterale e verifica che il testo sia una chiave del catalogo (stessa decodifica degli escape Lua). Deve fallire se ne manca uno, con file e riga. Oggi deve passare (0 mancanti).

VERIFICHE PRIMA DI DIRE "FATTO":
1. `bash gobbo_ricerca_battuta/test/run_all.sh` -> TUTTO OK
2. `bash gobbo_ricerca_battuta/test/fumo_tutte.sh` -> FINESTRE: TUTTE OK (it + en)
3. Italiano identico: per ogni frase unita, mostra in 1 riga il testo prima/dopo in italiano (devono coincidere).
4. Installa in REAPER i file toccati (Scripts/ZP Suite/ZP Studio Suite/ e lang/en.txt), dopo aver controllato che le copie installate siano quelle registrate in MEMORIA.
Poi riassumi a Paolo in 4 righe: quanti testi sistemati, quante frasi unite, risultato dei controlli, come provarlo (33 Benvenuto > Lingua della Suite: English, riapri il Benvenuto e Set Comandi).
