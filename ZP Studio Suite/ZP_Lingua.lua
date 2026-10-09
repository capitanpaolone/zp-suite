-- @noindex

-- ZP Studio Suite — modulo multilingua (ZP_Lingua.lua)
-- Gestisce traduzioni, cataloghi e lingua attiva (default "it").
-- Compatibile sia dentro REAPER che in ambienti Lua 5.4 autonomi.

local M = {}

M.EXT_SECTION = "ZP_STUDIO_SUITE"
M.EXT_KEY = "lingua"
M.DEFAULT_LANG = "it"

local _lingua_corrente = nil
local _cataloghi = {} -- [lang] = { [orig] = trad }
local _lang_dir_override = nil

local function get_script_dir()
  if _lang_dir_override then return _lang_dir_override end
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  local dir = src:match("^@?(.*[/\\])")
  if dir and dir ~= "" then
    return dir .. "lang/"
  end
  return "lang/"
end

function M.set_lang_dir_override(dir)
  _lang_dir_override = dir
  _cataloghi = {}
end

function M.escape_text(s)
  if type(s) ~= "string" then return "" end
  return s:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n")
end

function M.unescape_text(s)
  if type(s) ~= "string" then return "" end
  -- Sostituzione delle sequenze di escape
  local res = s:gsub("\\([\\trn])", function(esc)
    if esc == "n" then return "\n"
    elseif esc == "t" then return "\t"
    elseif esc == "r" then return "\r"
    elseif esc == "\\" then return "\\"
    end
    return esc
  end)
  return res
end

-- Estrae i segnaposto printf-style (%s, %d, %.1f, etc.)
function M.extract_placeholders(s)
  local list = {}
  if type(s) ~= "string" then return list end
  for ph in s:gmatch("%%[-+0-9#%. ]*[cdieEfgGousxXq%%]") do
    if ph ~= "%%" then -- ignora % letterale raddoppiato
      list[#list + 1] = ph
    end
  end
  return list
end

-- Verifica conformita segnaposto tra originale e traduzione
function M.check_placeholders(orig, trad)
  local ph_orig = M.extract_placeholders(orig)
  local ph_trad = M.extract_placeholders(trad)
  if #ph_orig ~= #ph_trad then
    return false, string.format("Numero segnaposto diverso: %d in orig, %d in trad", #ph_orig, #ph_trad)
  end
  for i = 1, #ph_orig do
    if ph_orig[i] ~= ph_trad[i] then
      return false, string.format("Segnaposto diverso alla pos %d: '%s' vs '%s'", i, ph_orig[i], ph_trad[i])
    end
  end
  return true
end

function M.get_lingua()
  if reaper and reaper.GetExtState then
    local v = reaper.GetExtState(M.EXT_SECTION, M.EXT_KEY)
    if v and v ~= "" then
      _lingua_corrente = v
      return v
    end
  end
  return _lingua_corrente or M.DEFAULT_LANG
end

function M.set_lingua(lang)
  lang = (lang or M.DEFAULT_LANG):lower():gsub("%s+", "")
  if lang == "" then lang = M.DEFAULT_LANG end
  _lingua_corrente = lang
  if reaper and reaper.SetExtState then
    reaper.SetExtState(M.EXT_SECTION, M.EXT_KEY, lang, true)
  end
  return lang
end

function M.carica_catalogo(lang)
  lang = (lang or M.get_lingua()):lower():gsub("%s+", "")
  if _cataloghi[lang] then
    return _cataloghi[lang]
  end

  local cat = {}
  if lang == "it" then
    _cataloghi[lang] = cat
    return cat
  end

  local dir = get_script_dir()
  local file_path = dir .. lang .. ".txt"
  local f = io.open(file_path, "r")
  if f then
    for line in f:lines() do
      -- ignora righe vuote o commenti che iniziano con #
      if line ~= "" and not line:match("^%s*#") then
        local k_raw, v_raw = line:match("^(.-)\t(.*)$")
        if k_raw and v_raw then
          local k = M.unescape_text(k_raw)
          local v = M.unescape_text(v_raw)
          if k ~= "" and v ~= "" then
            cat[k] = v
          end
        end
      end
    end
    f:close()
  end

  _cataloghi[lang] = cat
  return cat
end

function M.svuota_cache()
  _cataloghi = {}
end

function M.T(testo)
  if type(testo) ~= "string" or testo == "" then
    return testo
  end
  local lang = M.get_lingua()
  if lang == "it" then
    return testo
  end
  local cat = _cataloghi[lang] or M.carica_catalogo(lang)
  local tr = cat[testo]
  if tr and tr ~= "" then
    return tr
  end
  return testo
end

-- Esposizione globale per comodita negli script
if not _G.T then
  _G.T = M.T
end

return M
