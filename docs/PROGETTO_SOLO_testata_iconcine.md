# SOLO Recorder — progetto iconcine della testata

Stato: approvata da Paolo e realizzata il 2026-10-06 (SOLO Recorder, testata a icone).

## Problema
In testata convivono tre stili: icone (Save, Undo, Redo, Pin, Toolbar), scritte in scatole di
larghezze diverse (Regioni, FX, Video, Mini, Compact, Expanded, REAPER, ?) e un selettore a
parte sulla seconda riga (Sessione | Telecomando). FX in Telecomando e' una scatola vuota e scura.
Il risultato e' dispersivo e i pulsanti a scritta sembrano "incompleti" accanto alle icone.

## Regola unica
- Ogni comando della testata e' una **cella 28 x 24** con un'icona disegnata (area 16 px, tratto 2 px).
- Le celle stanno in **pillole**: gruppi con un solo bordo arrotondato e una riga sottile fra le celle.
  Spazio di 8 px fra le pillole.
- Stati, uguali per tutti:
  - normale: fondo scuro, icona grigio chiaro;
  - acceso / scelto: fondo azzurro (come oggi le schede), icona bianca;
  - non disponibile: icona al 35% (si vede ancora cosa sarebbe), nessun riquadro vuoto;
  - passaggio del mouse: fondo un po' piu' chiaro; la spiegazione resta nella barra in basso e nella guida ?.
- Niente piu' scritte in testata fuori dallo stato (STOP / REC) e dal timecode.

## Disposizione (una riga sola, y = 8)
Sinistra = il progetto e la sessione; destra = la finestra.

| Pillola | Celle | Icona |
|---|---|---|
| Progetto | Save · Undo · Redo | dischetto (pallino ambra se il progetto non e' salvato, `IsProjectDirty`) · freccia indietro · freccia avanti (spente se `Undo_CanUndo2` / `Undo_CanRedo2` sono vuoti) |
| Modalita' | Sessione · Telecomando | cartella (ZP SOLO SESSION) · telecomando (rettangolo con tasti e onde) |
| Sessione | Regioni · FX · Video | parentesi di regione con fascia · tre cursori di mixer (catena effetti) · cinepresa |
| Viste | Mini · Compact · Expanded | stessa finestrella con 1, 2, 3 file dentro |
| Finestra | Toolbar · REAPER | finestrella con la fila in basso · finestra con freccia giu' (su quando REAPER e' nascosto) |
| Aiuto | ? · Pin | punto di domanda nel cerchio · **puntina** (in alto a destra, come in REAPER: inclinata e grigia = libera, dritta e azzurra = sempre sopra) |

Larghezze: sinistra 8 celle (224 px), destra 7 celle (196 px) + spazi: circa 480 px in tutto.
Ci sta anche in Mini (720 px) con margine, quindi **la puntina va in alto a destra** come in REAPER
e non serve spostarla altrove.

## Seconda riga
Si libera: STOP / REC a sinistra con accanto, piccolo, "· Telecomando" o "· Sessione"
(la modalita' resta scritta, oltre al colore antracite di sfondo), timecode a destra.
Terza riga (Compact, Expanded) invariata: traccia, regione, take, pre-roll.

## Disegno delle icone (gfx, senza font)
Funzione unica `draw_header_icon(kind, cx, cy, s)` gia' esistente, estesa con: folder, remote,
regions, fx, video, view1/view2/view3, reaper_down/reaper_up, help, pin_on/pin_off.
Solo rettangoli, triangoli, archi e linee, tratto 2 px, cosi' restano nitide a 16 px.

## Fuori dalla testata (stessa regola, secondo passo, se piace)
- Toolbar in basso: stesse pillole con icona + scritta corta (li' c'e' spazio).
- PRE e lucchetto sul REC restano distintivi tondi: sono "sul" REC, non comandi di testata.

## Verifiche previste
- Simulazione fuori REAPER: nessuna cella fuori finestra o sovrapposta in Mini / Compact / Expanded.
- Guida ?: ogni cella ha la sua spiegazione (le chiavi AIUTI restano le stesse).
- Help solo_recorder.html: tabella della testata con le icone descritte a parole.
