-- Test della logica pura di 14_Marker_da_Timeline_a_Item.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/14_Marker_da_Timeline_a_Item.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
check("segnaposto #", M.service_reason("#scena 2") == "segnaposto")
check("azione !", M.service_reason("!1016") == "azione")
check("marker SOLO", M.service_reason("BAD_003") == "SOLO" and M.service_reason("SOLO_MARK_012") == "SOLO" and M.service_reason("INSERT_001") == "SOLO")
check("senza nome", M.service_reason("  ") == "senza nome")
check("testo vero", M.service_reason("Ciao, come stai?") == nil and M.service_reason("OK, andiamo") == nil and M.service_reason("BAD") == nil)
-- la registrazione parte prima del segnaposto e se lo porta dentro
local items = { { pos = 10, len = 20, startoffs = 0, rate = 1, existing = {} } }
local markers = {
  { pos = 12, name = "Prima battuta", id = 1 },
  { pos = 15, name = "#riprendere da qui", id = 2 },
  { pos = 18, name = "OK_004", id = 3 },
  { pos = 22, name = "Seconda battuta", id = 4 },
  { pos = 40, name = "fuori", id = 5 },
}
local plan, fixed, skipped = M.plan(items, markers)
check("copiati solo i due testi", #plan[1].add == 2 and plan[1].add[1].name == "Prima battuta" and plan[1].add[2].name == "Seconda battuta")
check("da cancellare solo i testi (mai i segnaposto)", #fixed == 2 and fixed[1] == 1 and fixed[2] == 4)
check("segnaposto e OK_004 riportati come lasciati", #skipped == 2 and skipped[1].reason == "segnaposto" and skipped[2].reason == "SOLO")
check("tempo sorgente giusto", math.abs(plan[1].add[2].src - 12) < 1e-9)
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
