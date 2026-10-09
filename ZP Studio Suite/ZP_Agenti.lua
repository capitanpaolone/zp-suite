-- @noindex

-- ZP Studio Suite for REAPER
-- Agenti AI per le funzioni facoltative (Traduci nel 29, Spiega con l'AI nel 34): la Suite usa
-- l'agente che c'e' su questo Mac. ZP Speech li trova ("zp-speech translators"): Codex, Claude,
-- Qwen, OpenCode (cloud, con il tuo account) e Ollama (modelli locali: niente esce dal Mac).
-- "auto" = il primo disponibile in quest'ordine. Prima di mandare testo, chi chiama dice dove va.

local M = {}

M.ORDER = { "codex", "claude", "qwen", "opencode", "ollama" }
M.NAMES = { auto = "Auto", codex = "Codex", claude = "Claude", qwen = "Qwen", opencode = "OpenCode", ollama = "Ollama (locale)" }
M.WHERE = {
  codex = "Il testo va a OpenAI con il tuo account ChatGPT.",
  claude = "Il testo va ad Anthropic con il tuo account Claude.",
  qwen = "Il testo va al servizio che hai configurato in Qwen Code.",
  opencode = "Il testo va al servizio che hai configurato in OpenCode.",
  ollama = "Il testo resta su questo Mac: lo legge un modello locale.",
}

-- JSON di "zp-speech translators" -> { {engine, available, models = {...}}, ... }
function M.parse(json)
  local list = {}
  for obj in tostring(json or ""):gmatch('{"engine"%s*:.-%]}') do
    local e = { engine = obj:match('"engine"%s*:%s*"([^"]+)"'),
                available = obj:match('"available"%s*:%s*true') ~= nil, models = {} }
    for m in (obj:match('"models"%s*:%s*%[(.-)%]') or ""):gmatch('"([^"]+)"') do e.models[#e.models + 1] = m end
    if e.engine then list[#list + 1] = e end
  end
  return list
end

-- "auto" -> il primo disponibile (nell'ordine di ZP Speech); un nome preciso resta quello.
function M.resolve(list, engine)
  if engine and engine ~= "" and engine ~= "auto" then return engine end
  for _, e in ipairs(list or {}) do if e.available then return e.engine end end
  return nil
end

function M.label(list, engine)
  if engine == "auto" or not engine or engine == "" then
    local r = M.resolve(list, "auto")
    return "Auto" .. (r and (" (" .. (M.NAMES[r] or r) .. ")") or " (nessuno)")
  end
  return M.NAMES[engine] or engine
end

function M.where(engine) return M.WHERE[engine] or ("Il testo va all'agente " .. tostring(engine) .. ".") end

if not reaper then return M end

M.SECTION, M.KEY = "ZP_STUDIO_SUITE", "agente_ai"

function M.get()
  local v = reaper.GetExtState(M.SECTION, M.KEY)
  return v ~= "" and v or "auto"
end

function M.set(engine) reaper.SetExtState(M.SECTION, M.KEY, engine, true) end

function M.cli() return (os.getenv("HOME") or "") .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech" end

-- Elenco degli agenti (una volta per finestra: chiede a ZP Speech, qualche secondo).
function M.load()
  local p = io.popen("'" .. M.cli():gsub("'", "'\\''") .. "' translators 2>/dev/null", "r")
  local list = {}
  if p then list = M.parse(p:read("*a")); p:close() end
  return list
end

-- Menu per scegliere l'agente (gfx.showmenu alla posizione del mouse). Restituisce la scelta o nil.
function M.menu(list, current)
  local items, keys = {}, {}
  items[#items + 1] = (current == "auto" and "!" or "") .. M.label(list, "auto") .. ": il primo disponibile"
  keys[#keys + 1] = "auto"
  for _, e in ipairs(list) do
    items[#items + 1] = (e.available and "" or "#") .. (e.engine == current and "!" or "") ..
      (M.NAMES[e.engine] or e.engine) .. (e.available and "" or " (non installato)")
    keys[#keys + 1] = e.engine
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(items, "|"))
  return keys[choice]
end

return M
