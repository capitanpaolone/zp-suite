# Provenienza — ZP Studio Suite 2.6.8

## Clean & Paint (beta)

- Destinazione: tre action locali in ZP Voce/, tutte marcate @noindex; non aggiunte al @provides del Lua 00 e non distribuite da ReaPack.
- ZP Clean & Paint.lua: la copia installata in REAPER era 1.0.0 (9 novembre 2026); la revisione successiva ZP_Clean_And_Paint_Reaper.lua, 1.0.0 (10 novembre), è stata scelta come base più recente. Il codice comune passa alla 1.0.1: rimuove il fallback assoluto al disco, usa il puntatore utente ZP_Clean_Paint/lab_root_path.txt e verifica CLI, Python e preset prima dell'avvio.
- ZP_Clean_And_Paint_Reaper.lua e ZP_Importa_da_Clean_Paint.lua: provenienza dal progetto motore locale zp-voice-model-lab; le copie d'origine coincidevano byte per byte con quelle installate in REAPER prima dell'aggiunta del solo metadato @noindex.
- Motore collegato: progetto separato zp-voice-model-lab, ancora in sviluppo; CLI, ambiente Python locale e preset sono stati rilevati. Il motore non è copiato nella Suite e non è dichiarato finito né collaudato con questo allineamento.
- Snapshot pre-intervento con SHA-256: /Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/2026-11-21_Clean_Paint_beta_2.6.8_preallineamento/.
- Il Benvenuto 33 mostra la beta e segnala la presenza di CLI, Python e preset; lo stato beta non incrementa il contatore delle attività da fare.
