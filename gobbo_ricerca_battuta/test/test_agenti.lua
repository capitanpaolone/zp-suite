-- Test della logica pura di ZP_Agenti.lua. Lancio dalla radice del repo.
local A = dofile("ZP Studio Suite/ZP_Agenti.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
local json = '{"engines": [{"engine": "codex", "available": false, "path": null, "cloud": true, "login": true, "where": "OpenAI", "models": []}, ' ..
  '{"engine": "claude", "available": true, "path": "/x", "cloud": true, "login": true, "where": "Anthropic", "models": []}, ' ..
  '{"engine": "ollama", "available": true, "path": "/y", "cloud": false, "login": false, "where": "nowhere: a local model", "models": ["qwen3.6:latest", "gemma4:latest"]}]}'
local list = A.parse(json)
check("parse: tre agenti, disponibilita' e modelli", #list == 3 and not list[1].available and list[2].available
  and list[3].models[2] == "gemma4:latest")
check("auto -> il primo disponibile (Claude, perche' Codex manca)", A.resolve(list, "auto") == "claude" and A.resolve(list, "") == "claude")
check("scelta precisa resta quella", A.resolve(list, "ollama") == "ollama")
check("nessun agente", A.resolve({}, "auto") == nil and A.label({}, "auto") == "Auto (nessuno)")
check("etichette", A.label(list, "auto") == "Auto (Claude)" and A.label(list, "ollama") == "Ollama (locale)")
check("dove va il testo: Ollama resta sul Mac, Claude ad Anthropic", A.where("ollama"):find("resta su questo Mac", 1, true)
  and A.where("claude"):find("Anthropic", 1, true) and A.where("boh"):find("boh", 1, true))
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
