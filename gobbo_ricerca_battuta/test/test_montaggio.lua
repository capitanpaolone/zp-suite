-- Test della logica pura di ZP Montaggio Parlato (ZP_Montaggio.lua). Dalla radice del repo:
--   lua gobbo_ricerca_battuta/test/test_montaggio.lua
local M = dofile("ZP Studio Suite/ZP_Montaggio.lua")
local failures = 0
local function eq(label, a, b)
  if a ~= b then failures = failures + 1; io.stderr:write("FAIL ", label, ": ", tostring(a), " ~= ", tostring(b), "\n") end
end
local function near(label, a, b, tol)
  if not a or math.abs(a - b) > (tol or 0.02) then failures = failures + 1; io.stderr:write("FAIL ", label, ": ", tostring(a), " ~= ", tostring(b), "\n") end
end

-- testo
eq("accenti e maiuscole", table.concat(M.tokens("Sarà PERCHÉ d’Autunno"), " "), "sara perche d autunno")
eq("numeri detti = scritti", table.concat(M.tokens("il Primo novembre, trentuno"), " "), "il 1 novembre 31")
eq("simili: una lettera", M.simili("prepara", "prepare"), true)
eq("simili: lettera in piu'", M.simili("palato", "parlato"), true)
eq("simili: parole corte no", M.simili("del", "nel"), false)
local fr = M.parse_copione("Prepara il palato… ritorna la Sagra! Gusterai i cappellacci.\nSabato 31 ci sarà la strega")
eq("frasi del copione", #fr, 4)
eq("prima frase", fr[1].text, "Prepara il palato")

-- json di ZP Speech
local doc = M.json_decode('{"segments":[{"words":[{"start_ms":1000,"end_ms":1500,"text":"Ciao"},{"start_ms":1500,"end_ms":2000,"text":"\\u00e8 l\\"uno"}]}],"x":[true,false,null,-1.5e2]}')
local w = M.words_from_transcript(doc, 10)
eq("parole lette", #w, 2); near("offset", w[1].s, 11); eq("escape", w[2].text, 'è l"uno')

-- parole finte: una lettura con rifacimento a voce
local function words_of(list)
  local out, t = {}, 0
  for _, x in ipairs(list) do
    if type(x) == "number" then t = t + x else out[#out + 1] = { s = t, e = t + 0.3, text = x }; t = t + 0.35 end
  end
  return out
end
local words = words_of({ "Allora", 1, "il", "30", "e", "31", "ottobre", 0.5, "Rifaccio", 1, "Il", "30", "e", "31", "ottobre", "e", "il", "primo", "novembre", 2,
                         "alternativa", 1, "il", "30", "e", "31", "ottobre", "e", "il", "1", "novembre" })
local frasi = M.parse_copione("Il 30 e 31 ottobre e il Primo novembre")
local p = M.plan({ words = words, frasi = frasi, len = 20 })
local tipi = {}
for _, iv in ipairs(p.interventi) do tipi[#tipi + 1] = iv.tipo end
eq("interventi", table.concat(tipi, ","), "fuori,rifacimento,comando,comando,alternativa")
local rif
for _, iv in ipairs(p.interventi) do if iv.tipo == "rifacimento" then rif = iv end end
near("rifacimento: inizio = prima versione", rif.s, words[2].s)
near("rifacimento: fine = attacco seconda", rif.e, words[8].s)
eq("un solo tratto tenuto", #p.keep, 1)
near("tenuto parte esattamente dalla seconda versione", p.keep[1].s, words[8].s)
eq("alternativa in corsia", #p.alt, 1)
-- cambiare idea: tengo il rifacimento
M.set_tieni(p, rif, true)
eq("tenendo il rifacimento, il comando resta fuori", p.stato[7], "comando")
M.set_tieni(p, rif, false)
eq("di nuovo tolto", p.stato[2], "rifatto")

-- senza copione: il rifacimento si trova lo stesso (stesse parole dopo il segnale)
local p2 = M.plan({ words = words, frasi = {}, len = 20 })
local found
for _, iv in ipairs(p2.interventi) do if iv.tipo == "rifacimento" then found = iv end end
near("senza copione: inizio", found and found.s, words[2].s)

-- comandi: dizionario e numeri
local dz = M.dizionario_da_testo("rifaccio = rifai\n# commento\nsilenzio di N secondi = silenzio\n")
eq("dizionario da testo", #dz, 2); eq("numero", dz[2][3], "#")
local tk = M.token_list(words_of({ "silenzio", "di", "quindici", "secondi" }))
local c = M.find_commands(tk, nil, {})
eq("silenzio di N", c[1] and c[1].azione, "silenzio"); eq("N", c[1] and c[1].n, 15)

-- click forti a gruppo, energia finta
local env = { hop = 0.005, pk = {}, rms = {} }
for k = 1, 2000 do env.pk[k] = -60; env.rms[k] = -62 end
for _, k in ipairs({ 1000, 1030, 1080 }) do env.pk[k] = -4 end
env.pk[1500] = -25 -- troppo debole: non e' un click
local g = M.find_clicks(env)
eq("un gruppo", #g, 1); eq("tre click", g[1] and g[1].n, 3); near("inizio gruppo", g[1] and g[1].s, 999 * 0.005)
-- attacco: salto di energia dopo il tempo di Whisper
for k = 1, 2000 do env.pk[k] = -60 end
for k = 415, 500 do env.pk[k] = -10 end
near("attacco vero", M.attack(env, 2.0), 414 * 0.005 - 0.004, 0.006)

-- frammenti: le parole affidabili restano, la parola stirata se ne va
local base = { { s = 1, e = 1.5, text = "ottobre" }, { s = 1.6, e = 5.8, text = "e" }, { s = 6, e = 6.3, text = "il" } }
local merged = M.merge_fragment(base, { { s = 1.1, e = 1.4, text = "x" }, { s = 3, e = 3.3, text = "Il" } }, { s = 1, e = 5.9 })
local t = {}; for _, x in ipairs(merged) do t[#t + 1] = x.text end
eq("frammento riempie solo i buchi", table.concat(t, " "), "ottobre Il il")

-- WAV: scrivo, leggo l'energia, taglio un frammento
local tmp = os.tmpname()
local sr, n = 8000, 8000
local body = {}
for i = 1, n do body[i] = string.pack("<i2", (i > 4000 and i < 4100) and 20000 or 0) end
local data = table.concat(body)
local fmt = string.pack("<I2I2I4I4I2I2", 1, 1, sr, sr * 2, 2, 16)
local f = io.open(tmp, "wb")
f:write("RIFF", string.pack("<I4", 4 + 8 + #fmt + 8 + #data), "WAVE", "fmt ", string.pack("<I4", #fmt), fmt, "data", string.pack("<I4", #data), data)
f:close()
local info = assert(M.wav_open(tmp))
eq("frame", info.frames, n); near("durata", info.len, 1)
local e2 = M.env_new(info.sr, 0.005)
while M.wav_read_env(info, e2, 1000) > 0 do end
M.wav_close(info)
eq("finestre", #e2.pk, 200)
near("picco nel punto giusto", e2.pk[101], M.db(20000 / 32768), 0.1)
local frag = tmp .. "_f.wav"
assert(M.wav_fragment(tmp, frag, 0.25, 0.75))
local fi = assert(M.wav_open(frag)); eq("frammento lungo mezzo secondo", fi.frames, 4000); M.wav_close(fi)
os.remove(tmp); os.remove(frag)

if failures > 0 then error(failures .. " test falliti") end
print("TUTTI OK")
