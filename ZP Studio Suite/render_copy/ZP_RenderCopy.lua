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
-- "Sincronizza ora" confronta Mixdown e consegna e copia i file mancanti, di dimensione
-- diversa o piu' recenti (stesso nome, versione aggiornata), dopo una conferma.
-- Chiudendo la finestra durante una copia, lo script chiede se aspettare che finisca.
-- Il servizio usa i comandi di sistema 'find' e 'stat': macOS (e Linux).

local sep = package.config:sub(1, 1)
local ui_path = reaper.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'ZP Suite' .. sep .. 'ZP Studio Suite' .. sep .. 'ZP_UI.lua'
local ok, UI = pcall(dofile, ui_path)
if not ok then
  reaper.ShowMessageBox('Impossibile caricare ZP_UI.lua. Verifica l’installazione di ZP Studio Suite.', 'ZP Render & Copy', 0)
  return
end

local TITLE = 'ZP Render & Copy'
local HELP = [[1. Scegli la cartella di consegna e premi «Salva stato» per salvarla nel progetto insieme alle impostazioni di render. «Apri render» apre la finestra di render di REAPER.

2. Con la finestra aperta e «Copia automatica: ON», lo strumento controlla Mixdown e le sue sottocartelle. Se la cartella di render è separata, controlla anche quella al primo livello. Copia i file audio creati o aggiornati da quando hai acceso il servizio, quando data e dimensione si sono stabilizzate. In consegna conserva le sottocartelle di Mixdown.

3. Se renderizzi dal Gestore Progetto o dalla Render Queue, lascia aperto Render & Copy. Per la coda, quando REAPER passa al progetto temporaneo, la consegna resta quella del progetto di lavoro.

4. Su Mac, «Sincronizza ora» confronta le cartelle sorvegliate con la consegna, anche con la copia automatica su OFF. Dopo la conferma, copia i file mancanti, più recenti o di dimensione diversa. Può sostituire un file con lo stesso nome in consegna.

«Mostra in consegna» seleziona l’ultima copia nel Finder oppure apre la cartella di consegna.]]
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
local SERVICE_OK = not os_name:find('win')
local MAC = (os_name:find('osx') or os_name:find('mac')) ~= nil

local _, _, sec, cmd = reaper.get_action_context()

-- ---------------------------------------------------------------- registro messaggi
local logs = {}
local function log(msg)
  table.insert(logs, 1, os.date('%H:%M:%S') .. '  ' .. tostring(msg))
  if #logs > 40 then table.remove(logs) end
end

-- ---------------------------------------------------------------- utilita'
local function norm(path)
  return ((path or ''):gsub('\\', '/'):gsub('/+$', ''))
end
local function dirname(path) return norm(path):match('^(.*)/[^/]+$') or '' end
local function filename(path) return norm(path):match('([^/]+)$') or '' end
local function join(folder, name) return norm(folder) .. '/' .. name end
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

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
  if rf ~= '' and rf:sub(1, 1) ~= '/' and pd ~= '' then rf = join(pd, rf) end
  if rf == '' or rf:sub(1, 1) ~= '/' then return end
  for _, r in ipairs(roots) do
    if rf == r.path or rf:sub(1, #r.path + 1) == r.path .. '/' then return end
  end
  roots[#roots + 1] = {path = rf, recursive = false}
end

-- 'queued' e' il progetto temporaneo della Render Queue, se in primo piano: la sua
-- cartella di render viene osservata in piu', ma le cartelle base sono quelle dell'originale.
local function watch_roots(proj, projfn, queued)
  local roots = {}
  local pd = dirname(projfn or '')
  if pd ~= '' then roots[#roots + 1] = {path = pd .. '/Mixdown', recursive = true} end
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
local function scan_new(root, recursive, since)
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

-- Data di modifica e dimensione di file precisi (a gruppi, con una chiamata a stat ciascuno).
local function stat_files(paths)
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

-- Progetto su cui lavorare. Con la Render Queue REAPER mette in primo piano un progetto
-- temporaneo (in QueuedRenders): si resta sul progetto originale, che ha la consegna
-- e la cartella Mixdown. Restituisce progetto, percorso e, se c'e', il progetto accodato.
local home_proj = nil
local function is_queued_path(fn) return (fn or ''):find('/QueuedRenders/', 1, true) ~= nil end
local function work_project()
  local active, active_fn = reaper.EnumProjects(-1)
  if not active then return nil end
  if not is_queued_path(active_fn) then
    home_proj = active
    return active, active_fn, nil
  end
  local first
  local i = 0
  while true do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if not is_queued_path(fn) then
      if p == home_proj then return p, fn, active end
      first = first or {p, fn}
    end
    i = i + 1
  end
  if first then return first[1], first[2], active end
  return active, active_fn, nil
end

-- ---------------------------------------------------------------- copia
-- La copia procede a piccoli pezzi a ogni ciclo, cosi' REAPER e la finestra non si
-- bloccano nemmeno con file grandi o verso un NAS lento. Scrive prima un file
-- provvisorio (.zp-part) e lo rinomina solo a copia completata e verificata.
local queue, job = {}, nil
local last_delivered = nil -- ultimo file copiato con successo in consegna

local function close_job(remove_tmp)
  if not job then return end
  if job.inp then job.inp:close() end
  if job.out then job.out:close() end
  if remove_tmp then os.remove(job.tmp) end
  job = nil
end

local function start_job(item)
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
    return log('ERRORE: scrittura fallita: ' .. filename(j.item.dst) .. ' ' .. tostring(cerr))
  end
  if src_size ~= j.total then
    os.remove(j.tmp)
    return log('ERRORE: copia incompleta: ' .. filename(j.item.src))
  end
  local moved, merr = os.rename(j.tmp, j.item.dst)
  if not moved then
    os.remove(j.tmp)
    return log('ERRORE: impossibile completare ' .. filename(j.item.dst) .. ' ' .. tostring(merr))
  end
  last_delivered = j.item.dst
  log('Copiato: ' .. j.item.rel .. ' in ' .. j.item.destname)
end

local function step_copy()
  if not job then
    local item = table.remove(queue, 1)
    if not item then return end
    local j, err = start_job(item)
    if not j then return log('ERRORE: ' .. err) end
    job = j
  end
  local t0 = reaper.time_precise()
  repeat
    local chunk = job.inp:read(CHUNK)
    if not chunk then return finish_job() end
    local ok_w, werr = job.out:write(chunk)
    if not ok_w then
      local name = filename(job.item.dst)
      close_job(true)
      return log('ERRORE: scrittura fallita: ' .. name .. ' ' .. tostring(werr))
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
local T0 = os.time()
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
  local answer = reaper.ShowMessageBox(why .. '\n\nVuoi scegliere ora la cartella di consegna?', TITLE, 4)
  if answer ~= 6 then return false end
  local path = choose_folder(TITLE .. ' - cartella di consegna', reaper.GetProjectPathEx(proj))
  return path ~= nil and set_destination(proj, path)
end

local function set_enabled(v)
  if not SERVICE_OK or v == enabled then return end
  enabled = v
  watch = {}
  refresh_indicators()
  if v then
    T0 = os.time() -- i file creati mentre era spenta non vengono copiati
    log('Copia automatica ATTIVA: i nuovi file di Mixdown verranno copiati nella consegna.')
    local proj, projfn = work_project()
    if proj and not get_destination(proj) then
      asked[projfn or ''] = true
      ask_destination(proj, 'Non so dove copiare i file secondari: in questo progetto non c\'e\' una cartella di consegna.')
    end
  else
    log('Copia automatica SPENTA: i render restano solo in locale.')
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
          local rel = path:sub(#f.root + 2)
          queue[#queue + 1] = {src = path, rel = rel, size = f.s.size, dst = join(dest, rel), destname = filename(dest)}
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
    return ('Copia %d%%  %s'):format(pct, job.item.rel), pct
  end
  if #queue > 0 then return ('In coda: %d file'):format(#queue) end
  if not SERVICE_OK then return 'Copia automatica disponibile solo su macOS' end
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

-- Apre il Finder sull'ultimo file consegnato (selezionato), oppure sulla cartella
-- di consegna se non c'e' ancora una copia recente. Da li' si usano le funzioni
-- del Mac: Condividi, link Dropbox/iCloud dal clic destro, AirDrop, Mail.
local function reveal_delivery(destination)
  if not MAC then return end
  if last_delivered and file_exists(last_delivered) then
    os.execute('open -R ' .. shq(last_delivered) .. ' >/dev/null 2>&1 &')
    log('Mostrato nel Finder: ' .. filename(last_delivered))
  elseif destination ~= '' then
    os.execute('open ' .. shq(destination) .. ' >/dev/null 2>&1 &')
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
    f.rel = path:sub(#f.root + 2)
    f.dst = join(dest, f.rel)
    paths[#paths + 1] = f.dst
  end
  local dstat = stat_files(paths)
  local todo = {}
  for path, f in pairs(src) do
    local d = dstat[f.dst]
    if not d or d.size ~= f.s.size or f.s.mtime > d.mtime then
      todo[#todo + 1] = {src = path, rel = f.rel, size = f.s.size, dst = f.dst,
        destname = filename(dest), sig = f.s.mtime .. ':' .. f.s.size}
    end
  end
  if #todo == 0 then
    log('Sincronizza: la consegna e\' gia\' aggiornata.')
    return
  end
  table.sort(todo, function(a, b) return a.rel < b.rel end)
  local answer = reaper.ShowMessageBox(
    ('In Mixdown ci sono %d file nuovi o diversi rispetto alla consegna (mancanti, di dimensione diversa o piu\' recenti).\n\nVuoi copiarli ora?'):format(#todo),
    TITLE, 4)
  if answer ~= 6 then
    log('Sincronizza annullato.')
    return
  end
  for _, item in ipairs(todo) do
    done[item.src] = item.sig
    queue[#queue + 1] = item
  end
  log(('Sincronizza: %d file in copia.'):format(#todo))
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
    log('ERRORE: ' .. tostring(err))
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
  if key < 0 or key == 27 then
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
  if proj ~= last_project or project_path ~= last_project_path then
    log('Impostazioni del progetto corrente.')
    last_project, last_project_path = proj, project_path
  end
  local _, render_path = reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', '', false)
  local _, destination = reaper.GetProjExtState(proj, SECTION, KEY)
  local clicked = gfx.mouse_cap & 1 == 1 and last_cap & 1 == 0
  last_cap = gfx.mouse_cap
  local width = math.max(240, gfx.w - 44)

  UI.fill_background()
  UI.draw_header({
    title = TITLE, title_size = 24, credit_size = 15, description_size = 17,
    icon_id = header_icon, icon_src_size = 96,
    description = 'Impostazioni di render e consegna del progetto',
  })
  if UI.draw_button({x = gfx.w - 56, y = 16, w = 34, h = 28}, '?', false, true, clicked, 'tab') or key == 63 then
    reaper.ShowMessageBox(HELP, TITLE .. ' · Aiuto', 0)
    last_cap = gfx.mouse_cap
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
  if UI.draw_button({x = 209, y = 254, w = 200, h = 30, font = 17}, 'Mostra in consegna', false, MAC and destination ~= '', clicked, 'reveal') then
    reveal_delivery(destination)
  end
  if UI.draw_button({x = 419, y = 254, w = 170, h = 30, font = 17}, 'Sincronizza ora', false, MAC and destination ~= '', clicked, 'sync') then
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
      last_project_path = saved_path
      log('Impostazioni salvate nel progetto: ' .. saved_path)
    else
      log('Il progetto non risulta salvato. Controlla e riprova.')
    end
  end

  local panel_h = math.max(90, gfx.h - 378)
  local bottom = 356 + panel_h
  UI.draw_panel({x = 22, y = 356, w = width, h = panel_h}, '')
  label('STATO', 34, 361, UI.colors.muted)
  local state, pct = current_state()
  label(state, 34, 385)
  local y = 412
  if pct then
    gfx.set(0.45, 0.45, 0.45, 0.35)
    gfx.rect(34, y, width - 24, 8, 1)
    gfx.set(0.3, 0.75, 0.4, 1)
    gfx.rect(34, y, math.floor((width - 24) * pct / 100), 8, 1)
    y = y + 18
  end
  gfx.setfont(1, 'Arial', 17)
  for _, entry in ipairs(logs) do
    for _, line in ipairs(UI.wrap_text(entry, width - 24)) do
      if y + 21 > bottom then break end
      label(line, 34, y, UI.colors.muted)
      y = y + 21
    end
    if y + 21 > bottom then break end
  end
  gfx.update()
  reaper.defer(loop)
end

-- ---------------------------------------------------------------- avvio
refresh_indicators()
reaper.atexit(function()
  close_job(true)
  window_open = false
  refresh_indicators()
end)

if SERVICE_OK then
  log('Pronto. Copia automatica attiva: copia i nuovi file audio che compaiono in Mixdown.')
else
  log('La copia automatica funziona solo su macOS: la finestra serve per le impostazioni.')
end

local d, x, y, w, h = (reaper.GetExtState('ZP_RENDER_COPY', 'window') .. ','):match('([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)')
gfx.init(TITLE, tonumber(w) or 650, tonumber(h) or 500, tonumber(d) or 0, tonumber(x) or 200, tonumber(y) or 150)
local script_dir = dirname(debug.getinfo(1, 'S').source:sub(2))
header_icon = gfx.loadimg(0, join(script_dir, 'assets/zp_render_copy.png'))
loop()
