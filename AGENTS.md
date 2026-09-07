# AGENTS.md — Indice e Regole Operative ZP Suite

> Repository canonico vivo della ZP Studio Suite e degli 11 effetti JSFX.
> Qualsiasi agente AI che opera su questa codebase deve attenersi a questo indice.

## Regole Fondamentali
1. **Unica Fonte di Verità**: Questo repository (`zp-suite`) è l'unico ambiente di sviluppo vivo. Qualsiasi cartella su volumi esterni (incluso LaCie) è archivio storico in sola lettura.
2. **ReaPack Deploy**: *Una versione = un singolo commit*. Mai riutilizzare lo stesso tag di versione in commit successivi (`reapack-index` scarta le modifiche successive se la versione è già indicizzata).
3. **Nomi e Metadata**: Mai inserire numeri di versione o date nei nomi dei file né nella direttiva `desc:` dei JSFX (ReaPack mostra `desc:` agli utenti). La versione vive unicamente nei metadati di header (`@version`).
4. **Dipendenze Zero**: Gli script Lua non devono avere dipendenze obbligatorie da SWS o js_ReaScriptAPI; ogni estensione deve essere protetta da fallback nativi REAPER.
5. **Autonomia del Deploy**: L'agente prepara e collauda in locale; solo l'utente esegue `git push` e distribuzioni pubbliche.

## Mappa della Documentazione
Per operare sul progetto, consulta esclusivamente il modulo pertinente al task:

- **[`docs/agent/PROJECT.md`](docs/agent/PROJECT.md)** — Scopo della suite, catalogo degli 11 JSFX, elenco degli script Lua e architettura audio/routing.
- **[`docs/agent/CURRENT.md`](docs/agent/CURRENT.md)** — Stato vivo attuale, rami pronti, task aperti e prossimi passi prioritari (nessuna cronologia).
- **[`docs/agent/DECISIONS.md`](docs/agent/DECISIONS.md)** — Decisioni architetturali consolidate e vincolanti (isolamento git, ReaPack, convenzioni corsie marker, report CSV).
- **[`docs/agent/LESSONS.md`](docs/agent/LESSONS.md)** — Bug documentati, errori da non ripetere, regole di threading DSP e compatibilità REAPER 7.77+.
- **[`docs/agent/TOOLS.md`](docs/agent/TOOLS.md)** — Strumenti di verifica sintattica, procedure di indicizzazione ReaPack e requisiti di ambiente.
- **[`docs/agent/ARCHITETTURA_ZP_STUDIO_SUITE.md`](docs/agent/ARCHITETTURA_ZP_STUDIO_SUITE.md)** — Mappa architetturale di sistema della ZP Studio Suite (convenzioni condivise, modello SRT/Cue, Gobbo, SOLO Recorder, dipendenze fra script, debito tecnico), orientata ad agenti AI.

## ZP Remote — documentazione da leggere prima di lavorarci

ZP Remote è il prodotto browser-based (controllo DAW + cue/script sincronizzabile + routing media per ruoli) in fase di progettazione sopra la ZP Studio Suite. La sua documentazione canonica vive in `docs/agent/` insieme al resto:

- **[`docs/agent/CURRENT_ZP_REMOTE.md`](docs/agent/CURRENT_ZP_REMOTE.md)** — punto di ingresso rapido: stato attuale, fase corrente, cosa NON è ancora implementato.
- **[`docs/agent/ARCHITETTURA_ZP_REMOTE.md`](docs/agent/ARCHITETTURA_ZP_REMOTE.md)** — architettura completa (componenti, ruoli/capability, control plane, media plane, Cue Model, diagrammi).
- **[`docs/agent/ROADMAP_ZP_REMOTE.md`](docs/agent/ROADMAP_ZP_REMOTE.md)** — sequenza di fasi (Fase 0 → Fase 6 → Futuro).
- **[`docs/agent/REFERENCES_ZP_REMOTE.md`](docs/agent/REFERENCES_ZP_REMOTE.md)** — riferimenti esterni (SonoBus, AOO, BlackHole, WebRTC, Source-Connect, SessionLinkPRO) con licenze e cosa NON significano.

**Prima di lavorare su ZP Remote**, un agente deve leggere almeno `docs/agent/CURRENT_ZP_REMOTE.md`, `docs/agent/ARCHITETTURA_ZP_REMOTE.md` e `docs/agent/ROADMAP_ZP_REMOTE.md`. Quando il lavoro tocca REAPER/ZP Studio Suite, deve leggere anche `docs/agent/ARCHITETTURA_ZP_STUDIO_SUITE.md`, `docs/agent/PROJECT.md`, `docs/agent/DECISIONS.md` e `docs/agent/LESSONS.md`.

Due regole vincolanti per ZP Remote:

- **Non iniziare una fase successiva della roadmap senza verificare lo stato corrente in `CURRENT_ZP_REMOTE.md`.**
- **Per ZP Remote, distinguere sempre Control Plane e Media Plane. Il REAPER Lua Adapter governa stato/comandi/routing della DAW ma non trasporta PCM realtime.**
