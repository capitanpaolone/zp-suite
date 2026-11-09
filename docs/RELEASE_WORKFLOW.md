# Ciclo di lavoro delle release ZP Suite

## Una storia Git, tag per le release

Il repository è la fonte unica. Ogni release pubblicata riceve un tag immutabile (`v2.6.6`, `v2.6.7` e così via). Il tag identifica esattamente i file distribuiti; non serve conservare una copia completa separata per ogni versione. Le copie di sicurezza sul Lacie servono al recupero e non diventano nuove sorgenti di lavoro.

Mentre si prepara una versione, usare due worktree collegati allo stesso repository: uno detached sul tag dell’ultima release e uno sul ramo della prossima. In questo assetto, oggi, `zp-suite-2.6.6-online` resta al tag `v2.6.6` e `zp-suite-2.6.7` lavora sul ramo `release/2.6.7`.

## Preparare la release successiva

1. Creare il ramo della prossima release dal tag pubblicato più recente. Per la 2.6.8, partire da `v2.6.7` dopo la sua pubblicazione.
2. Usare REAPER sul Mac come installazione di riferimento beta. Confrontare i file installati con il tag base e importare soltanto le differenze approvate; non sostituire intere cartelle, perché alcuni componenti possono non essere cambiati.
3. Prima della copia, salvare sul Lacie uno snapshot con data, percorso sorgente e SHA-256. Nel repository registrare proprietario/componente, pacchetto e versione d’origine, data della cattura e versione interna (`@version` o intestazione). Se la versione di download non si può provare, dichiarare il contesto installato senza presentarlo come dato certo.
4. Aggiornare solo i componenti modificati. Le loro versioni ReaPack restano indipendenti dal numero della Suite; i componenti invariati mantengono la propria versione. Le nuove action o risorse entrano nel `@provides` del pacchetto principale.
5. La versione complessiva della Suite è il `@version` di `00_Apri_Help_ZP_Studio_Suite.lua`. Aggiornare README, changelog e guida soltanto con modifiche effettivamente integrate; tenere la voce della prossima release marcata come «in preparazione» fino alla pubblicazione.
6. Prima della pubblicazione, confrontare il pacchetto candidato con il tag base e con l’installazione REAPER, completare i collaudi e rigenerare/controllare `index.xml`. Commit, push, tag e ReaPack richiedono il via di Paolo.
7. Dopo la pubblicazione, il nuovo tag diventa il riferimento. Archiviare la vecchia worktree online sul Lacie se serve liberare spazio; non cancellare il tag. Creare la worktree della release successiva dal tag appena pubblicato.

## Regola per modifiche parziali

Una release può cambiare un solo componente o aggiungerne uno nuovo. La patch deve quindi essere per file/componente: si mantengono gli altri file dal tag base e si aggiornano versioni, `@provides` e documentazione solo dove serve. I report di provenienza aiutano a capire perché un file installato è diverso e impediscono che una successiva copia completa cancelli lavoro già consolidato.
