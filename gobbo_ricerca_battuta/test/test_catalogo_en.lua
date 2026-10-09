-- Test per validita del catalogo lang/en.txt:
-- 1. Segnaposto %s, %d, etc. coerenti tra originale e traduzione
-- 2. Copertura completa di tutte le chiamate T("...") letterali nei file .lua della Suite
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_catalogo_en.lua

local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local suite_dir = (info or "./") .. "../../ZP Studio Suite/"

local Lingua = dofile(suite_dir .. "ZP_Lingua.lua")

local en_file = suite_dir .. "lang/en.txt"
local f = io.open(en_file, "r")
if not f then
  error("File lang/en.txt non trovato!")
end

local n_totali = 0
local n_tradotte = 0
local errori_segnaposto = 0

for line in f:lines() do
  if line ~= "" and not line:match("^%s*#") then
    local k_raw, v_raw = line:match("^(.-)\t(.*)$")
    if k_raw then
      n_totali = n_totali + 1
      local orig = Lingua.unescape_text(k_raw)
      local trad = v_raw and Lingua.unescape_text(v_raw) or ""
      if trad ~= "" then
        n_tradotte = n_tradotte + 1
        local ok, err = Lingua.check_placeholders(orig, trad)
        if not ok then
          print(string.format("ERRORE SEGNAPOSTO in '%s' -> '%s': %s", orig, trad, err))
          errori_segnaposto = errori_segnaposto + 1
        end
      end
    end
  end
end
f:close()

if errori_segnaposto > 0 then
  error(string.format("Trovati %d errori nei segnaposto del catalogo!", errori_segnaposto))
end

-- 2. Controllo copertura: tutti i T(...) letterali nei file .lua devono esistere nel catalogo
local cat = Lingua.carica_catalogo("en")

local function extract_t_literals(content)
  local list = {}
  local pos = 1
  local len = #content
  while pos <= len do
    local s, e = content:find("T%s*%(", pos)
    if not s then break end
    local depth = 1
    local p = e + 1
    local in_str = nil
    local in_comment = false
    local escaped = false
    while p <= len and depth > 0 do
      local c = content:sub(p, p)
      if in_comment then
        if c == "\n" then in_comment = false end
      elseif in_str then
        if in_str == "[[" then
          if content:sub(p, p + 1) == "]]" then
            in_str = nil
            p = p + 1
          end
        else
          if escaped then
            escaped = false
          elseif c == "\\" then
            escaped = true
          elseif c == in_str then
            in_str = nil
          end
        end
      else
        if content:sub(p, p + 1) == "--" then
          if content:sub(p + 2, p + 3) == "[[" then
            local c_end = content:find("%]%]", p + 4)
            p = c_end and (c_end + 1) or len
          else
            in_comment = true
          end
        elseif c == "\"" or c == "\x27" then
          in_str = c
        elseif content:sub(p, p + 1) == "[[" then
          in_str = "[["
          p = p + 1
        elseif c == "(" then
          depth = depth + 1
        elseif c == ")" then
          depth = depth - 1
        end
      end
      if depth == 0 then break end
      p = p + 1
    end

    local arg = content:sub(e + 1, p - 1)
    local ok, res = pcall(function()
      local fn = load("return " .. arg, "t_arg", "t", {})
      if fn then return fn() end
    end)
    if ok and type(res) == "string" then
      -- calcola numero di riga
      local _, nl_count = content:sub(1, s):gsub("\n", "\n")
      table.insert(list, { text = res, line = nl_count + 1 })
    end
    pos = p + 1
  end
  return list
end

local p_cmd = io.popen("ls \"" .. suite_dir .. "\"*.lua")
local lua_files = {}
if p_cmd then
  for line in p_cmd:lines() do
    table.insert(lua_files, line)
  end
  p_cmd:close()
end

local t_totali = 0
local t_mancanti = 0

for _, filepath in ipairs(lua_files) do
  local fh = io.open(filepath, "r")
  if fh then
    local content = fh:read("*a")
    fh:close()
    local calls = extract_t_literals(content)
    local filename = filepath:match("([^/]+)$")
    for _, call in ipairs(calls) do
      t_totali = t_totali + 1
      if not cat[call.text] then
        t_mancanti = t_mancanti + 1
        print(string.format("VOCE MANCANTE in %s:%d: %q", filename, call.line, call.text))
      end
    end
  end
end

if t_mancanti > 0 then
  error(string.format("Trovate %d chiamate T() senza traduzione nel catalogo en.txt!", t_mancanti))
end

print("TUTTI OK")
