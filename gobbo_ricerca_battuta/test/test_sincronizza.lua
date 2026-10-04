-- Test della logica pura di ZP_sincronizza_aggancio.lua (fuori da REAPER).
-- Lancio: lua gobbo_ricerca_battuta/test/test_sincronizza.lua  (dalla radice del repo)
local M = dofile("ZP Studio Suite/ZP_sincronizza_aggancio.lua")
local fails = 0
local function check(name, cond)
  print((cond and "ok   " or "FAIL ") .. name)
  if not cond then fails = fails + 1 end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
local P = M.CARRY_PREFIX

local mk = { { src = 2, text = "A" }, { src = 6, text = "B" }, { src = 12, text = "C" } }

-- item_lines ----------------------------------------------------------------
local l = M.item_lines({ pos = 100, len = 20, startoffs = 0, rate = 1 }, mk)
check("item intero: tre battute, nessuna in corso", #l == 3 and not l[1].carry)
check("posizione = pos + (src - offset)", near(l[2].pos, 106) and near(l[2].len, 6))
check("ultima battuta fino alla fine dell'item", near(l[3].len, 8))

l = M.item_lines({ pos = 50, len = 4, startoffs = 7, rate = 1 }, mk)
check("pezzo senza marker (7..11): una battuta in corso", #l == 1 and l[1].carry)
check("battuta in corso = B con '… ' all'inizio del pezzo", l[1].text == P .. "B" and near(l[1].pos, 50) and near(l[1].len, 4))

l = M.item_lines({ pos = 0, len = 10, startoffs = 4, rate = 1 }, mk)
check("pezzo 4..14: A in corso, poi B e C", #l == 3 and l[1].carry and l[1].text == P .. "A" and l[2].text == "B")
check("in corso dura fino al primo marker del pezzo", near(l[1].len, 2) and near(l[2].pos, 2))

l = M.item_lines({ pos = 0, len = 10, startoffs = 6, rate = 1 }, mk)
check("pezzo che comincia esattamente su un marker: niente in corso", #l == 2 and not l[1].carry)

l = M.item_lines({ pos = 0, len = 1, startoffs = 0, rate = 1 }, mk)
check("pezzo prima del primo marker: niente", #l == 0)

l = M.item_lines({ pos = 10, len = 2, startoffs = 8, rate = 2 }, mk)
check("playrate 2: pezzo 8..12 con B in corso, durata in timeline 2", #l == 1 and l[1].carry and near(l[1].len, 2))

l = M.item_lines({ pos = 0, len = 10, startoffs = 7, rate = 1 }, { { src = 6, text = "" }, { src = 2, text = "A" } })
check("marker senza testo ignorato anche come battuta in corso", #l == 1 and l[1].text == P .. "A")

-- plan (aggancio) -------------------------------------------------------------
local function w(key, text) return { key = key, srckey = "f|" .. key, track = "T", pos = 1, len = 1, text = text } end
local function e(key, notes, orig, extra)
  local x = { id = key, key = key, srckey = "f|" .. key, track = "T", notes = notes, orig = orig }
  for k, v in pairs(extra or {}) do x[k] = v end
  return x
end
local plan = M.plan({ w("k1", "uno") }, { e("k1", "uno", "uno") })
check("stesso marker: aggiornato, testo non riscritto", #plan.update == 1 and not plan.update[1].set_text and #plan.create == 0)
plan = M.plan({ w("k1", "uno nuovo") }, { e("k1", "corretto a mano", "uno") })
check("testo corretto a mano: non viene sovrascritto", #plan.update == 1 and not plan.update[1].set_text)
plan = M.plan({ w("k1", "uno nuovo") }, { e("k1", "uno", "uno") })
check("testo mai toccato e marker cambiato: segue il marker", plan.update[1].set_text == true)
plan = M.plan({}, { e("k1", "uno", "uno") })
check("marker sparito, testo mai toccato: cancellato", #plan.delete == 1)
plan = M.plan({}, { e("k1", "mio", "uno") })
check("marker sparito, testo modificato: in mute", #plan.mute == 1 and #plan.delete == 0)
plan = M.plan({ w("k1", "uno") }, { e("k1", "mio", "uno", { orphan = true }) })
check("marker tornato: tolto il mute", plan.update[1].unmute == true)
plan = M.plan({ { key = "nuovo", srckey = "f|k1", track = "T", pos = 1, len = 1, text = "uno" } }, { e("k1", "mio", "uno") })
check("GUID cambiato (split): ripiego su file+tempo, testo salvo", #plan.update == 1 and plan.update[1].rebind and #plan.create == 0)
plan = M.plan({ w("k1", "uno"), w("k2", "uno") }, { e("k1", "uno", "uno") })
check("item duplicato: nasce un item testo nuovo", #plan.create == 1)
plan = M.plan({ { key = "k1", srckey = "f|k1", track = "T2", pos = 1, len = 1, text = "uno" } }, { e("k1", "uno", "uno") })
check("item spostato su un'altra voce: cambia traccia testo", plan.update[1].move == true)

print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails))
os.exit(fails == 0 and 0 or 1)
