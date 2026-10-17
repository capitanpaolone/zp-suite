# Avanzamento — notifiche non bloccanti ZP Suite

Data: 2026-10-16  
Repository: `/Users/paolob/Documents/ZP/zp-suite`  
Installazione di prova: `/Volumes/DiscoM28T/Reaper26_test`

## Verifica e modifiche

- In `ZP Studio Suite/19_Report_Minuti_Voce.lua`, il salvataggio riuscito apriva un `ShowMessageBox` modale sopra la finestra che aveva già avviato l'azione. Ora l'esito resta nella finestra Report Minuti Voce: pannello verde leggibile, testo a capo, percorso HTML e conteggi; rimane visibile finché non arriva un nuovo esito. Gli errori di scrittura conservano il popup bloccante.
- In `ZP Studio Suite/23_ZP_Chain_Builder.lua`, dopo le azioni di trasformazione/riparazione il report è già presentato nella finestra Chain Builder; rimossi i popup che lo ripetevano e bloccavano REAPER. Il popup di conferma prima di applicare Check / Repair resta perché richiede una scelta.
- Gli help italiano e inglese non documentano questi popup; nessun aggiornamento help necessario.

## Verifiche

- `luac -p` superato su entrambi i file modificati; `git diff --check` senza errori.
- Le copie in Reaper26_test differivano dal repository prima della modifica. Le versioni sostituite sono conservate in `/private/tmp/zp-suite-notifiche-20261016/`; ora gli SHA-256 delle copie installate coincidono con quelli dei due sorgenti nel repository.
- La scansione ha rilevato altri `ShowMessageBox` informativi in script autonomi o riepiloghi che includono anche errori; questa modifica si è limitata ai due casi con una finestra applicativa che può già mostrare il risultato. Le conferme e gli errori restano modali.

Nessun commit o push.
