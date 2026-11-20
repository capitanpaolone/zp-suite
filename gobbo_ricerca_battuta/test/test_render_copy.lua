-- Render & Copy con piu' progetti aperti in tab: a quale progetto appartiene cosa.
local path = 'ZP Studio Suite/render_copy/ZP_RenderCopy.lua'
local f = assert(io.open(path, 'rb')); local src = f:read('a'); f:close()
local fails = 0
local function check(name, cond) print((cond and 'ok   ' or 'FAIL ') .. name); if not cond then fails = fails + 1 end end

local projects, active = {}, 1
local env = setmetatable({}, {__index = _G}); env._G = env
env.ZP_RENDER_COPY_TEST = true
env.dofile = function() return {} end            -- ZP_UI non serve alla logica
env.reaper = {
  GetResourcePath = function() return '/risorse' end,
  GetOS = function() return 'macOS-arm64' end,
  get_action_context = function() return false, '', 0, 0 end,
  EnumProjects = function(i)
    local p = projects[i == -1 and active or (i + 1)]
    if p then return p.id, p.fn end
  end,
}
local M = assert(load(src, '@' .. path, 't', env))()

local A = {'A', '/lavori/Spot Falco/Spot Falco.rpp'}
local B = {'B', '/lavori/EP02/EP02 MASTER.RPP'}
local C = {'C', '/lavori/EP02/MASTER.rpp'}
check('coda: trova il progetto dal nome del file accodato',
  M.queued_owner('/r/QueuedRenders/qrender_261116_101500_Spot Falco.rpp', {A, B}) == A)
check('coda: fra due nomi che chiudono il file vince il piu\' lungo',
  M.queued_owner('/r/QueuedRenders/qrender_261116_101500_EP02 MASTER.rpp', {C, B}) == B)
check('coda: un nome che e\' solo la coda di un altro non basta',
  M.queued_owner('/r/QueuedRenders/qrender_261116_101500_GRANDMASTER.rpp', {C}) == nil)
check('coda: nessun progetto aperto corrisponde', M.queued_owner('/r/QueuedRenders/qrender_1_2_Altro.rpp', {A, B}) == nil)
check('coda: progetto non salvato ignorato', M.queued_owner('/r/QueuedRenders/qrender_1_2_X.rpp', {{'U', ''}}) == nil)

check('chiave: percorso del file', M.project_key('A', 'C:\\lavori\\x.rpp') == M.project_key('Z', 'C:/lavori/x.rpp'))
check('chiave: progetti non salvati distinti', M.project_key('P1', '') ~= M.project_key('P2', ''))
check('nome: senza estensione', M.project_label('/a/b/EP02 MASTER.RPP') == 'EP02 MASTER')
check('nome: non salvato', M.project_label('') == 'progetto non salvato')
check('dentro la consegna', M.is_inside('/consegne/EP02/a.wav', '/consegne/EP02') and not M.is_inside('/consegne/EP02 bis/a.wav', '/consegne/EP02'))

-- Progetto di lavoro: in primo piano un progetto normale = quello; in primo piano un
-- progetto accodato = il suo progetto d'origine, anche se l'ultimo usato era un altro.
projects = {{id = 'A', fn = A[2]}, {id = 'B', fn = B[2]}, {id = 'Q', fn = '/r/QueuedRenders/qrender_261116_101500_EP02 MASTER.rpp'}}
active = 1
local p, fn, q = M.work_project(); check('tab 1 in primo piano', p == 'A' and q == nil)
active = 3
p, fn, q = M.work_project(); check('coda del progetto 2 mentre l\'ultimo usato era il progetto 1', p == 'B' and q == 'Q')
active = 2
p = M.work_project(); check('passo al progetto 2', p == 'B')
projects[3].fn = '/r/QueuedRenders/qrender_261116_101500_Sconosciuto.rpp'; active = 3
p, fn, q = M.work_project(); check('coda senza corrispondenza: resta l\'ultimo progetto usato', p == 'B' and q == 'Q')

-- Versioni dei file con lo stesso nome in consegna
check('versione 1 = nome com\'e\'', M.version_path('/c/Spot.wav', 1) == '/c/Spot.wav')
check('versione 2 prima dell\'estensione', M.version_path('/c/Spot.wav', 2) == '/c/Spot (vers 2).wav')
check('nome con punti e cartella con punto', M.version_path('/c/v1.2/Spot.mix.wav', 3) == '/c/v1.2/Spot.mix (vers 3).wav')
check('senza estensione', M.version_path('/c/v1.2/Spot', 2) == '/c/v1.2/Spot (vers 2)')
do
  local present = {['/c/A.wav'] = true, ['/c/A (vers 2).wav'] = true, ['/c/A (vers 3).wav'] = true, ['/c/B (vers 2).wav'] = true}
  local function exists(path) return present[path] == true end
  local last, n = M.latest_version('/c/A.wav', exists)
  check('ultima versione presente', last == '/c/A (vers 3).wav' and n == 3)
  check('la prossima e\' la 4', M.version_path('/c/A.wav', n + 1) == '/c/A (vers 4).wav')
  last, n = M.latest_version('/c/Nuovo.wav', exists)
  check('nessun file con quel nome: si copia col nome suo', last == nil and n == 0)
  last, n = M.latest_version('/c/B.wav', exists)
  check('senza il file senza numero si riparte dal nome suo', last == nil and n == 0)
end

-- Scorrimento storico messaggi nel pannello STATO
do
  local entries = {
    {text = 'riga A1', key = 'PA'},
    {text = 'riga B1 altro progetto', key = 'PB'},
    {text = 'riga globale', key = '*'},
    {text = 'riga A2 lunga', key = 'PA'},
  }
  local function fake_wrap(s, max_w)
    if #s > max_w then return {s:sub(1, max_w), s:sub(max_w + 1)} end
    return {s}
  end
  local linesA = M.collect_log_lines(entries, 'PA', fake_wrap, 8)
  check('storico filtra progetto + generali e wrappa in ordine',
    #linesA == 5 and linesA[1] == 'riga A1' and linesA[2] == 'riga glo' and linesA[3] == 'bale' and linesA[4] == 'riga A2 ' and linesA[5] == 'lunga')
  local linesB = M.collect_log_lines(entries, 'PB', fake_wrap, 40)
  check('storico altro progetto non vede righe di PA', #linesB == 2 and linesB[1] == 'riga B1 altro progetto' and linesB[2] == 'riga globale')

  local s0, m0 = M.clamp_log_scroll(3, 4, 5)
  check('clamp: niente scroll se tutte le righe entrano', s0 == 0 and m0 == 0)
  local s1, m1 = M.clamp_log_scroll(-4, 12, 5)
  check('clamp: non scende sotto 0', s1 == 0 and m1 == 7)
  local s2, m2 = M.clamp_log_scroll(99, 12, 5)
  check('clamp: si ferma esattamente in fondo', s2 == 7 and m2 == 7)
  local s3, m3 = M.clamp_log_scroll(3.6, 12, 5)
  check('clamp: posizione intermedia valida', s3 == 4 and m3 == 7)
end

print(fails == 0 and '\nTUTTI OK' or ('\nFALLITI: ' .. fails)); os.exit(fails == 0 and 0 or 1)
