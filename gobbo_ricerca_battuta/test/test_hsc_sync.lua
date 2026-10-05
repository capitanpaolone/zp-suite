-- Test della sincronizzazione cue <-> marker #HSC (helper Cue Navigator 1.4). Lancio dalla radice del repo.
HSC_SYNC_TEST = true
local HSC = dofile("ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
local fails = 0
local function eq(a, b) return HSC.same(HSC.sorted(a or {}), HSC.sorted(b or {})) end
local function check(name, cond) if not cond then fails = fails + 1; print("FAIL " .. name) end end

-- nomi dei marker
check("nome esatto", HSC.is_cue_marker("#HSC", false))
check("nome con spazi", HSC.is_cue_marker("  #HSC ", false))
check("nome con suffisso", HSC.is_cue_marker("#HSC voce", false))
check("regione esclusa", not HSC.is_cue_marker("#HSC", true))
check("altro segnaposto", not HSC.is_cue_marker("#HSCX", false))
check("testo", not HSC.is_cue_marker("HSC", false))

-- prima volta: migrazione dei cue in marker
local p = HSC.plan(nil, {}, {12.0, 3.5})
check("migrazione: aggiunge", eq(p.add, {3.5, 12.0}) and #p.remove == 0 and p.to_carver == nil)
check("migrazione: istantanea", eq(p.snapshot, {3.5, 12.0}))

-- prima volta con marker gia' presenti: comandano i marker
p = HSC.plan(nil, {5.0, 9.0}, {1.0})
check("primo avvio: marker al Carver", eq(p.to_carver, {5.0, 9.0}) and #p.add == 0)
p = HSC.plan(nil, {5.0, 9.0}, {9.002, 5.0})
check("primo avvio gia' allineato: niente", p.to_carver == nil and #p.add == 0 and #p.remove == 0)

-- tutto vuoto
p = HSC.plan(nil, {}, {})
check("vuoto", p.to_carver == nil and #p.add == 0 and eq(p.snapshot, {}))

local snap = {10.0, 20.0, 30.0}
-- marker spostato (ripple o mouse)
p = HSC.plan(snap, {10.0, 17.0, 27.0}, snap)
check("marker spostati -> Carver", eq(p.to_carver, {10.0, 17.0, 27.0}) and #p.add == 0 and #p.remove == 0)
-- marker cancellato
p = HSC.plan(snap, {10.0, 30.0}, snap)
check("marker cancellato -> Carver", eq(p.to_carver, {10.0, 30.0}))
-- tutti i marker cancellati
p = HSC.plan(snap, {}, snap)
check("tutti i marker cancellati -> Carver vuoto", p.to_carver ~= nil and #p.to_carver == 0)
-- cue aggiunto dal Carver
p = HSC.plan(snap, snap, {10.0, 15.0, 20.0, 30.0})
check("cue aggiunto -> marker", eq(p.add, {15.0}) and #p.remove == 0 and p.to_carver == nil)
-- cue tolto dal Carver
p = HSC.plan(snap, snap, {10.0, 30.0})
check("cue tolto -> marker tolto", eq(p.remove, {20.0}) and #p.add == 0)
-- CLEAR ALL nel Carver
p = HSC.plan(snap, snap, {})
check("clear all -> marker tolti", eq(p.remove, snap))
-- conflitto: cambiano entrambi, vincono i marker
p = HSC.plan(snap, {11.0, 21.0, 31.0}, {10.0, 20.0, 30.0, 40.0})
check("conflitto: vincono i marker", eq(p.to_carver, {11.0, 21.0, 31.0}) and #p.add == 0 and #p.remove == 0)
-- niente di cambiato (differenze sotto la tolleranza)
p = HSC.plan(snap, {10.001, 20.0, 30.004}, {10.0, 19.997, 30.0})
check("sotto tolleranza: niente", p.to_carver == nil and #p.add == 0 and #p.remove == 0)
-- cue a 4 ms l'uno dall'altro: restano distinti nel conteggio
p = HSC.plan({}, {}, {1.000, 1.004})
check("cue vicini: due marker", #p.add == 2)
-- oltre 64 marker: il Carver riceve i primi 64 e c'e' un avviso
local many = {}
for i = 1, 70 do many[i] = i * 1.0 end
p = HSC.plan({}, many, {})
check("64 al Carver", p.to_carver and #p.to_carver == 64 and p.to_carver[64] == 64.0 and p.warn ~= nil)
-- ordine indifferente
p = HSC.plan({30.0, 10.0, 20.0}, {20.0, 30.0, 10.0}, {30.0, 20.0, 10.0})
check("ordine indifferente", p.to_carver == nil and #p.add == 0 and #p.remove == 0)

print(fails == 0 and "TUTTI OK" or (fails .. " FALLITI"))
