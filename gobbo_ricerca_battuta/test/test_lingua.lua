-- Test autonomo per ZP_Lingua.lua
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_lingua.lua

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("ASSERT FALLITA: %s (ottenuto: %s, atteso: %s)", msg or "", tostring(a), tostring(b)), 2)
  end
end

local function assert_true(cond, msg)
  if not cond then
    error("ASSERT FALLITA: " .. (msg or "condizione non vera"), 2)
  end
end

-- Determina percorso script
local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local suite_dir = (info or "./") .. "../../ZP Studio Suite/"

local Lingua = dofile(suite_dir .. "ZP_Lingua.lua")

print("--- Test ZP_Lingua.lua ---")

-- 1. Default lingua "it"
Lingua.set_lingua("it")
assert_eq(Lingua.get_lingua(), "it", "default lingua deve essere it")
assert_eq(Lingua.T("Salva"), "Salva", "in italiano T() ritorna originale")

-- 2. Escape / Unescape
local s_raw = "Riga 1\nRiga 2\tColonna\nRitorno\\Speciale"
local s_esc = Lingua.escape_text(s_raw)
assert_true(not s_esc:find("\n"), "escape non deve contenere newline reali")
assert_true(not s_esc:find("\t"), "escape non deve contenere tab reali")
local s_unesc = Lingua.unescape_text(s_esc)
assert_eq(s_unesc, s_raw, "unescape deve ripristinare il testo originale esatto")

-- 3. Check segnaposto
local ok, err = Lingua.check_placeholders("Trovati %d elementi su %s", "Found %d items in %s")
assert_true(ok, "stessi segnaposto in stesso ordine devono essere validi")

local ok2, _ = Lingua.check_placeholders("Item %d di %d", "Item %d")
assert_true(not ok2, "conteggio segnaposto diverso deve fallire")

local ok3, _ = Lingua.check_placeholders("File: %s, Livello: %d", "File: %d, Livello: %s")
assert_true(not ok3, "ordine o tipo segnaposto diverso deve fallire")

-- 4. Test catalogo sintetico
local tmp_dir = "/tmp/zp_test_lang/"
os.execute("mkdir -p " .. tmp_dir)
local f = io.open(tmp_dir .. "en.txt", "w")
f:write("# Commento\n")
f:write(Lingua.escape_text("Salva") .. "\t" .. Lingua.escape_text("Save") .. "\n")
f:write(Lingua.escape_text("Annulla") .. "\t" .. Lingua.escape_text("Cancel") .. "\n")
f:write(Lingua.escape_text("Riga1\nRiga2") .. "\t" .. Lingua.escape_text("Line1\nLine2") .. "\n")
f:close()

Lingua.set_lang_dir_override(tmp_dir)
Lingua.set_lingua("en")
assert_eq(Lingua.get_lingua(), "en", "lingua impostata su en")

assert_eq(Lingua.T("Salva"), "Save", "traduzione di Salva")
assert_eq(Lingua.T("Annulla"), "Cancel", "traduzione di Annulla")
assert_eq(Lingua.T("Riga1\nRiga2"), "Line1\nLine2", "traduzione con multiriga escapata")
assert_eq(Lingua.T("TestoNonPresente"), "TestoNonPresente", "fallback su originale se assente")

-- Ripristino lingua it
Lingua.set_lingua("it")
assert_eq(Lingua.T("Salva"), "Salva", "ritorno a it restituisce originale")

-- Pulizia tmp
os.execute("rm -rf " .. tmp_dir)

print("TUTTI OK")
