-- Test unitario per il ponte help/lingua JSFX (Cue Navigator)
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_ponte_help.lua

local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local root_dir = (info or "./") .. "../../"

-- Carica la logica con HSC_SYNC_TEST = true
_G.HSC_SYNC_TEST = true
local HSC = dofile(root_dir .. "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
local Bridge = HSC.Bridge

assert(Bridge, "Bridge non trovato in HSC")
assert(Bridge.GMEM_ALIVE == 3900, "GMEM_ALIVE non e' 3900")
assert(Bridge.GMEM_LANG == 3901, "GMEM_LANG non e' 3901")
assert(Bridge.GMEM_REQ_PLUGIN == 3902, "GMEM_REQ_PLUGIN non e' 3902")
assert(Bridge.GMEM_REQ_SEQ == 3903, "GMEM_REQ_SEQ non e' 3903")
assert(Bridge.GMEM_ACK_SEQ == 3904, "GMEM_ACK_SEQ non e' 3904")
assert(Bridge.GMEM_ACK_STATUS == 3905, "GMEM_ACK_STATUS non e' 3905")

-- 1. Verifica mapping degli 11 plugin
local expected_ids = {
  [1] = "plugin-bus-chain",
  [2] = "plugin-carver",
  [3] = "plugin-spoken-finish",
  [4] = "plugin-stagekeeper",
  [5] = "plugin-subliminal",
  [6] = "plugin-unified-chain",
  [7] = "plugin-master-pro",
  [8] = "plugin-mirror-eq",
  [9] = "plugin-loudness-meter",
  [10] = "plugin-oscilloscope",
  [11] = "plugin-probe",
}

for i = 1, 11 do
  assert(Bridge.PLUGIN_IDS[i] == expected_ids[i], string.format("Plugin %d ID errato: %s vs %s", i, tostring(Bridge.PLUGIN_IDS[i]), tostring(expected_ids[i])))
end

-- 2. Verifica help_url (codifica e ancore)
local u1 = Bridge.help_url("/path/with space/index.html", "plugin-carver")
assert(u1:match("^file:///path/with%%20space/index%.html#plugin%-carver$"), "help_url errato: " .. u1)

-- 3. Verifica risoluzione help percorsi reali
local script_source = root_dir .. "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua"
local it_url = Bridge.resolve_url(2, "it", nil, script_source)
assert(it_url:find("#plugin%-carver"), "it_url deve contenere #plugin-carver: " .. tostring(it_url))
assert(it_url:find("index%.html"), "it_url deve puntare a index.html")
assert(not it_url:find("/en/"), "it_url non deve contenere /en/")

local en_url = Bridge.resolve_url(4, "en", nil, script_source)
assert(en_url:find("#plugin%-stagekeeper"), "en_url deve contenere #plugin-stagekeeper: " .. tostring(en_url))
assert(en_url:find("/en/index%.html"), "en_url deve puntare a en/index.html")

-- 4. Fallback per plugin inesistente o percorso non trovato
-- ZP Lab: 12 e 13 vanno alla pagina a parte lab.html
assert(Bridge.PLUGIN_IDS[12] == "plugin-brownslope-prism" and Bridge.PLUGIN_IDS[13] == "plugin-brownslope-guard", "id ZP Lab")
assert(Bridge.PLUGIN_PAGES[12] == "lab.html" and Bridge.PLUGIN_PAGES[2] == nil, "pagina ZP Lab")
local fallback_url = Bridge.resolve_url(99, "it", nil, script_source)
assert(fallback_url == Bridge.FALLBACK_URL, "Fallback per plugin 99 fallito")

local fallback_no_file = Bridge.resolve_url(1, "it", "/non/existent/path", "/another/fake/path.lua")
assert(fallback_no_file == Bridge.FALLBACK_URL, "Fallback per percorsi inesistenti fallito")

-- 5. Simulazione gmem / serve_bridge
_G.HSC_SYNC_TEST = nil
_G.HSC_SYNC_SIM = true

-- Creiamo un ambiente REAPER simulato per gmem e ExtState
local gmem = {}
local ext_state = { ["ZP_STUDIO_SUITE:lingua"] = "en" }
local opened_urls = {}

_G.reaper = {
  gmem_attach = function() end,
  gmem_read = function(idx) return gmem[idx] or 0 end,
  gmem_write = function(idx, val) gmem[idx] = val end,
  GetExtState = function(sec, key) return ext_state[sec .. ":" .. key] or "" end,
  SetExtState = function(sec, key, val) ext_state[sec .. ":" .. key] = val end,
  DeleteExtState = function(sec, key) ext_state[sec .. ":" .. key] = nil end,
  GetResourcePath = function() return root_dir end,
  GetOS = function() return "OSX64" end,
  defer = function() end,
  time_precise = function() return 100.0 end,
  TrackCtl_SetToolTip = function() end,
  EnumProjects = function() return nil end,
  ColorToNative = function(r, g, b) return 0 end,
}

local sim = dofile(root_dir .. "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
assert(sim and sim.serve_bridge, "serve_bridge non esposto in HSC_SYNC_SIM")
sim.bridge.open_url = function(url)
  table.insert(opened_urls, url)
  return true
end

-- Giro 1: lingua "en", nessun request
sim.serve_bridge()
assert(gmem[3900] == 1, "Ponte vivo tick deve essere 1")
assert(gmem[3901] == 1, "Lingua gmem deve essere 1 per en")

-- Giro 2: lingua "it", richiesta plugin 4 (Stagekeeper) con seq 1
ext_state["ZP_STUDIO_SUITE:lingua"] = "it"
gmem[3902] = 4 -- plugin 4
gmem[3903] = 1 -- req_seq 1
gmem[3904] = 0 -- ack_seq 0

sim.serve_bridge()
assert(gmem[3900] == 2, "Ponte vivo tick deve essere 2")
assert(gmem[3901] == 0, "Lingua gmem deve essere 0 per it")
assert(gmem[3904] == 1, "Ack seq deve essere 1")
assert(gmem[3905] == 1, "Ack status deve essere 1")
assert(#opened_urls == 1, "Deve aver aperto 1 URL")
assert(opened_urls[1]:find("#plugin%-stagekeeper"), "URL deve contenere #plugin-stagekeeper")

-- Giro 3: stessa seq (nessuna nuova richiesta)
sim.serve_bridge()
assert(gmem[3900] == 3, "Ponte vivo tick deve essere 3")
assert(#opened_urls == 1, "Non deve riaprire lo stesso URL con lo stesso seq")

print("TUTTI OK")
