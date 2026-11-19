-- @noindex
-- ZP Render & Copy: finestra di controllo + servizio di copia automatica.
--
-- Come si usa:
--   1) la prima volta scegli la cartella di consegna (la cartella del render resta quella
--      del progetto, di solito Mixdown, e la imposta anche il Gestore Progetto);
--   2) con "Copia automatica: ON" e la finestra aperta, ogni file audio NUOVO e completo
--      che compare in Mixdown (render normale, Gestore Progetto, Render Queue) viene
--      copiato nella cartella di consegna, mantenendo le sottocartelle di sezione;
--   3) con "Copia automatica: OFF", o con la finestra chiusa, REAPER lavora solo in locale.
--      I file creati mentre la copia e' spenta non vengono copiati in seguito.
-- Se la copia e' ON ma il progetto non ha una cartella di consegna, lo script lo segnala
-- e chiede dove metterli. Il pulsante in toolbar e' acceso solo con la copia ON.
-- Con la Render Queue il servizio resta sul progetto originale, non su quello temporaneo.
-- Con piu' progetti aperti in tab, registro, stato e ultima copia sono tenuti per progetto.
-- Domande e aiuto si disegnano dentro la finestra (non nei riquadri di sistema).
-- "Sincronizza ora" confronta Mixdown e consegna e copia i file mancanti, di dimensione
-- diversa o piu' recenti (stesso nome, versione aggiornata), dopo una conferma.
-- Chiudendo la finestra durante una copia, lo script chiede se aspettare che finisca.
-- Sistemi: macOS e Linux usano i comandi 'find' e 'stat'; Windows usa le funzioni di REAPER
-- e l'estensione js_ReaScriptAPI (JS_File_Stat), da installare con ReaPack.

local sep = package.config:sub(1, 1)
-- Zoom proporzionale (ZP_GfxScale.lua): finestra di partenza 650x540; ingrandendola cresce tutto insieme (e allungandola cresce il registro).
local gfx = gfx
do
  local zp_dir = (debug.getinfo(1, 'S').source:gsub('^@', ''):match('^(.*)[/\\]') or '.')
  local zp_chunk = loadfile(zp_dir .. sep .. '..' .. sep .. 'ZP_GfxScale.lua')
    or (reaper and reaper.GetResourcePath and loadfile(reaper.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'ZP Suite' .. sep .. 'ZP Studio Suite' .. sep .. 'ZP_GfxScale.lua'))
  if gfx and zp_chunk then
    ZP_GFX_SCALE_FN = function(w, h) return math.max(0.6, math.min(3.0, math.min(w / 650, h / 540))) end
    gfx = zp_chunk().wrap(gfx)
  end
end
local ui_path = reaper.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'ZP Suite' .. sep .. 'ZP Studio Suite' .. sep .. 'ZP_UI.lua'
local ok, UI = pcall(dofile, ui_path)
if not ok then
  reaper.ShowMessageBox('Impossibile caricare ZP_UI.lua. Verifica l’installazione di ZP Studio Suite.', 'ZP Render & Copy', 0)
  return
end

local TITLE = 'ZP Render & Copy'
local HELP = [[1. Scegli la cartella di consegna e premi «Salva stato» per salvarla nel progetto insieme alle impostazioni di render. «Apri render» apre la finestra di render di REAPER.

2. Con la finestra aperta e «Copia automatica: ON», lo strumento controlla Mixdown e le sue sottocartelle. Se la cartella di render è separata, controlla anche quella al primo livello. Copia i file audio creati o aggiornati da quando hai acceso il servizio, quando data e dimensione si sono stabilizzate. In consegna conserva le sottocartelle di Mixdown.

3. Se renderizzi dal Gestore Progetto o dalla Render Queue, lascia aperto Render & Copy. Per la coda, quando REAPER passa al progetto temporaneo, la consegna è quella del progetto che ha messo in coda quel render.

4. «Sincronizza ora» confronta le cartelle sorvegliate con la consegna, anche con la copia automatica su OFF. Dopo la conferma, copia i file mancanti, più recenti o di dimensione diversa.

5. Stesso nome in consegna: quando in consegna c’è già un file con lo stesso nome puoi sostituirlo oppure tenere tutte le versioni. Con «Tieni le versioni» il file che c’è resta e il nuovo viene copiato come «nome (vers 2)», «nome (vers 3)» e così via. Il pulsante «Stesso nome in consegna» vale per la copia automatica; «Sincronizza ora» te lo chiede ogni volta.

«Mostra in consegna» mostra l’ultima copia di questo progetto nel gestore file, oppure apre la sua cartella di consegna.

Con più progetti aperti in tab, cartelle, stato e messaggi sono quelli del progetto in primo piano. Una copia già avviata per un altro progetto prosegue e lo stato lo dice.

Su Windows, per la copia automatica e «Sincronizza ora» serve l’estensione js_ReaScriptAPI. Su Linux, per aprire il gestore file serve xdg-open.]]
local SECTION, KEY = 'ZP_RENDER_COPY', 'DESTINATION'
local ACTION_RENDER_DIALOG = 40015 -- File: Render project to disk...
local POLL = 1.0       -- secondi tra un controllo e il successivo
local STABLE = 3.0     -- secondi senza variazioni prima di considerare il file finito
local BUDGET = 0.02    -- secondi di copia per ciclo (REAPER resta reattivo)
local CHUNK = 4 * 1024 * 1024
-- Estensioni copiate: solo audio, cosi' report e file di servizio restano fuori.
local AUDIO_EXT = {wav = true, w64 = true, mp3 = true, flac = true, ogg = true, opus = true,
  aif = true, aiff = true, aifc = true, m4a = true, aac = true, wv = true, caf = true}

local os_name = reaper.GetOS():lower()
local WIN = os_name:find('win') ~= nil
local MAC = (os_name:find('osx') or os_name:find('mac')) ~= nil
-- macOS e Linux: comandi di sistema find+stat. Windows: funzioni di REAPER
-- (EnumerateFiles) e JS_File_Stat dell'estensione js_ReaScriptAPI, senza finestre di comando.
local USE_API = WIN
local SERVICE_OK = true
local SERVICE_WHY = nil
if WIN and not reaper.JS_File_Stat then
  SERVICE_OK = false
  SERVICE_WHY = 'su Windows serve l\'estensione js_ReaScriptAPI (installala da ReaPack)'
end
if USE_API then POLL = 2.0 end -- senza find, ogni controllo scorre le cartelle: meno frequente

local _, _, sec, cmd = reaper.get_action_context()

-- ---------------------------------------------------------------- registro messaggi
-- Ogni riga porta il progetto a cui si riferisce: la finestra mostra solo quelle del
-- progetto in primo piano (e quelle generali), cosi' con piu' progetti aperti in tab
-- lo stato di uno non si mescola con quello di un altro.
local logs = {}
local current_key = ''      -- chiave del progetto in primo piano, aggiornata a ogni ciclo
local GENERAL = '*'
local function log(msg, key)
  table.insert(logs, 1, {text = os.date('%H:%M:%S') .. '  ' .. tostring(msg), key = key or current_key})
  if #logs > 120 then table.remove(logs) end
end

-- ---------------------------------------------------------------- messaggi nella finestra
-- Domande e aiuto compaiono dentro la finestra di Render & Copy, con lo stesso aspetto
-- del resto, invece che nei riquadri di sistema. Si mettono in fila: uno alla volta.
-- buttons = { {etichetta, funzione, stile}, ... }: il primo e' la scelta di Invio, l'ultimo di Esc.
local dialogs = {}
local function open_dialog(title, text, buttons)
  dialogs[#dialogs + 1] = {title = title, text = text, buttons = buttons, scroll = 0}
end

-- ---------------------------------------------------------------- utilita'
local function norm(path)
  path = (path or ''):gsub('\\', '/')
  local trimmed = path:gsub('/+$', '')
  if path ~= trimmed and (trimmed == '' or trimmed:match('^%a:$')) then return trimmed .. '/' end
  return trimmed
end
local function dirname(path)
  return norm(norm(path):match('^(.*/)[^/]+$'))
end
local function filename(path) return norm(path):match('([^/]+)$') or '' end
local function join(folder, name)
  folder = norm(folder)
  return folder .. (folder:sub(-1) == '/' and '' or '/') .. name
end
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function is_abs(p) return p:sub(1, 1) == '/' or p:match('^%a:/') ~= nil end
local function is_inside(p, base)
  if WIN then p, base = p:lower(), base:lower() end -- Windows: maiuscole/minuscole indifferenti
  local prefix = join(base, '')
  return p == base or p:sub(1, #prefix) == prefix
end
local function native_path(p) return WIN and (p:gsub('/', '\\')) or p end

-- RecursiveCreateDirectory restituisce quante cartelle ha CREATO (0 se esiste gia'):
-- per sapere se la cartella e' utilizzabile si prova a scriverci un file.
local function ensure_dir(path)
  reaper.RecursiveCreateDirectory(path, 0)
  local probe = path .. '/.zp-probe-' .. tostring(math.floor(reaper.time_precise() * 1000000) % 1000000)
  local f, err = io.open(probe, 'wb')
  if not f then return false, tostring(err) end
  f:close()
  os.remove(probe)
  return true
end

local function file_exists(p)
  local f = io.open(p, 'rb')
  if f then f:close() return true end
  return false
end

-- Versioni in consegna: "nome.wav", "nome (vers 2).wav", "nome (vers 3).wav"...
local function version_path(dst, n)
  if n <= 1 then return dst end
  local stem, ext = dst:match('^(.*)(%.[^%./]+)$')
  if not stem then stem, ext = dst, '' end
  return ('%s (vers %d)%s'):format(stem, n, ext)
end
-- L'ultima versione presente (percorso e numero), contando di seguito da quella senza numero.
-- 0 = in consegna non c'e' ancora nessun file con quel nome.
local function latest_version(dst, exists)
  exists = exists or file_exists
  if not exists(dst) then return nil, 0 end
  local n = 1
  while exists(version_path(dst, n + 1)) do n = n + 1 end
  return version_path(dst, n), n
end
-- Scelta per la copia automatica: sostituire il file con lo stesso nome, o tenerle tutte.
local keep_versions = reaper.GetExtState and reaper.GetExtState('ZP_RENDER_COPY', 'same_name') == 'keep' or false

local function choose_folder(title, initial)
  local chosen, path = reaper.GetUserFileName(3, title, initial or '', '')
  if chosen and path ~= '' then return path end
end

local function get_destination(proj)
  local n, d = reaper.GetProjExtState(proj, SECTION, KEY)
  if n > 0 and d ~= '' then return norm(d) end
end

local function set_destination(proj, path)
  path = norm(path)
  local ok_d, derr = ensure_dir(path)
  if not ok_d then
    log('ERRORE: la cartella non e\' scrivibile: ' .. path .. ' ' .. tostring(derr))
    return false
  end
  reaper.SetProjExtState(proj, SECTION, KEY, path)
  reaper.MarkProjectDirty(proj)
  log('Cartella di consegna aggiornata. Salva il progetto per conservarla.')
  return true
end

-- ---------------------------------------------------------------- cosa osservare
-- Le cartelle dove compaiono i render: Mixdown del progetto (comprese le sottocartelle
-- di sezione create dal Gestore Progetto) e, se diversa, la cartella di render corrente
-- (solo il suo primo livello, per non scansionare media e registrazioni).
local function add_render_root(roots, rf, pd)
  rf = norm(rf)
  if rf ~= '' and not is_abs(rf) and pd ~= '' then rf = join(pd, rf) end
  if rf == '' or not is_abs(rf) then return end
  for _, r in ipairs(roots) do
    if is_inside(rf, r.path) then return end
  end
  roots[#roots + 1] = {path = rf, recursive = false}
end

-- 'queued' e' il progetto temporaneo della Render Queue, se in primo piano: la sua
-- cartella di render viene osservata in piu', ma le cartelle base sono quelle dell'originale.
local function watch_roots(proj, projfn, queued)
  local roots = {}
  local pd = dirname(projfn or '')
  if pd ~= '' then roots[#roots + 1] = {path = join(pd, 'Mixdown'), recursive = true} end
  local _, rf = reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', '', false)
  add_render_root(roots, rf, pd)
  if queued then
    local _, qrf = reaper.GetSetProjectInfo_String(queued, 'RENDER_FILE', '', false)
    add_render_root(roots, qrf, pd)
  end
  return roots
end

-- File audio modificati di recente in una cartella (data e dimensione con una sola
-- chiamata a find+stat; -mmin riduce l'elenco ai file piu' recenti di 'since').
local function scan_shell(root, recursive, since)
  local out = {}
  local fmt = MAC and "-f '%m %z %N'" or "-c '%Y %s %n'"
  local recent = since and (' -mmin -' .. (math.floor((os.time() - since) / 60) + 2)) or ''
  local command = 'find ' .. shq(root) .. (recursive and '' or ' -maxdepth 1') ..
    ' -type f' .. recent .. ' -exec stat ' .. fmt .. ' {} + 2>/dev/null'
  local h = io.popen(command)
  if not h then return out end
  for line in h:lines() do
    local m, s, name = line:match('^(%d+) (%d+) (.+)$')
    if m then
      local base = filename(name)
      local ext = base:match('%.([^.]+)$')
      if base:sub(1, 1) ~= '.' and ext and AUDIO_EXT[ext:lower()] then
        out[name] = {mtime = tonumber(m), size = tonumber(s)}
      end
    end
  end
  h:close()
  return out
end

-- Windows: data e dimensione con JS_File_Stat. La data puo' essere un numero o un testo
-- (stesso tipo per ogni file): si confronta soltanto con altre date dello stesso tipo.
local function api_stat(path)
  local rv, size, _, mtime = reaper.JS_File_Stat(native_path(path))
  if rv ~= 0 or not mtime then return nil end
  return {mtime = mtime, size = tonumber(size) or 0}
end

-- JS_File_Stat restituisce data e ora locali in questo formato, ordinabile come testo.
local function now_stamp()
  return USE_API and os.date('%Y.%m.%d %H:%M:%S') or os.time()
end

local function api_scan(root, recursive)
  local out = {}
  local function walk(dir, depth)
    local native_dir = native_path(dir)
    reaper.EnumerateFiles(native_dir, -1) -- svuota la cache dell'elenco, per non vedere file vecchi
    local i = 0
    while true do
      local name = reaper.EnumerateFiles(native_dir, i)
      if not name then break end
      i = i + 1
      local ext = name:match('%.([^.]+)$')
      if name:sub(1, 1) ~= '.' and ext and AUDIO_EXT[ext:lower()] then
        local path = join(dir, name)
        local st = api_stat(path)
        if st then out[path] = st end
      end
    end
    if recursive and depth < 8 then
      reaper.EnumerateSubdirectories(native_dir, -1)
      local j = 0
      while true do
        local sub = reaper.EnumerateSubdirectories(native_dir, j)
        if not sub then break end
        j = j + 1
        if sub:sub(1, 1) ~= '.' then walk(join(dir, sub), depth + 1) end
      end
    end
  end
  walk(root, 0)
  return out
end

-- Data di modifica e dimensione di file precisi (a gruppi, con una chiamata a stat ciascuno).
local function stat_files_shell(paths)
  local out = {}
  local fmt = MAC and "-f '%m %z %N'" or "-c '%Y %s %n'"
  local i = 1
  while i <= #paths do
    local args = {}
    for j = i, math.min(i + 59, #paths) do args[#args + 1] = shq(paths[j]) end
    local h = io.popen('stat ' .. fmt .. ' ' .. table.concat(args, ' ') .. ' 2>/dev/null')
    if h then
      for line in h:lines() do
        local m, s, name = line:match('^(%d+) (%d+) (.+)$')
        if m then out[name] = {mtime = tonumber(m), size = tonumber(s)} end
      end
      h:close()
    end
    i = i + 60
  end
  return out
end

local function scan_new(root, recursive, since)
  if USE_API then return api_scan(root, recursive) end
  return scan_shell(root, recursive, since)
end

local function stat_files(paths)
  if not USE_API then return stat_files_shell(paths) end
  local out = {}
  for _, p in ipairs(paths) do
    local st = api_stat(p)
    if st then out[p] = st end
  end
  return out
end

-- Progetto su cui lavorare. Con la Render Queue REAPER mette in primo piano un progetto
-- temporaneo (in QueuedRenders): si resta sul progetto originale, che ha la consegna
-- e la cartella Mixdown. Restituisce progetto, percorso e, se c'e', il progetto accodato.
local home_proj = nil
local function is_queued_path(fn) return norm(fn or ''):find('/QueuedRenders/', 1, true) ~= nil end
local function base_name(fn) return (filename(fn or ''):gsub('%.[Rr][Pp][Pp]$', '')) end

-- Chiave stabile di un progetto: il percorso del file, o il puntatore se non e' ancora salvato.
local function project_key(proj, fn)
  if fn and fn ~= '' then return norm(fn) end
  return tostring(proj)
end
local function project_label(fn)
  local name = base_name(fn)
  return name ~= '' and name or 'progetto non salvato'
end

-- Fra i progetti aperti, quello da cui viene un progetto accodato. REAPER chiama il file
-- della coda "qrender_<data>_<ora>_<nome del progetto>.rpp": si cerca il nome piu' lungo
-- che chiude il nome del file accodato. candidates = { {proj, fn}, ... } non accodati.
local function queued_owner(queued_fn, candidates)
  local q = base_name(queued_fn)
  local best, best_len
  for _, c in ipairs(candidates) do
    local b = base_name(c[2])
    if b ~= '' and #b <= #q and q:sub(-#b) == b and (#b == #q or q:sub(-#b - 1, -#b - 1) == '_') then
      if not best_len or #b > best_len then best, best_len = c, #b end
    end
  end
  return best
end

local function work_project()
  local active, active_fn = reaper.EnumProjects(-1)
  if not active then return nil end
  if not is_queued_path(active_fn) then
    home_proj = active
    return active, active_fn, nil
  end
  local candidates, home = {}, nil
  local i = 0
  while true do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if not is_queued_path(fn) then
      candidates[#candidates + 1] = {p, fn}
      if p == home_proj then home = candidates[#candidates] end
    end
    i = i + 1
  end
  -- Prima il progetto che ha davvero messo in coda questo render, poi l'ultimo su cui
  -- si lavorava, poi il primo aperto.
  local owner = queued_owner(active_fn, candidates) or home or candidates[1]
  if owner then return owner[1], owner[2], active end
  return active, active_fn, nil
end

-- ---------------------------------------------------------------- copia
-- La copia procede a piccoli pezzi a ogni ciclo, cosi' REAPER e la finestra non si
-- bloccano nemmeno con file grandi o verso un NAS lento. Scrive prima un file
-- provvisorio (.zp-part) e lo rinomina solo a copia completata e verificata.
local queue, job = {}, nil
local last_delivered = {} -- per progetto: ultimo file copiato con successo in consegna

local function close_job(remove_tmp)
  if not job then return end
  if job.inp then job.inp:close() end
  if job.out then job.out:close() end
  if remove_tmp then os.remove(job.tmp) end
  job = nil
end

local function start_job(item)
  if item.keep then
    local _, n = latest_version(item.dst)
    if n > 0 then
      item.dst = version_path(item.dst, n + 1)
      item.version = n + 1
    end
  end
  local ok_d, derr = ensure_dir(dirname(item.dst))
  if not ok_d then
    return nil, 'Cartella di consegna non raggiungibile: ' .. dirname(item.dst) .. ' ' .. tostring(derr)
  end
  local inp = io.open(item.src, 'rb')
  if not inp then return nil, 'Impossibile leggere ' .. filename(item.src) end
  local tmp = item.dst .. '.zp-part'
  local out, oerr = io.open(tmp, 'wb')
  if not out then
    inp:close()
    return nil, 'Impossibile scrivere ' .. tmp .. ' ' .. tostring(oerr)
  end
  return {item = item, inp = inp, out = out, tmp = tmp, total = 0}
end

local function finish_job()
  local j = job
  job = nil
  local src_size = j.inp:seek('end')
  j.inp:close()
  local closed, cerr = j.out:close()
  if not closed then
    os.remove(j.tmp)
    return log('ERRORE: scrittura fallita: ' .. filename(j.item.dst) .. ' ' .. tostring(cerr), j.item.pkey)
  end
  if src_size ~= j.total then
    os.remove(j.tmp)
    return log('ERRORE: copia incompleta: ' .. filename(j.item.src), j.item.pkey)
  end
  local moved, merr = os.rename(j.tmp, j.item.dst)
  if WIN and not moved and file_exists(j.item.dst) then
    -- Su Windows rename non sostituisce un file esistente. Teniamo la versione
    -- precedente finché la nuova copia non è al suo posto.
    local backup = j.tmp .. '.previous'
    if not file_exists(backup) and os.rename(j.item.dst, backup) then
      moved, merr = os.rename(j.tmp, j.item.dst)
      if moved then
        if not os.remove(backup) then log('Versione precedente conservata in ' .. backup, j.item.pkey) end
      elseif not os.rename(backup, j.item.dst) then
        log('ERRORE: versione precedente da recuperare in ' .. backup, j.item.pkey)
      end
    end
  end
  if not moved then
    os.remove(j.tmp)
    return log('ERRORE: impossibile completare ' .. filename(j.item.dst) .. ' ' .. tostring(merr), j.item.pkey)
  end
  if j.item.pkey then last_delivered[j.item.pkey] = j.item.dst end
  if j.item.version then
    log(('Copiato: %s in %s come «%s» (la versione precedente resta)'):format(j.item.rel, j.item.destname, filename(j.item.dst)), j.item.pkey)
  else
    log('Copiato: ' .. j.item.rel .. ' in ' .. j.item.destname, j.item.pkey)
  end
end

local function step_copy()
  if not job then
    local item = table.remove(queue, 1)
    if not item then return end
    local j, err = start_job(item)
    if not j then return log('ERRORE: ' .. err, item.pkey) end
    job = j
  end
  local t0 = reaper.time_precise()
  repeat
    local chunk = job.inp:read(CHUNK)
    if not chunk then return finish_job() end
    local ok_w, werr = job.out:write(chunk)
    if not ok_w then
      local name, key = filename(job.item.dst), job.item.pkey
      close_job(true)
      return log('ERRORE: scrittura fallita: ' .. name .. ' ' .. tostring(werr), key)
    end
    job.total = job.total + #chunk
  until reaper.time_precise() - t0 >= BUDGET
end

-- ---------------------------------------------------------------- controllo dei nuovi file
-- Un file e' "nuovo" se e' stato modificato dopo l'accensione della copia automatica
-- e non e' gia' stato copiato (stessa data e stessa dimensione). Diventa "finito"
-- quando data e dimensione restano invariate per STABLE secondi.
local enabled = SERVICE_OK
local window_open = true
local T0 = now_stamp()
local watch, done, asked = {}, {}, {}
local need_dest = false

-- Indicatori: pulsante in toolbar acceso solo con copia ON e finestra aperta; lo stato
-- e' pubblicato anche in ExtState (on/off) per chi volesse leggerlo, ad esempio il Gestore.
local function refresh_indicators()
  local on = enabled and window_open
  if cmd and cmd ~= 0 then
    reaper.SetToggleCommandState(sec, cmd, on and 1 or 0)
    reaper.RefreshToolbar2(sec, cmd)
  end
  reaper.SetExtState(SECTION, 'service', on and 'on' or 'off', false)
end

local function ask_destination(proj, why)
  local function choose()
    if not reaper.ValidatePtr(proj, 'ReaProject*') then return false end
    local path = choose_folder(TITLE .. ' - cartella di consegna', reaper.GetProjectPathEx(proj))
    return path ~= nil and set_destination(proj, path)
  end
  if window_open then
    open_dialog('Manca la cartella di consegna', why .. '\n\nVuoi scegliere ora la cartella di consegna?',
      {{'Scegli cartella', choose, 'auto'}, {'Non ora'}})
    return false
  end
  -- Finestra gia' chiusa (si sta solo finendo una copia): resta il riquadro di sistema.
  local answer = reaper.ShowMessageBox(why .. '\n\nVuoi scegliere ora la cartella di consegna?', TITLE, 4)
  if answer ~= 6 then return false end
  return choose()
end

local function set_enabled(v)
  if not SERVICE_OK or v == enabled then return end
  enabled = v
  watch = {}
  refresh_indicators()
  if v then
    T0 = now_stamp() -- i file creati mentre era spenta non vengono copiati
    log('Copia automatica ATTIVA: i nuovi file di Mixdown verranno copiati nella consegna.', GENERAL)
    local proj, projfn = work_project()
    if proj and not get_destination(proj) then
      asked[projfn or ''] = true
      ask_destination(proj, 'Non so dove copiare i file secondari: in questo progetto non c\'e\' una cartella di consegna.')
    end
  else
    log('Copia automatica SPENTA: i render restano solo in locale.', GENERAL)
  end
end

local function poll(now)
  local proj, projfn, queued_p = work_project()
  if not proj then return end
  local dest = get_destination(proj)
  local found = {}
  for _, r in ipairs(watch_roots(proj, projfn, queued_p)) do
    for path, s in pairs(scan_new(r.path, r.recursive, T0)) do
      if s.size > 0 and s.mtime >= T0 and not found[path] then found[path] = {s = s, root = r.path} end
    end
  end
  for path, f in pairs(found) do
    local sig = f.s.mtime .. ':' .. f.s.size
    if done[path] ~= sig then
      local w = watch[path]
      if not w or w.sig ~= sig then
        watch[path] = {sig = sig, since = now}
      elseif now - w.since >= STABLE then
        if dest then
          done[path] = sig
          watch[path] = nil
          local rel = path:sub(#join(f.root, '') + 1)
          queue[#queue + 1] = {src = path, rel = rel, size = f.s.size, dst = join(dest, rel), destname = filename(dest),
            pkey = project_key(proj, projfn), pname = project_label(projfn), keep = keep_versions}
        else
          need_dest = true -- resta in attesa: si copiera' appena c'e' una destinazione
        end
      end
    end
  end
  for path in pairs(watch) do
    if not found[path] then watch[path] = nil end
  end
end

local function busy()
  return job ~= nil or #queue > 0 or next(watch) ~= nil
end

local function current_state()
  if job then
    local pct = job.item.size > 0 and math.floor(100 * job.total / job.item.size) or 0
    pct = math.max(0, math.min(100, pct))
    if job.item.pkey and job.item.pkey ~= current_key then
      return ('Copia %d%%  %s  (progetto «%s»)'):format(pct, job.item.rel, job.item.pname or '?'), pct
    end
    return ('Copia %d%%  %s'):format(pct, job.item.rel), pct
  end
  if #queue > 0 then
    local others = 0
    for _, item in ipairs(queue) do
      if item.pkey and item.pkey ~= current_key then others = others + 1 end
    end
    if others == #queue then return ('In coda: %d file di un altro progetto'):format(#queue) end
    if others > 0 then return ('In coda: %d file (%d di un altro progetto)'):format(#queue, others) end
    return ('In coda: %d file'):format(#queue)
  end
  if not SERVICE_OK then return 'Copia automatica non disponibile: ' .. (SERVICE_WHY or 'sistema non supportato') end
  if not enabled then return 'Copia automatica SPENTA: i render restano solo in locale' end
  local proj = work_project()
  if proj and not get_destination(proj) then
    return 'ATTENZIONE: manca la cartella di consegna, i nuovi file non vengono copiati'
  end
  if next(watch) ~= nil then return 'Render in chiusura: attendo che il file sia completo...' end
  return 'In attesa di nuovi file in Mixdown'
end

-- ---------------------------------------------------------------- finestra
local last_cap = 0
local last_project, last_project_path
local header_icon

local function label(text, x, y, color)
  gfx.setfont(1, 'Arial', 17)
  UI.set_color(color or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(UI.fit_text(text, gfx.w - x - 24))
end

-- Disegna il messaggio in cima alla fila, sopra la finestra oscurata. Restituisce true
-- se c'e' un messaggio aperto (i comandi sotto restano fermi).
local function draw_dialog(clicked, key)
  local d = dialogs[1]
  if not d then return false end
  gfx.set(0.02, 0.02, 0.03, 0.72)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)
  local w = math.max(260, math.min(gfx.w - 40, 620))
  gfx.setfont(1, 'Arial', 17)
  local lines = UI.wrap_text(d.text, w - 48)
  local line_h, head, foot = 23, 54, 62
  local max_rows = math.max(3, math.floor((gfx.h - 40 - head - foot) / line_h))
  local rows = math.min(#lines, max_rows)
  local h = head + rows * line_h + foot
  local x, y = math.floor((gfx.w - w) / 2), math.max(12, math.floor((gfx.h - h) / 2))
  UI.draw_panel({x = x, y = y, w = w, h = h}, '', {fill = UI.colors.panel, border = UI.colors.panel_border})
  gfx.setfont(1, 'Arial', 21, string.byte('b'))
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = x + 24, y + 18
  gfx.drawstr(UI.fit_text(d.title, w - 48))

  -- Testo lungo: scorre con la rotella o con le frecce.
  local max_scroll = math.max(0, #lines - rows)
  if gfx.mouse_wheel ~= 0 then
    d.scroll = d.scroll - (gfx.mouse_wheel > 0 and 3 or -3)
    gfx.mouse_wheel = 0
  end
  if key == 30064 then d.scroll = d.scroll - 1 elseif key == 1685026670 then d.scroll = d.scroll + 1 end
  d.scroll = math.max(0, math.min(max_scroll, d.scroll))
  gfx.setfont(1, 'Arial', 17)
  UI.set_color(UI.colors.text)
  for i = 1, rows do
    gfx.x, gfx.y = x + 24, y + head + (i - 1) * line_h
    gfx.drawstr(lines[i + d.scroll] or '')
  end
  if max_scroll > 0 then
    local track_h = rows * line_h
    local bar_h = math.max(18, math.floor(track_h * rows / #lines))
    gfx.set(0.45, 0.45, 0.5, 0.35)
    gfx.rect(x + w - 14, y + head, 4, track_h, 1)
    UI.set_color(UI.colors.gold)
    gfx.rect(x + w - 14, y + head + math.floor((track_h - bar_h) * d.scroll / max_scroll), 4, bar_h, 1)
  end

  local chosen
  local bx = x + w - 24
  for i = #d.buttons, 1, -1 do
    local b = d.buttons[i]
    gfx.setfont(1, 'Arial', 17)
    local bw = math.max(120, gfx.measurestr(b[1]) + 36)
    bx = bx - bw
    if UI.draw_button({x = bx, y = y + h - 48, w = bw, h = 34, font = 17}, b[1], i == 1, true, clicked, b[3]) then chosen = i end
    bx = bx - 10
  end
  if key == 13 then chosen = 1 elseif key == 27 then chosen = #d.buttons end
  if chosen then
    table.remove(dialogs, 1)
    local action = d.buttons[chosen][2]
    if action then action() end
  end
  return true
end

-- Apre il gestore file sulla consegna. Finder ed Esplora file possono anche
-- selezionare l'ultima copia, mentre xdg-open apre la cartella che la contiene.
local function open_in_file_manager(path, select_it)
  if WIN then
    local np = native_path(path)
    reaper.ExecProcess('explorer.exe ' .. (select_it and ('/select,"' .. np .. '"') or ('"' .. np .. '"')), -1)
  elseif MAC then
    os.execute('open ' .. (select_it and '-R ' or '') .. shq(path) .. ' >/dev/null 2>&1 &')
  else
    os.execute('xdg-open ' .. shq(select_it and dirname(path) or path) .. ' >/dev/null 2>&1 &')
  end
end

local function reveal_delivery(destination)
  local fm = MAC and 'Finder' or 'file manager'
  local last = last_delivered[current_key]
  if last and destination ~= '' and is_inside(last, norm(destination)) and file_exists(last) then
    open_in_file_manager(last, true)
    log('Mostrato nel ' .. fm .. ': ' .. filename(last))
  elseif destination ~= '' then
    open_in_file_manager(destination, false)
    log('Aperta la cartella di consegna (nessuna copia recente da mostrare).')
  end
end

-- Sincronizza: confronta tutti i file audio di Mixdown con la consegna e copia quelli
-- mancanti, di dimensione diversa o piu' recenti (stesso nome, versione aggiornata).
-- Serve anche come rete di sicurezza, ad esempio dopo una Render Queue.
local function run_sync()
  local proj, projfn, queued_p = work_project()
  if not proj then return end
  local dest = get_destination(proj)
  if not dest then
    ask_destination(proj, 'Non so dove copiare i file: in questo progetto non c\'e\' una cartella di consegna.')
    return
  end
  local src = {}
  for _, r in ipairs(watch_roots(proj, projfn, queued_p)) do
    for path, s in pairs(scan_new(r.path, r.recursive, nil)) do
      if s.size > 0 and not src[path] then src[path] = {s = s, root = r.path} end
    end
  end
  local paths = {}
  for path, f in pairs(src) do
    f.rel = path:sub(#join(f.root, '') + 1)
    f.dst = join(dest, f.rel)
    f.last = latest_version(f.dst)   -- nil se in consegna non c'e' ancora
    paths[#paths + 1] = f.dst
    if f.last and f.last ~= f.dst then paths[#paths + 1] = f.last end
  end
  local dstat = stat_files(paths)
  local function same(d, f) return d ~= nil and d.size == f.s.size and f.s.mtime <= d.mtime end
  local todo, clashes = {}, 0
  for path, f in pairs(src) do
    -- A posto se coincide il file senza numero oppure l'ultima versione tenuta.
    if not (same(dstat[f.dst], f) or (f.last and same(dstat[f.last], f))) then
      if f.last then clashes = clashes + 1 end
      todo[#todo + 1] = {src = path, rel = f.rel, size = f.s.size, dst = f.dst,
        destname = filename(dest), sig = f.s.mtime .. ':' .. f.s.size, clash = f.last ~= nil,
        pkey = project_key(proj, projfn), pname = project_label(projfn)}
    end
  end
  if #todo == 0 then
    log('Sincronizza: la consegna e\' gia\' aggiornata.')
    return
  end
  table.sort(todo, function(a, b) return a.rel < b.rel end)
  local key = project_key(proj, projfn)
  local lines = {
    ('Progetto «%s»'):format(project_label(projfn)),
    'Consegna: ' .. dest,
    '',
    (#todo == 1 and 'In Mixdown c\'è 1 file nuovo o diverso rispetto alla consegna:'
      or ('In Mixdown ci sono %d file nuovi o diversi rispetto alla consegna:'):format(#todo)),
  }
  for i = 1, math.min(#todo, 12) do
    lines[#lines + 1] = '  ' .. todo[i].rel .. (todo[i].clash and '   (c\'è già in consegna)' or '')
  end
  if #todo > 12 then lines[#lines + 1] = ('  … e altri %d'):format(#todo - 12) end
  local function start(keep)
    return function()
      for _, item in ipairs(todo) do
        item.keep = keep
        done[item.src] = item.sig
        queue[#queue + 1] = item
      end
      log(('Sincronizza: %d file in copia%s.'):format(#todo,
        clashes > 0 and (keep and ', le versioni già in consegna restano' or ', sostituendo quelli con lo stesso nome') or ''), key)
    end
  end
  local cancel = {'Annulla', function() log('Sincronizza annullato.', key) end}
  local buttons
  if clashes == 0 then
    buttons = {{(#todo == 1 and 'Copia il file' or ('Copia %d file'):format(#todo)), start(false), 'sync'}, cancel}
  else
    lines[#lines + 1] = ''
    lines[#lines + 1] = (clashes == 1 and '1 file ha già in consegna un file con lo stesso nome.'
      or ('%d file hanno già in consegna un file con lo stesso nome.'):format(clashes))
    lines[#lines + 1] = '«Sostituisci» lo rimpiazza. «Tieni le versioni» lascia quello che c\'è e copia il nuovo come «nome (vers 2)», «(vers 3)»…'
    local replace = {'Sostituisci', start(false), 'sync'}
    local keep = {'Tieni le versioni', start(true), 'auto'}
    -- Invio sceglie quello che fa gia' la copia automatica.
    buttons = keep_versions and {keep, replace, cancel} or {replace, keep, cancel}
  end
  open_dialog('Sincronizza ora', table.concat(lines, '\n'), buttons)
end

local closing, last_err = false, nil
local last_poll = -1e9

local function service_tick()
  local ok_s, err = pcall(function()
    local now = reaper.time_precise()
    if enabled and now - last_poll >= POLL then
      last_poll = now
      poll(now)
    end
    if need_dest then
      need_dest = false
      local proj, projfn = work_project()
      local k = projfn or ''
      if enabled and proj and not asked[k] and not get_destination(proj) then
        asked[k] = true
        ask_destination(proj, 'Sono comparsi nuovi file in Mixdown, ma non so dove copiarli: questo progetto non ha una cartella di consegna.')
      end
    end
    step_copy()
  end)
  if not ok_s and err ~= last_err then
    last_err = err
    log('ERRORE: ' .. tostring(err), GENERAL)
  end
end

local function loop()
  if closing then
    -- Finestra chiusa: si completa solo il lavoro rimasto, poi lo script termina.
    service_tick()
    if busy() then reaper.defer(loop) end
    return
  end

  local key = gfx.getchar()
  if key < 0 or (key == 27 and not dialogs[1]) then
    reaper.SetExtState('ZP_RENDER_COPY', 'window', table.concat({gfx.dock(-1, 0, 0, 0, 0)}, ','), true)
    gfx.quit()
    window_open = false
    refresh_indicators()
    if enabled and busy() then
      local answer = reaper.ShowMessageBox(
        'Una copia e\' ancora in corso o in attesa.\n\nVuoi aspettare che finisca prima di chiudere?\n' ..
        '(No = interrompi: in consegna non resta nessun file a meta)', TITLE, 4)
      if answer == 6 then
        closing = true
        reaper.defer(loop)
        return
      end
    end
    close_job(true)
    return
  end

  service_tick()

  local proj, project_path = work_project()
  current_key = project_key(proj, project_path)
  if proj ~= last_project or project_path ~= last_project_path then
    -- Un progetto appena salvato cambia chiave: le sue righe e la sua ultima copia lo seguono.
    if proj == last_project and last_project_path ~= nil then
      local old_key = project_key(proj, last_project_path)
      for _, entry in ipairs(logs) do if entry.key == old_key then entry.key = current_key end end
      last_delivered[current_key], last_delivered[old_key] = last_delivered[old_key], nil
    end
    log('Progetto in primo piano: ' .. project_label(project_path) .. '.')
    last_project, last_project_path = proj, project_path
  end
  local _, render_path = reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', '', false)
  local _, destination = reaper.GetProjExtState(proj, SECTION, KEY)
  local pressed = gfx.mouse_cap & 1 == 1 and last_cap & 1 == 0
  last_cap = gfx.mouse_cap
  -- Con un messaggio aperto i comandi della finestra restano fermi.
  local had_dialog = dialogs[1] ~= nil
  local clicked = pressed and not had_dialog
  local width = math.max(240, gfx.w - 44)

  UI.fill_background()
  UI.draw_header({
    title = TITLE, title_size = 24, credit_size = 15, description_size = 17,
    icon_id = header_icon, icon_src_size = 96,
    description = 'Impostazioni di render e consegna del progetto',
  })
  if UI.draw_button({x = gfx.w - 56, y = 16, w = 34, h = 28}, '?', false, true, clicked, 'tab') or (key == 63 and not had_dialog) then
    open_dialog(TITLE .. ' · Aiuto', HELP, {{'Chiudi'}})
  end

  UI.draw_panel({x = 22, y = 104, w = width, h = 90}, '')
  label('CARTELLA DEL RENDER', 34, 110, UI.colors.muted)
  label(render_path ~= '' and render_path or (reaper.GetProjectPathEx(proj) .. ' (cartella del progetto)'), 34, 132)
  if UI.draw_button({x = 34, y = 154, w = 165, h = 30, font = 17}, 'Scegli cartella', false, true, clicked) then
    local path = choose_folder('Cartella del render', render_path ~= '' and render_path or reaper.GetProjectPathEx(proj))
    if path then
      reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', path, true)
      reaper.MarkProjectDirty(proj)
      log('Cartella del render aggiornata. Salva il progetto per conservarla.')
    end
  end

  UI.draw_panel({x = 22, y = 204, w = width, h = 90}, '')
  label('CARTELLA DI CONSEGNA', 34, 210, UI.colors.muted)
  label(destination ~= '' and destination or 'Nessuna cartella selezionata', 34, 232)
  if UI.draw_button({x = 34, y = 254, w = 165, h = 30, font = 17}, 'Scegli cartella', false, true, clicked) then
    local path = choose_folder('Cartella di consegna', destination ~= '' and destination or reaper.GetProjectPathEx(proj))
    if path then set_destination(proj, path) end
  end
  if UI.draw_button({x = 209, y = 254, w = 200, h = 30, font = 17}, 'Mostra in consegna', false, destination ~= '', clicked, 'reveal') then
    reveal_delivery(destination)
  end
  if UI.draw_button({x = 419, y = 254, w = 170, h = 30, font = 17}, 'Sincronizza ora', false, SERVICE_OK and destination ~= '', clicked, 'sync') then
    run_sync()
  end

  local on_label = 'Copia automatica: ' .. (enabled and 'ON' or 'OFF')
  if UI.draw_button({x = 22, y = 307, w = 250, h = 36, font = 17}, on_label, enabled, SERVICE_OK, clicked, 'auto') then
    set_enabled(not enabled)
  end
  if UI.draw_button({x = 282, y = 307, w = 150, h = 36, font = 17}, 'Apri render', false, true, clicked, 'render') then
    log(enabled and 'Finestra di render aperta: copia automatica attiva.' or 'Finestra di render aperta: copia automatica spenta.')
    reaper.Main_OnCommand(ACTION_RENDER_DIALOG, 0)
    last_cap = gfx.mouse_cap
  end
  if UI.draw_button({x = 442, y = 307, w = 150, h = 36, font = 17}, 'Salva stato', false, true, clicked, 'save') then
    reaper.Main_SaveProject(proj, false)
    local _, saved_path = reaper.EnumProjects(-1)
    if saved_path ~= '' and reaper.GetSetProjectInfo(proj, 'DIRTY', 0, false) == 0 then
      log('Impostazioni salvate nel progetto: ' .. saved_path)
    else
      log('Il progetto non risulta salvato. Controlla e riprova.')
    end
  end

  local same_label = 'Stesso nome in consegna: ' .. (keep_versions and 'TIENI LE VERSIONI' or 'SOSTITUISCI')
  if UI.draw_button({x = 22, y = 351, w = 410, h = 32, font = 17}, same_label, keep_versions, true, clicked, 'auto') then
    keep_versions = not keep_versions
    reaper.SetExtState('ZP_RENDER_COPY', 'same_name', keep_versions and 'keep' or 'replace', true)
    log(keep_versions and 'Stesso nome in consegna: il file che c\'è resta, il nuovo viene copiato come «nome (vers 2)», «(vers 3)»…'
      or 'Stesso nome in consegna: il nuovo file sostituisce quello che c\'è.', GENERAL)
  end

  local panel_h = math.max(90, gfx.h - 418)
  local bottom = 396 + panel_h
  UI.draw_panel({x = 22, y = 396, w = width, h = panel_h}, '')
  label('STATO', 34, 401, UI.colors.muted)
  local state, pct = current_state()
  label(state, 34, 425)
  local y = 452
  if pct then
    gfx.set(0.45, 0.45, 0.45, 0.35)
    gfx.rect(34, y, width - 24, 8, 1)
    gfx.set(0.3, 0.75, 0.4, 1)
    gfx.rect(34, y, math.floor((width - 24) * pct / 100), 8, 1)
    y = y + 18
  end
  gfx.setfont(1, 'Arial', 17)
  for _, entry in ipairs(logs) do
    if entry.key == current_key or entry.key == GENERAL then
      for _, line in ipairs(UI.wrap_text(entry.text, width - 24)) do
        if y + 21 > bottom then break end
        label(line, 34, y, UI.colors.muted)
        y = y + 21
      end
      if y + 21 > bottom then break end
    end
  end
  -- Un messaggio aperto in questo stesso ciclo si disegna dal prossimo: il clic che lo ha
  -- aperto non deve premere anche uno dei suoi pulsanti.
  if had_dialog then draw_dialog(pressed, key) else gfx.mouse_wheel = 0 end
  gfx.update()
  reaper.defer(loop)
end

-- Per i collaudi: solo la logica, senza aprire la finestra.
if rawget(_G, 'ZP_RENDER_COPY_TEST') then
  return {queued_owner = queued_owner, project_key = project_key, project_label = project_label,
    is_inside = is_inside, work_project = work_project, version_path = version_path, latest_version = latest_version}
end

-- ---------------------------------------------------------------- avvio
refresh_indicators()
reaper.atexit(function()
  close_job(true)
  window_open = false
  refresh_indicators()
end)

if SERVICE_OK then
  log('Pronto. Copia automatica attiva: copia i nuovi file audio che compaiono in Mixdown.', GENERAL)
else
  log('Copia automatica non disponibile: ' .. (SERVICE_WHY or 'sistema non supportato') .. '. La finestra serve per le impostazioni.', GENERAL)
end

local d, x, y, w, h = (reaper.GetExtState('ZP_RENDER_COPY', 'window') .. ','):match('([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)')
gfx.init(TITLE, tonumber(w) or 650, math.max(tonumber(h) or 0, 540), tonumber(d) or 0, tonumber(x) or 200, tonumber(y) or 150)
local script_dir = dirname(debug.getinfo(1, 'S').source:sub(2))
header_icon = gfx.loadimg(0, join(script_dir, 'assets/zp_render_copy.png'))
loop()
