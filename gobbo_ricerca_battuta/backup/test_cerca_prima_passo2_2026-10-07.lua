local C = dofile("ZP Studio Suite/ZP_cerca.lua")
local failures = 0
local function eq(label, a, b)
  if a ~= b then failures = failures + 1; io.stderr:write("FAIL ", label, ": ", tostring(a), " ~= ", tostring(b), "\n") end
end
local function found(text, query) return C.find(text, query) end

local a,b = found("Hijacking", "hijac"); eq("prefisso case-insensitive", a, 1); eq("fine prefix", b, 5)
eq("non parte nel mezzo", found("hijacking", "ac"), nil)
eq("accento ignorato", found("Perché", "perche"), 1)
eq("maiuscola accentata", found("È", "e"), 1)
eq("minuscola vs maiuscola accentata", found("e", "È"), 1)
eq("lettera accentata nel confine", found("città", "citt"), 1)
eq("inizio interno non trovato", found("città", "itta"), nil)
eq("esatto con punteggiatura", found("hijacking,", '"hijacking"'), 1)
eq("esatto rifiuta plurale", found("hijackings", '"hijacking"'), nil)
eq("frase con ultimo prefisso", found("il hijacking", "il hijac"), 1)
for _, wrapped in ipairs({"l'hijacking", "l’hijacking", "«hijacking»", "‹hijacking›", "“hijacking”", "—hijacking", "…hijacking", "·hijacking", "•hijacking", " hijacking", "　hijacking", "、hijacking"}) do
  local expected = wrapped:find("hijacking", 1, true)
  eq("punteggiatura prima: " .. wrapped, found(wrapped, "hijac"), expected)
  eq("evidenzia parola avvolta: " .. wrapped, C.word_matches(wrapped, "hijac"), true)
end
local s,e = found("Èx Perché", "perche"); eq("offset originale con accentate prima", s, 5); eq("offset finale", e, 11)
eq("query vuota", found("abc", ""), nil)
local crs, cre = found("uno\r\ndopo hijacking", "hijac")
eq("offset CRLF originale", crs, 11); eq("fine offset CRLF", cre, 15)
local rows = {{notes="hijacking hijacked"},{notes="Hijacking"}}
local total,current = C.count(rows, "hijac", rows[1])
eq("conteggio per item, non per parola", total, 2); eq("indice del primo item", current, 1)
total,current = C.count(rows, "hijac", rows[2])
eq("indice secondo item", current, 2)
if failures > 0 then error(failures .. " test falliti") end
print("TUTTI OK")
