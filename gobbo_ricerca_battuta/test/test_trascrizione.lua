-- Test della logica pura di 29_ZP_Trascrizione.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/29_ZP_Trascrizione.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
local rows = {
  { path = "/a/nuovo.wav", wav = true, srt = false, markers = 0, texts = 0 },
  { path = "/a/glued-01.wav", wav = true, srt = false, markers = 12, texts = 12 },   -- glue: marker, niente SRT
  { path = "/a/glued-01.wav", wav = true, srt = false, markers = 3, texts = 3 },    -- stesso file, altro item
  { path = "/a/fatto.wav", wav = true, srt = true, markers = 0, texts = 0 },
  { path = "/a/clip.mp3", wav = false, srt = false, markers = 0, texts = 0 },
}
local q = M.to_transcribe(rows)
check("Trascrivi: solo il WAV senza SRT e senza marker", #q == 1 and q[1] == "/a/nuovo.wav")
local r, nm, ns = M.to_retranscribe(rows)
check("Ritrascrivi: tutti i WAV, ogni file una volta", #r == 3 and r[2] == "/a/glued-01.wav")
check("Ritrascrivi: conta gli item con marker (2) e i file con SRT (1)", nm == 2 and ns == 1)
local steps = M.road({ rows[2] }, false)
check("file glued con marker: tappa 1 risulta fatta (il pulsante diventa Ritrascrivi)", steps[1].done)
check("riga di stato: 5 selezionati, 1 da trascrivere, 3 gia' fatti, 1 non WAV",
  M.summary(rows) == "5 selezionati: 1 da trascrivere, 3 gia' fatti, 1 non WAV")
check("riga di stato al singolare", M.summary({ rows[1] }) == "1 selezionato: 1 da trascrivere, 0 gia' fatti")
check("nome breve large-v3", M.model_label("whisperkit:openai_whisper-large-v3-v20240930") == "large-v3")
check("nome breve small", M.model_label("whisperkit:openai_whisper-small") == "small")
check("nome breve parakeet", M.model_label("parakeet-pro:nvidia_parakeet-v3_494MB") == "parakeet-v3")
check("modello vuoto = predefinito", M.model_label("") == "predefinito")
local ms = M.parse_models('{"provider":"macwhisper","models":["whisperkit:a","parakeet-pro:b"],"capabilities":{"input_formats":["wav"]}}')
check("modelli letti dal servizio", #ms == 2 and ms[1] == "whisperkit:a" and ms[2] == "parakeet-pro:b")
check("servizio muto: nessun modello", #M.parse_models("") == 0)
check("lingue", M.lang_label("en") == "Inglese" and M.lang_label("auto") == "Automatica")
check("lingua francese e cinese in tendina", M.lang_label("fr") == "Francese" and M.lang_label("zh") == "Cinese")
check("codice scritto a mano", M.clean_lang_code(" YUE ") == "yue" and M.clean_lang_code("italiano") == nil)
check("lingua sconosciuta mostrata come codice", M.lang_label("nl") == "NL")
check("parakeet e cinese: avviso", M.lang_warning("parakeet-pro:nvidia_parakeet-v3_494MB", "zh") ~= nil)
check("parakeet e francese: nessun avviso", M.lang_warning("parakeet-pro:nvidia_parakeet-v3_494MB", "fr") == nil)
check("whisper e cinese: nessun avviso", M.lang_warning("whisperkit:openai_whisper-large-v3-v20240930", "zh") == nil)
check("nome tradotto", M.translated_name("/a/Episodio01.srt", "it") == "/a/Episodio01.it.srt")
check("nome tradotto da file gia' con lingua", M.translated_name("/a/Ep.zh.srt", "it") == "/a/Ep.it.srt")
check("nome tradotto: cartella con punto", M.translated_name("/a.b/Ep.srt", "en") == "/a.b/Ep.en.srt")
local eng = M.parse_engines('{"engines": [{"engine": "codex", "available": true, "path": "/x", "cloud": true, "login": true, "models": ["gpt-6-luna", "gpt-6-astra"]}, {"engine": "opencode", "available": false, "path": null, "cloud": true, "login": true, "models": []}]}')
check("motori letti", #eng == 2 and eng[1].engine == "codex" and eng[1].available and eng[1].models[2] == "gpt-6-astra" and not eng[2].available)
check("motori: risposta vuota", #M.parse_engines("") == 0)
local d, t = M.progress_from_log("x\nprogress 60/130\nprogress 120/130\n")
check("avanzamento traduzione", d == 120 and t == 130)
local sh = M.batch_script("/tmp/d d", { { path = "/a/l'x.wav", cmd = "cmd1" }, { path = "/b.wav", cmd = "cmd2" } }, "ZP T", "Prova")
check("coda: cartella e percorsi con apici quotati", sh:find("D='/tmp/d d'", 1, true) and sh:find([['/a/l'\''x.wav']], 1, true))
check("coda: ogni comando nel suo log, raggruppato", sh:find('{ cmd1 ; } > "$D/log_1" 2>&1', 1, true) and sh:find('"$D/log_2"', 1, true))
check("coda: fine e notifica", sh:find('"$D/end"', 1, true) and sh:find("display notification", 1, true) and sh:find("di 2 file", 1, true))
local dn = M.parse_done("1\t0\t12\t/a/x.wav\n2\t1\t0\t/b c.wav\nrotta\n")
check("coda: righe dei lavori finiti", #dn == 2 and dn[1].secs == 12 and dn[2].code == 1 and dn[2].path == "/b c.wav")
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
