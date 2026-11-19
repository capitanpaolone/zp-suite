-- @description ZP Consolidate - copia in Media le sorgenti usate dal progetto e aggiorna i riferimenti
-- @author Paolo Balestri
-- @version 1.0
-- @about
--   Raccoglie in Media, con copie byte per byte verificate, le sorgenti file di tutti i take (anche
--   inattivi: audio, MIDI esterni, video, sorgenti SECTION/reverse) e gli SRT/VTT del progetto
--   (registro ZP, SRT collegati agli item, SRT accanto ai media). Non converte, non ricampiona, non taglia,
--   non sposta e non cancella gli originali. Prima di cambiare i riferimenti salva il progetto e conserva
--   una copia di sicurezza del RPP; i riferimenti sono cambiati in un solo blocco Undo.
--   Una sorgente non raggiungibile (per esempio un file Dropbox non ancora scaricato) non e' data per
--   mancante: puoi riprovare, scegliere il file corretto, saltarla o annullare tutto.
--   La finestra offre tre comandi: «Consolida progetto», «Pulisci Media» (sposta in una cartella fuori da
--   Media i file che il progetto non usa; non cancella nulla) e «Numera item» (rinomina in sequenza gli item
--   delle tracce selezionate partendo dal nome della traccia), piu' un pulsante ? con l'aiuto.

-- Zoom proporzionale (ZP_GfxScale.lua): finestra di partenza 650x582; ingrandendola cresce tutto insieme.
local gfx = gfx
do
  local zp_dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)[/\\]") or ".")
  local zp_chunk = loadfile(zp_dir .. package.config:sub(1, 1) .. "ZP_GfxScale.lua")
  if zp_chunk then
    ZP_GFX_SCALE_FN = function(w, h) return math.max(0.6, math.min(3.0, math.min(w / 650, h / 582))) end
    gfx = zp_chunk().wrap(gfx)
  end
end
local r = reaper
local TITLE = "ZP Consolidate"
local C = {}                      -- interfaccia interna, usata dai collaudi
local sep = package.config:sub(1, 1)
local IS_WIN = tostring(r.GetOS and r.GetOS() or ""):match("Win") ~= nil
local CHUNK, BUDGET = 1024 * 1024, 0.012
local MAX_USAGE_LINES = 4

---------------------------------------------------------------------------
-- Percorsi e file
---------------------------------------------------------------------------
local function slash(p) return (tostring(p or ""):gsub("\\", "/")) end
local function norm(path)
  local p = slash(path)
  while p:find("/./", 1, true) do p = p:gsub("/%./", "/") end
  p = p:gsub("([^/])//+", "%1/")
  p = p:gsub("(.)/+$", "%1")
  if IS_WIN then p = p:lower() end
  return p
end
local function lkey(path) return norm(path):lower() end
local function basename(p) return slash(p):match("[^/]+$") or tostring(p) end
local function split_ext(name)
  local ext = name:match("(%.[^./]+)$") or ""
  return name:sub(1, #name - #ext), ext
end
local function join(a, b)
  local last = a:sub(-1)
  if last == "/" or last == "\\" then return a .. b end
  return a .. sep .. b
end
local function now() return r.time_precise and r.time_precise() or os.clock() end
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

-- Legge davvero inizio e fine del file: un segnaposto cloud non scaricato, una cartella o un
-- file senza permessi non superano la prova. Ritorna ok, dimensione, motivo.
local function probe_file(path)
  local f, err = io.open(path, "rb")
  if not f then return false, nil, tostring(err or "apertura impossibile") end
  local size = f:seek("end")
  if not size then f:close(); return false, nil, "dimensione non leggibile" end
  if size == 0 then f:close(); return false, 0, "file vuoto" end
  f:seek("set", 0)
  local head, herr = f:read(4096)
  f:seek("set", math.max(0, size - 4096))
  local tail, terr = f:read(4096)
  f:close()
  if not head or not tail then return false, size, tostring(herr or terr or "lettura impossibile") end
  return true, size
end

---------------------------------------------------------------------------
-- Chunk REAPER: percorso FILE dentro il blocco SOURCE di ogni take
---------------------------------------------------------------------------
local function split_lines(text)
  local lines, pos = {}, 1
  while true do
    local nl = text:find("\n", pos, true)
    if not nl then lines[#lines + 1] = text:sub(pos); break end
    lines[#lines + 1] = text:sub(pos, nl - 1)
    pos = nl + 1
  end
  return lines
end

local function parse_file_line(line)
  local indent, rest = line:match("^(%s*)FILE%s+(.*)$")
  if not indent then return nil end
  local q = rest:sub(1, 1)
  if q == '"' or q == "'" or q == "`" then
    local close = rest:find(q, 2, true)
    if not close then return nil end
    return indent, rest:sub(2, close - 1), rest:sub(close + 1)
  end
  local token, tail = rest:match("^(%S+)(.*)$")
  return indent, token, tail
end

local function format_file_line(indent, path, tail)
  local q
  for _, c in ipairs({ '"', "'", "`" }) do
    if not path:find(c, 1, true) then q = c; break end
  end
  if not q then return nil end
  return indent .. "FILE " .. q .. path .. q .. (tail or "")
end

-- Ritorna { lines=..., sources = { {first,last,files={ {line,path,indent,tail} },section={...}} } }
-- Considera solo i blocchi SOURCE figli diretti dell'ITEM: uno per take, nell'ordine dei take.
local function parse_item_chunk(chunk)
  local lines = split_lines(chunk)
  local info = { lines = lines, sources = {} }
  local depth, current = 0, nil
  for i, line in ipairs(lines) do
    if line:match("^%s*<") then
      depth = depth + 1
      if depth == 2 and line:match("^%s*<SOURCE") then
        current = { first = i, files = {}, section = {}, head = line }
        info.sources[#info.sources + 1] = current
      end
    elseif line:match("^%s*>%s*$") then
      if depth == 2 and current then current.last = i; current = nil end
      depth = depth - 1
    elseif current then
      local indent, path, tail = parse_file_line(line)
      if indent then
        current.files[#current.files + 1] = { line = i, path = path, indent = indent, tail = tail }
      elseif depth == 2 then
        local key = line:match("^%s*(%u+)%s")
        if key == "LENGTH" or key == "STARTPOS" or key == "MODE" or key == "OVERLAP" then
          current.section[#current.section + 1] = (line:gsub("^%s+", ""))
        end
      end
    end
  end
  info.balanced = (depth == 0)
  return info
end
C.parse_item_chunk = parse_item_chunk

local function section_text(src)
  if not src.head:match("SECTION") then return nil end
  return table.concat(src.section, "; ")
end

---------------------------------------------------------------------------
-- Interazione con l'utente (sostituibile dai collaudi)
---------------------------------------------------------------------------
local function ask_four(title, text, labels)
  local a = r.ShowMessageBox(text .. "\n\nSì = " .. labels[1] .. "\nNo = " .. labels[2] ..
    "\nAnnulla = altre scelte (" .. labels[3] .. " / " .. labels[4] .. ")", title, 3)
  if a == 6 then return 1 elseif a == 7 then return 2 end
  local b = r.ShowMessageBox(text .. "\n\nSì = " .. labels[3] .. "\nNo = " .. labels[4], title, 4)
  return b == 6 and 3 or 4
end

local function default_hooks()
  local H = {}
  function H.confirm(title, text) return r.ShowMessageBox(text, title, 1) == 1 end
  function H.message(title, text) r.ShowMessageBox(text, title, 0) end
  function H.ask_unreachable(rec, text)
    local n = ask_four(TITLE .. " - sorgente non raggiungibile", text,
      { "Riprova (dopo aver reso disponibile il file)", "Seleziona il file corretto…", "Salta questa sorgente", "Annulla l'intera operazione" })
    return ({ "retry", "pick", "skip", "cancel" })[n]
  end
  function H.ask_collision(rec, text)
    local n = ask_four(TITLE .. " - nome già presente in Media", text,
      { "Rinomina la nuova copia", "Sovrascrivi la copia in Media", "Salta questa sorgente", "Annulla l'intera operazione" })
    return ({ "rename", "overwrite", "skip", "cancel" })[n]
  end
  function H.pick_file(rec)
    if not r.GetUserFileNameForRead then return nil end
    local ok, file = r.GetUserFileNameForRead(rec.source, TITLE .. ": scegli " .. basename(rec.source), "")
    if ok and file and file ~= "" then return file end
    return nil
  end
  function H.sleep(seconds)
    local t = now()
    while now() - t < seconds do end
  end
  function H.defer(fn) r.defer(fn) end
  function H.log(line) r.ShowConsoleMsg(line .. "\n") end
  function H.save_project() r.Main_SaveProject(0, false) end
  function H.confirm_cleanup(text) return r.ShowMessageBox(text, TITLE .. " - pulizia di Media", 1) == 1 end
  return H
end

---------------------------------------------------------------------------
-- Scansione del progetto (nessuna modifica)
---------------------------------------------------------------------------
local SPECIAL_TYPES = { CLICK = true, LTC = true, EMPTY = true, VIDEOEFFECT = true, TIMECODE = true }

local function guid_of_item(item) local _, g = r.GetSetMediaItemInfo_String(item, "GUID", "", false); return g end
local function guid_of_take(take) local _, g = r.GetSetMediaItemTakeInfo_String(take, "GUID", "", false); return g end

local function root_source(src)
  local cur, depth = src, 0
  while r.GetMediaSourceParent and depth < 8 do
    local parent = r.GetMediaSourceParent(cur)
    if not parent then break end
    cur, depth = parent, depth + 1
  end
  return cur, depth
end

local function time_label(sec)
  local m = math.floor(sec / 60)
  return string.format("%d:%06.3f", m, sec - m * 60)
end

local function usage_label(u)
  local s = string.format("item %d «%s» a %s, take %d%s", u.item_index, u.item_name ~= "" and u.item_name or "senza nome",
    time_label(u.item_pos), u.take_index, u.active and "" or " (inattivo)")
  if u.derived then s = s .. " [" .. (u.section or "sorgente derivata") .. "]" end
  return s
end

local function describe_usages(rec)
  local out = {}
  for i, u in ipairs(rec.usages) do
    if i > MAX_USAGE_LINES then out[#out + 1] = "… e altri " .. (#rec.usages - MAX_USAGE_LINES); break end
    if u.type == "take" then out[#out + 1] = usage_label(u)
    elseif u.type == "registry" then out[#out + 1] = "registro SRT ZP (" .. (u.entry.lang ~= "" and u.entry.lang or "senza lingua") .. ")"
    elseif u.type == "item_srt" then out[#out + 1] = "item testo con SRT collegato (" .. u.item_name .. ")"
    elseif u.type == "sidecar" then out[#out + 1] = "SRT/VTT accanto a " .. basename(u.media.source) end
  end
  return table.concat(out, "\n  ")
end

local function scan_project(ctx, SRT)
  local M = { recs = {}, by_key = {}, srt_recs = {}, srt_by_key = {}, manual = {}, inline_midi = 0, no_file = 0,
    take_count = 0, item_count = 0, section_takes = 0, blocked = {}, notes = {} }

  local function add_rec(list, by_key, kind, path, usage)
    local key = norm(path)
    local rec = by_key[key]
    if not rec then
      rec = { kind = kind, source = path, key = key, usages = {} }
      by_key[key] = rec
      list[#list + 1] = rec
    end
    rec.usages[#rec.usages + 1] = usage
    return rec
  end

  local n_items = r.CountMediaItems(0)
  M.item_count = n_items
  for i = 0, n_items - 1 do
    local item = r.GetMediaItem(0, i)
    local item_guid = guid_of_item(item)
    local _, item_name_ = r.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local active_take = r.GetActiveTake(item)
    local n_takes = r.CountTakes(item)
    local chunk_info, chunk_text
    for t = 0, n_takes - 1 do
      local take = r.GetTake(item, t)
      if take then
        M.take_count = M.take_count + 1
        local src = r.GetMediaItemTake_Source(take)
        if src then
          local top_type = r.GetMediaSourceType(src, "") or ""
          local root, depth = root_source(src)
          local root_type = r.GetMediaSourceType(root, "") or ""
          local path = r.GetMediaSourceFileName(root, "") or ""
          local derived = depth > 0 or top_type == "SECTION"
          local usage = { type = "take", item = item_guid, item_index = i + 1, item_name = item_name_ or "", item_pos = item_pos,
            take = guid_of_take(take), take_index = t + 1, active = (take == active_take), derived = derived,
            take_name = r.GetTakeName and r.GetTakeName(take) or "" }
          if derived then M.section_takes = M.section_takes + 1 end
          if path == "" then
            if root_type == "MIDI" then M.inline_midi = M.inline_midi + 1 else M.no_file = M.no_file + 1 end
          elseif root_type == "RPP_PROJECT" then
            local key = norm(path)
            if not M.manual[key] then
              M.manual[key] = { path = path, why = "subproject: copia solo il file RPP; le sue dipendenze vanno raccolte aprendolo", usages = {} }
              M.manual[#M.manual + 1] = M.manual[key]
            end
            table.insert(M.manual[key].usages, usage_label(usage))
          elseif SPECIAL_TYPES[root_type] then
            M.no_file = M.no_file + 1
          else
            path = ctx.resolve_path(path)
            usage.mode = (derived or root_type == "MIDI") and "chunk" or "api"
            usage.root_type = root_type
            if usage.mode == "chunk" then
              if not chunk_info then
                local ok, text = r.GetItemStateChunk(item, "", false)
                chunk_text = ok and text or nil
                chunk_info = chunk_text and parse_item_chunk(chunk_text) or { sources = {}, balanced = false }
              end
              local s = chunk_info.sources[t + 1]
              if derived and s then usage.section = section_text(s) or "sorgente derivata" end
              if not chunk_info.balanced or #chunk_info.sources ~= n_takes or not s then
                usage.blocked = "struttura dell'item non verificabile con certezza"
              elseif #s.files ~= 1 then
                usage.blocked = "la sorgente contiene " .. #s.files .. " riferimenti FILE: non ricostruibile con certezza"
              elseif norm(ctx.resolve_path(s.files[1].path)) ~= norm(path) then
                usage.blocked = "il file nel chunk non coincide con quello riportato da REAPER"
              elseif not format_file_line("", path, "") then
                usage.blocked = "percorso non scrivibile nel chunk"
              end
            end
            add_rec(M.recs, M.by_key, "media", path, usage)
          end
        end
      end
    end

    -- SRT collegato direttamente all'item di testo
    local _, srt_path = r.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_PATH", "", false)
    if srt_path and srt_path ~= "" and not srt_path:match("^region:") then
      add_rec(M.srt_recs, M.srt_by_key, "srt", ctx.resolve_path(srt_path),
        { type = "item_srt", item = item_guid, item_name = item_name_ or "" })
    end
  end

  if SRT then
    for _, entry in ipairs(SRT.entries()) do
      if entry.path and entry.path ~= "" then
        add_rec(M.srt_recs, M.srt_by_key, "srt", ctx.resolve_path(entry.path), { type = "registry", entry = entry })
      end
    end
  end
  return M
end
C.scan_project = scan_project

-- SRT/VTT accanto ai media fuori da Media: Nome.srt, Nome.vtt, Nome.<lingua>.srt/.vtt
local function find_sidecars(media_path)
  local dir = slash(media_path):match("^(.*)/[^/]+$")
  if not dir then return {} end
  local stem = split_ext(basename(media_path))
  local found, seen = {}, {}
  local function add(name)
    local p = dir .. "/" .. name
    local k = lkey(p)
    if not seen[k] and exists(p) then seen[k] = true; found[#found + 1] = p end
  end
  for _, e in ipairs({ ".srt", ".vtt", ".SRT", ".VTT" }) do add(stem .. e) end
  if r.EnumerateFiles then
    local esc = stem:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    for i = 0, 4000 do
      local name = r.EnumerateFiles(dir, i)
      if not name then break end
      if name:match("^" .. esc .. "%.%a%a%a?%.[SsVv][RrTt][TtTt]$") and name:lower():match("%.(%a+)$") ~= "tmp" then add(name) end
    end
  end
  return found
end
C.find_sidecars = find_sidecars

---------------------------------------------------------------------------
-- Esecuzione
---------------------------------------------------------------------------
function C.run(opts)
  opts = opts or {}
  local H = default_hooks()
  for k, v in pairs(opts.hooks or {}) do H[k] = v end
  local on_done = opts.on_done or function() end

  local project_handle, rpp = r.EnumProjects(-1, "")
  if not rpp or rpp == "" then
    H.message(TITLE, "Prima salva il progetto: ZP Consolidate deve conoscere la cartella Media.")
    return on_done({ status = "no_project" })
  end
  local project_dir = rpp:match("^(.*)[/\\][^/\\]+$")
  if not project_dir then
    H.message(TITLE, "Non riesco a determinare la cartella del progetto.")
    return on_done({ status = "no_project" })
  end
  local media_dir = join(project_dir, "Media")
  local media_prefix = lkey(media_dir) .. "/"
  local function in_media(path) return lkey(path):sub(1, #media_prefix) == media_prefix end
  local ctx = {}
  function ctx.resolve_path(path)
    path = tostring(path or "")
    if path:match("^[/\\]") or path:match("^%a:[/\\]") then return path end
    return join(project_dir, path)
  end

  local SRT
  do
    local helper = opts.srt_module_path or ((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".") .. sep .. "ZP_SRT_Progetto.lua")
    local ok, module = pcall(dofile, helper)
    if ok and type(module) == "table" then SRT = module end
  end

  local S = {   -- esito
    copied = {}, reused = {}, in_media = {}, retried = {}, picked = {}, skipped = {}, unreachable = {},
    failed = {}, manual = {}, blocked = {}, warnings = {}, relinked_takes = 0, relinked_sections = 0, srt_registered = 0,
    srt_items = 0, renamed = {},
  }
  local result = { status = "running", summary = S, project_handle = project_handle, rpp = rpp }
  local temps = {}   -- file .zp-part da ripulire in caso di interruzione

  local function finish(status, extra)
    for path in pairs(temps) do os.remove(path) end
    result.status = status
    for k, v in pairs(extra or {}) do result[k] = v end
    on_done(result)
  end

  local reserved = {}
  local function unique_path(path)
    local stem, ext = split_ext(path)
    for n = 2, 10000 do
      local candidate = stem .. " (" .. n .. ")" .. ext
      if not exists(candidate) and not reserved[lkey(candidate)] then return candidate end
    end
  end

  local function main()
    local model = scan_project(ctx, SRT)
    result.model = model

    -- Sidecar: aggiunti dopo la scansione, solo per i media fuori da Media
    for _, rec in ipairs(model.recs) do
      if not in_media(rec.source) then
        for _, p in ipairs(find_sidecars(rec.source)) do
          local key = norm(p)
          local srt = model.srt_by_key[key]
          if not srt then
            srt = { kind = "srt", source = p, key = key, usages = {} }
            model.srt_by_key[key] = srt
            model.srt_recs[#model.srt_recs + 1] = srt
          end
          srt.usages[#srt.usages + 1] = { type = "sidecar", media = rec }
        end
      end
    end

    -- I riferimenti bloccati non vengono toccati
    for _, rec in ipairs(model.recs) do
      rec.relinkable = 0
      for _, u in ipairs(rec.usages) do
        if u.blocked then
          S.blocked[#S.blocked + 1] = basename(rec.source) .. " (" .. usage_label(u) .. "): " .. u.blocked
        else
          rec.relinkable = rec.relinkable + 1
        end
      end
    end

    -- Solo scansione (pulsante «Pulisci Media»): nessun accesso ai file, nessuna modifica.
    if opts.scan_only then
      for _, rec in ipairs(model.recs) do rec.cur = rec.source end
      for _, rec in ipairs(model.srt_recs) do rec.cur = rec.source end
      return finish("scanned")
    end

    -- Accesso ai file
    local all = {}
    for _, rec in ipairs(model.recs) do all[#all + 1] = rec end
    for _, rec in ipairs(model.srt_recs) do all[#all + 1] = rec end
    for _, rec in ipairs(all) do
      rec.cur = rec.source
      rec.ok, rec.size, rec.why = probe_file(rec.cur)
      rec.where = in_media(rec.cur) and "media" or "esterno"
    end

    -- Quadro iniziale
    local n_media_ext, n_media_in, n_unreach, n_srt_ext, n_srt_in, n_srt_unreach = 0, 0, 0, 0, 0, 0
    for _, rec in ipairs(model.recs) do
      if rec.relinkable > 0 then
        if not rec.ok then n_unreach = n_unreach + 1
        elseif rec.where == "media" then n_media_in = n_media_in + 1 else n_media_ext = n_media_ext + 1 end
      end
    end
    for _, rec in ipairs(model.srt_recs) do
      if not rec.ok then n_srt_unreach = n_srt_unreach + 1
      elseif rec.where == "media" then n_srt_in = n_srt_in + 1 else n_srt_ext = n_srt_ext + 1 end
    end
    local lines = {
      "Take esaminati: " .. model.take_count .. " in " .. model.item_count .. " item (compresi i take inattivi).",
      "File distinti referenziati dai take: " .. #model.recs .. "  (il numero dei take non è il numero dei file).",
      "  · fuori da Media, da copiare: " .. n_media_ext,
      "  · già in Media: " .. n_media_in,
      "  · non raggiungibili ora: " .. n_unreach .. "  (non dati per mancanti: potrai riprovare o scegliere il file)",
      "SRT/VTT distinti (registro, item, accanto ai media): " .. #model.srt_recs .. "  ·  da copiare " .. n_srt_ext ..
        "  ·  già in Media " .. n_srt_in .. "  ·  non raggiungibili " .. n_srt_unreach,
    }
    if model.section_takes > 0 then
      lines[#lines + 1] = "Take SECTION/reverse/derivati: " .. model.section_takes .. "  (contati sul file originale sottostante, non come file a parte)."
    end
    if model.inline_midi > 0 then lines[#lines + 1] = "MIDI incorporati nel progetto: " .. model.inline_midi .. "  (nessun file da raccogliere)." end
    if #model.manual > 0 then lines[#lines + 1] = "Subproject e dipendenze non raccoglibili in automatico: " .. #model.manual end
    if #S.blocked > 0 then lines[#lines + 1] = "Riferimenti che non posso ricostruire con certezza e lascio intatti: " .. #S.blocked end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Gli originali non vengono modificati. Continuare?"
    result.preflight = table.concat(lines, "\n")
    local any_work = (n_media_ext + n_srt_ext + n_unreach + n_srt_unreach) > 0 or (n_media_in + n_srt_in) > 0
    if not any_work then
      H.message(TITLE, result.preflight:gsub("\nGli originali non vengono modificati%. Continuare%?", "") ..
        "\n\nNon c'è nulla da raccogliere.")
      return finish("nothing")
    end
    if not H.confirm(TITLE, result.preflight) then return finish("cancelled") end

    -- Sorgenti non raggiungibili: nessuna viene classificata come definitivamente mancante
    local function resolve_unreachable(rec)
      local reason = rec.why or "non leggibile"
      while true do
        local text = "Non riesco a leggere questa sorgente:\n\n" .. rec.cur .. "\n\nMotivo: " .. tostring(reason) ..
          "\n\nUsata da:\n  " .. describe_usages(rec) ..
          "\n\nSe il file è su Dropbox o su un altro servizio cloud, scaricalo prima nel Finder/Explorer (REAPER non può farlo da solo) e poi scegli Riprova."
        local choice = H.ask_unreachable(rec, text)
        if choice == "retry" then
          local ok, why = true, nil
          local p1, s1, e1 = probe_file(rec.cur)
          if not p1 then ok, why = false, e1
          else
            H.sleep(1.0)
            local p2, s2, e2 = probe_file(rec.cur)
            if not p2 then ok, why = false, e2
            elseif s1 ~= s2 then ok, why = false, "la dimensione sta ancora cambiando (download in corso?)" end
          end
          if ok then rec.ok, rec.size, rec.via = true, s1, "retry"; return "ok" end
          reason = why
        elseif choice == "pick" then
          local picked = H.pick_file(rec)
          if picked then
            local p1, s1, e1 = probe_file(picked)
            local ok, why = p1, e1
            if p1 then
              H.sleep(1.0)
              local p2, s2, e2 = probe_file(picked)
              if not p2 then ok, why = false, e2 elseif s1 ~= s2 then ok, why = false, "il file scelto sta cambiando dimensione" end
            end
            if ok then
              rec.cur, rec.ok, rec.size, rec.via = picked, true, s1, "pick"
              rec.where = in_media(picked) and "media" or "esterno"
              return "ok"
            end
            reason = "file scelto non utilizzabile: " .. tostring(why)
          end
        elseif choice == "skip" then
          rec.status = "skipped"
          S.skipped[#S.skipped + 1] = rec.source .. "  (" .. tostring(reason) .. ")"
          return "skip"
        else
          return "cancel"
        end
      end
    end

    for _, rec in ipairs(all) do
      if not rec.ok and (rec.kind == "srt" or rec.relinkable > 0) then
        if resolve_unreachable(rec) == "cancel" then return finish("cancelled") end
      end
    end

    -- Decisioni sui nomi in Media
    local function decide_batch(recs)
      local identity = {}
      for _, rec in ipairs(recs) do
        if rec.ok and not rec.status and (rec.kind == "srt" or rec.relinkable > 0) then
          if rec.where == "media" then
            rec.status, rec.final = "in_media", rec.cur
          else
            local name = rec.target_name or basename(rec.cur)
            local target = join(media_dir, name)
            if reserved[lkey(target)] then
              target = unique_path(target)
              rec.auto_renamed = true
            end
            if not target then
              rec.status = "failed"; S.failed[#S.failed + 1] = basename(rec.cur) .. ": nessun nome libero in Media"
            elseif exists(target) and not rec.auto_renamed then
              local tok, tsize = probe_file(target)
              rec.target = target
              if tok and tsize == rec.size then identity[#identity + 1] = rec
              else rec.collision = { size = tsize, readable = tok } end
            else
              rec.target = target
            end
            if rec.target then reserved[lkey(rec.target)] = true end
          end
        end
      end
      -- confronto byte per byte con la copia già presente: la riuso solo se identica
      for _, rec in ipairs(identity) do
        local fa, fb = io.open(rec.cur, "rb"), io.open(rec.target, "rb")
        local equal = fa ~= nil and fb ~= nil
        local t0 = now()
        while equal do
          local x, y = fa:read(CHUNK), fb:read(CHUNK)
          if x ~= y then equal = false end
          if not x or not y then break end
          if now() - t0 >= BUDGET then coroutine.yield(); t0 = now() end
        end
        if fa then fa:close() end
        if fb then fb:close() end
        if equal then
          rec.status, rec.final, rec.reused = "reused", rec.target, true
        else
          rec.collision = { size = rec.size, readable = true }
        end
      end
      for _, rec in ipairs(recs) do
        if rec.collision and not rec.status then
          local text = "In Media esiste già un file con questo nome, ma non è identico alla sorgente:\n\n" .. basename(rec.target) ..
            "\n  in Media: " .. (rec.collision.size and (rec.collision.size .. " byte") or "non leggibile") ..
            "\n  sorgente: " .. rec.size .. " byte (" .. rec.cur .. ")" ..
            "\n\nUsata da:\n  " .. describe_usages(rec) ..
            "\n\nSovrascrivere cambia ciò che già punta a quel file in Media; rinominare conserva entrambe."
          local choice = H.ask_collision(rec, text)
          if choice == "overwrite" then rec.overwrite = true
          elseif choice == "rename" then
            reserved[lkey(rec.target)] = nil
            local alt = unique_path(rec.target)
            if not alt then rec.status = "failed"; S.failed[#S.failed + 1] = basename(rec.cur) .. ": nessun nome libero in Media"
            else rec.target = alt; reserved[lkey(alt)] = true; rec.renamed = true end
          elseif choice == "skip" then
            rec.status = "skipped"; reserved[lkey(rec.target)] = nil
            S.skipped[#S.skipped + 1] = rec.cur .. "  (scelta: salta per nome già presente in Media)"
          else
            return "cancel"
          end
        end
      end
    end

    local firsts = {}
    for _, rec in ipairs(model.recs) do firsts[#firsts + 1] = rec end
    for _, rec in ipairs(model.srt_recs) do
      local sidecar_only = true
      for _, u in ipairs(rec.usages) do if u.type ~= "sidecar" then sidecar_only = false end end
      rec.sidecar_only = sidecar_only
      if not sidecar_only then firsts[#firsts + 1] = rec end
    end
    if decide_batch(firsts) == "cancel" then return finish("cancelled") end

    -- Sidecar: stesso nome del media copiato, così l'associazione per nome resta valida
    local seconds = {}
    for _, rec in ipairs(model.srt_recs) do
      if rec.sidecar_only then
        local media
        for _, u in ipairs(rec.usages) do media = u.media; break end
        if media and (media.status == "reused" or media.target) and media.status ~= "skipped" and media.status ~= "failed" then
          local old_stem = split_ext(basename(media.source))
          local new_stem = split_ext(basename(media.target))
          local name = basename(rec.cur)
          if name:sub(1, #old_stem) == old_stem then name = new_stem .. name:sub(#old_stem + 1) end
          rec.target_name = name
          seconds[#seconds + 1] = rec
        else
          rec.status = "not_needed"
        end
      end
    end
    if decide_batch(seconds) == "cancel" then return finish("cancelled") end

    -- Copie in file temporanei (niente cambia ancora in Media con il loro nome definitivo)
    local jobs = {}
    for _, rec in ipairs(all) do
      if rec.target and not rec.status then jobs[#jobs + 1] = rec end
    end
    if #jobs > 0 then
      if not r.RecursiveCreateDirectory then
        H.message(TITLE, "Questa versione di REAPER non espone RecursiveCreateDirectory.")
        return finish("error")
      end
      r.RecursiveCreateDirectory(media_dir, 0)
      local probe_path = join(media_dir, ".zp-consolidate-probe")
      local probe = io.open(probe_path, "wb")
      if not probe then
        H.message(TITLE, "Non riesco a scrivere nella cartella Media:\n" .. media_dir)
        return finish("error")
      end
      probe:close(); os.remove(probe_path)
    end

    local function temp_name(path)
      local base = path .. ".zp-part"
      local n = 1
      local candidate = base
      while exists(candidate) or temps[candidate] do
        n = n + 1
        candidate = base .. "." .. n
      end
      return candidate
    end

    for _, rec in ipairs(jobs) do
      local input, err = io.open(rec.cur, "rb")
      if not input then
        rec.status = "failed"; S.failed[#S.failed + 1] = basename(rec.cur) .. ": lettura impossibile (" .. tostring(err) .. ")"
      else
        local temp = temp_name(rec.target)
        local output, werr = io.open(temp, "wb")
        if not output then
          input:close()
          rec.status = "failed"; S.failed[#S.failed + 1] = basename(rec.target) .. ": scrittura impossibile (" .. tostring(werr) .. ")"
        else
          temps[temp] = true
          local bytes, ok, why, t0 = 0, true, nil, now()
          while true do
            local chunk, rerr = input:read(CHUNK)
            if not chunk then
              if rerr then ok, why = false, "lettura interrotta (" .. tostring(rerr) .. ")" end
              break
            end
            local wok, wmsg = output:write(chunk)
            if not wok then ok, why = false, "scrittura fallita (" .. tostring(wmsg) .. ")"; break end
            bytes = bytes + #chunk
            if now() - t0 >= BUDGET then coroutine.yield(); t0 = now() end
          end
          input:close()
          local closed, cerr = output:close()
          if ok and not closed then ok, why = false, "chiusura fallita (" .. tostring(cerr) .. ")" end
          if ok and bytes ~= rec.size then ok, why = false, "copia incompleta (" .. bytes .. " di " .. rec.size .. " byte)" end
          -- verifica byte per byte contro la sorgente
          if ok then
            local fa, fb = io.open(rec.cur, "rb"), io.open(temp, "rb")
            if not fa or not fb then ok, why = false, "verifica impossibile" end
            t0 = now()
            while ok do
              local x, y = fa:read(CHUNK), fb:read(CHUNK)
              if x ~= y then ok, why = false, "la copia non coincide con la sorgente"; break end
              if not x then break end
              if now() - t0 >= BUDGET then coroutine.yield(); t0 = now() end
            end
            if fa then fa:close() end
            if fb then fb:close() end
          end
          if ok then rec.temp = temp
          else
            os.remove(temp); temps[temp] = nil
            rec.status = "failed"; S.failed[#S.failed + 1] = basename(rec.cur) .. ": " .. tostring(why)
          end
        end
      end
      coroutine.yield()
    end

    -- Installazione dei file verificati
    for _, rec in ipairs(jobs) do
      if rec.temp then
        local backup
        local blocked_by_name = exists(rec.target) and not rec.overwrite
        if blocked_by_name then
          os.remove(rec.temp); temps[rec.temp] = nil
          rec.status = "failed"
          S.failed[#S.failed + 1] = basename(rec.target) .. ": il nome è stato occupato durante la copia; nessuna sovrascrittura eseguita"
        else
          local proceed = true
          if exists(rec.target) then
            local n = 1
            repeat
              backup = rec.temp .. ".previous" .. (n > 1 and ("." .. n) or "")
              n = n + 1
            until not exists(backup)
            local moved, merr = os.rename(rec.target, backup)
            if not moved then
              os.remove(rec.temp); temps[rec.temp] = nil
              rec.status = "failed"; proceed = false
              S.failed[#S.failed + 1] = basename(rec.target) .. ": backup della versione precedente fallito (" .. tostring(merr) .. ")"
            else
              temps[backup] = nil
            end
          end
          if proceed then
            local moved, merr = os.rename(rec.temp, rec.target)
            if not moved then
              if backup then os.rename(backup, rec.target) end
              os.remove(rec.temp)
              rec.status = "failed"
              S.failed[#S.failed + 1] = basename(rec.target) .. ": installazione fallita (" .. tostring(merr) .. ")"
            else
              temps[rec.temp] = nil
              rec.status, rec.final = "copied", rec.target
              if backup and not os.remove(backup) then
                S.warnings[#S.warnings + 1] = "versione precedente di " .. basename(rec.target) .. " conservata in " .. backup
              end
            end
          end
        end
      end
    end
    coroutine.yield()

    -- Verifica finale di ogni copia prima di toccare i riferimenti
    for _, rec in ipairs(all) do
      if rec.final then
        local ok, size, why = probe_file(rec.final)
        if not ok or (rec.status ~= "in_media" and size ~= rec.size) then
          rec.final, rec.status = nil, "failed"
          S.failed[#S.failed + 1] = basename(rec.source) .. ": copia non valida dopo la verifica finale (" .. tostring(why or "dimensione diversa") .. ")"
        end
      end
    end

    -- Rapporti per l'elenco finale
    for _, rec in ipairs(all) do
      if rec.final then
        local label = rec.source
        if rec.via == "retry" then S.retried[#S.retried + 1] = label end
        if rec.via == "pick" then S.picked[#S.picked + 1] = rec.source .. "  →  " .. rec.cur end
        if rec.status == "copied" then S.copied[#S.copied + 1] = rec.cur .. "  →  " .. rec.final
        elseif rec.status == "reused" then S.reused[#S.reused + 1] = rec.cur .. "  =  " .. rec.final .. " (identica, verificata)"
        elseif rec.status == "in_media" then S.in_media[#S.in_media + 1] = rec.final end
        if rec.renamed or rec.auto_renamed then S.renamed[#S.renamed + 1] = rec.cur .. "  →  " .. basename(rec.final) end
      elseif rec.status == "failed" or rec.status == nil then
        if rec.ok == false and (rec.kind == "srt" or rec.relinkable > 0) then S.unreachable[#S.unreachable + 1] = rec.source end
      end
    end
    for _, m in ipairs(model.manual) do
      S.manual[#S.manual + 1] = m.path .. ": " .. m.why .. "\n    usato da: " .. table.concat(m.usages, "; ")
    end

    -- Cambiamenti di riferimento da fare
    local media_changes, srt_changes = {}, {}
    for _, rec in ipairs(model.recs) do
      if rec.final and norm(rec.final) ~= norm(rec.source) and rec.relinkable > 0 then media_changes[#media_changes + 1] = rec end
    end
    for _, rec in ipairs(model.srt_recs) do
      if rec.final and norm(rec.final) ~= norm(rec.source) then srt_changes[#srt_changes + 1] = rec end
    end
    if #media_changes == 0 and #srt_changes == 0 then
      result.report = C.build_report(result, S, nil, rpp)
      return finish("done_no_changes")
    end

    local cur_handle, cur_rpp = r.EnumProjects(-1, "")
    if cur_handle ~= project_handle or cur_rpp ~= rpp or r.GetProjectStateChangeCount(0) ~= result.state_at_scan then
      S.warnings[#S.warnings + 1] = "Il progetto è cambiato durante la raccolta: le copie sono in Media ma non ho ricollegato nulla. Rilancia ZP Consolidate sul progetto fermo."
      result.report = C.build_report(result, S, nil, rpp)
      return finish("project_changed")
    end

    -- Salvataggio e copia di sicurezza del RPP, prima di cambiare riferimenti
    H.save_project()
    local stem = split_ext(basename(rpp))
    local stamp = os.date("%Y-%m-%d %H-%M-%S")
    local backup_path = join(project_dir, stem .. " (copia di sicurezza prima di ZP Consolidate " .. stamp .. ").rpp")
    do
      local fin = io.open(rpp, "rb")
      local fout = fin and io.open(backup_path, "wb")
      local ok = fin ~= nil and fout ~= nil
      if ok then
        while true do
          local chunk = fin:read(CHUNK)
          if not chunk then break end
          if not fout:write(chunk) then ok = false; break end
        end
      end
      if fin then fin:close() end
      if fout and not fout:close() then ok = false end
      if ok then
        local fa, fb = io.open(rpp, "rb"), io.open(backup_path, "rb")
        while ok and fa and fb do
          local x, y = fa:read(CHUNK), fb:read(CHUNK)
          if x ~= y then ok = false end
          if not x then break end
        end
        if not fa or not fb then ok = false end
        if fa then fa:close() end
        if fb then fb:close() end
      end
      if not ok then
        os.remove(backup_path)
        S.failed[#S.failed + 1] = "Copia di sicurezza del RPP non riuscita: nessun riferimento è stato cambiato."
        result.report = C.build_report(result, S, nil, rpp)
        return finish("backup_failed")
      end
    end
    result.backup = backup_path
    result.state_after_save = r.GetProjectStateChangeCount(0)

    C.apply_relinks(ctx, H, SRT, model, media_changes, srt_changes, S, result)

    H.save_project()
    result.report = C.build_report(result, S, backup_path, rpp)
    return finish("done")
  end

  -- stato del progetto al momento della scansione
  result.state_at_scan = r.GetProjectStateChangeCount(0)
  local co = coroutine.create(main)
  local function pump()
    local ok, err = coroutine.resume(co)
    if not ok then
      H.message(TITLE, "ZP Consolidate si è interrotto prima di cambiare i riferimenti:\n" .. tostring(err))
      return finish("error", { error = tostring(err) })
    end
    if coroutine.status(co) ~= "dead" then H.defer(pump) end
  end
  pump()
  return result
end

---------------------------------------------------------------------------
-- Cambio dei riferimenti (un solo blocco Undo)
---------------------------------------------------------------------------
local function item_props(item)
  local props = { pos = r.GetMediaItemInfo_Value(item, "D_POSITION"), len = r.GetMediaItemInfo_Value(item, "D_LENGTH"), takes = {} }
  for t = 0, r.CountTakes(item) - 1 do
    local tk = r.GetTake(item, t)
    props.takes[#props.takes + 1] = tk and {
      guid = guid_of_take(tk),
      off = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"),
      rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"),
      pitch = r.GetMediaItemTakeInfo_Value(tk, "D_PITCH"),
    } or { guid = "" }
  end
  return props
end
local function same_props(a, b)
  if math.abs(a.pos - b.pos) > 1e-9 or math.abs(a.len - b.len) > 1e-9 or #a.takes ~= #b.takes then return false end
  for i, x in ipairs(a.takes) do
    local y = b.takes[i]
    if x.guid ~= y.guid or math.abs((x.off or 0) - (y.off or 0)) > 1e-9 or math.abs((x.rate or 0) - (y.rate or 0)) > 1e-9
      or math.abs((x.pitch or 0) - (y.pitch or 0)) > 1e-9 then return false end
  end
  return true
end

function C.apply_relinks(ctx, H, SRT, model, media_changes, srt_changes, S, result)
  -- 1) prepara tutto prima di toccare il progetto
  local by_item, api_pending = {}, {}
  local rec_failed = {}
  for _, rec in ipairs(media_changes) do
    for _, u in ipairs(rec.usages) do
      if u.type == "take" and not u.blocked then
        if u.mode == "chunk" then
          by_item[u.item] = by_item[u.item] or {}
          table.insert(by_item[u.item], { usage = u, rec = rec })
        else
          local src = r.PCM_Source_CreateFromFile(rec.final)
          if src then
            api_pending[#api_pending + 1] = { usage = u, rec = rec, source = src }
          else
            rec_failed[rec] = true
            S.failed[#S.failed + 1] = basename(rec.source) .. ": REAPER non riesce a riaprire la copia; riferimento lasciato com'era"
          end
        end
      end
    end
  end
  for _, rec in ipairs(media_changes) do
    if rec_failed[rec] then
      for i = #api_pending, 1, -1 do
        if api_pending[i].rec == rec then
          if r.PCM_Source_Destroy then r.PCM_Source_Destroy(api_pending[i].source) end
          table.remove(api_pending, i)
        end
      end
    end
  end

  local function item_map()
    local items, takes = {}, {}
    for i = 0, r.CountMediaItems(0) - 1 do
      local it = r.GetMediaItem(0, i)
      items[guid_of_item(it)] = it
      for t = 0, r.CountTakes(it) - 1 do
        local tk = r.GetTake(it, t)
        if tk then takes[guid_of_take(tk)] = { take = tk, item = it, index = t + 1 } end
      end
    end
    return items, takes
  end

  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  local ok, err = pcall(function()
    local items, takes = item_map()

    -- SECTION / reverse / MIDI esterni: si cambia solo il percorso FILE nel chunk, il resto resta identico
    for item_guid, list in pairs(by_item) do
      local item = items[item_guid]
      local okc, chunk = false, nil
      if item then okc, chunk = r.GetItemStateChunk(item, "", false) end
      local info = okc and parse_item_chunk(chunk) or nil
      local before = item and item_props(item)
      local good = info and info.balanced and #info.sources == r.CountTakes(item)
      local new_lines
      if good then
        new_lines = {}
        for i, line in ipairs(info.lines) do new_lines[i] = line end
      end
      if good then
        for _, c in ipairs(list) do
          local s = info.sources[c.usage.take_index]
          if not s or #s.files ~= 1 or norm(ctx.resolve_path(s.files[1].path)) ~= norm(c.rec.source) then good = false; break end
          local line = format_file_line(s.files[1].indent, c.rec.final, s.files[1].tail)
          if not line then good = false; break end
          new_lines[s.files[1].line] = line
        end
      end
      if not good then
        for _, c in ipairs(list) do
          S.blocked[#S.blocked + 1] = basename(c.rec.source) .. " (" .. usage_label(c.usage) .. "): chunk cambiato prima del ricollegamento; riferimento lasciato intatto"
        end
      else
        local set_ok = r.SetItemStateChunk(item, table.concat(new_lines, "\n"), false)
        local verified = set_ok
        local why = set_ok and nil or "SetItemStateChunk ha rifiutato il chunk"
        if set_ok then
          local ok2, chunk2 = r.GetItemStateChunk(item, "", false)
          local info2 = ok2 and parse_item_chunk(chunk2)
          verified = info2 and info2.balanced and #info2.sources == #info.sources and same_props(before, item_props(item))
          if verified then
            for idx, s in ipairs(info.sources) do
              local s2 = info2.sources[idx]
              if section_text(s) ~= section_text(s2) or #s2.files ~= 1 then verified = false; break end
              local expected
              for _, c in ipairs(list) do if c.usage.take_index == idx then expected = c.rec.final end end
              local want = norm(expected or ctx.resolve_path(s.files[1].path))
              if norm(ctx.resolve_path(s2.files[1].path)) ~= want then verified = false; break end
            end
          end
          if not verified then why = "verifica dopo il ricollegamento fallita" end
        end
        if verified then
          for _, c in ipairs(list) do
            S.relinked_takes = S.relinked_takes + 1
            if c.usage.derived then S.relinked_sections = S.relinked_sections + 1 end
            c.rec.relinked = true
          end
        else
          r.SetItemStateChunk(item, chunk, false)
          for _, c in ipairs(list) do
            S.blocked[#S.blocked + 1] = basename(c.rec.source) .. " (" .. usage_label(c.usage) .. "): " .. tostring(why) .. "; ripristinato il riferimento originale"
          end
        end
      end
    end

    -- audio/video semplici: nuova sorgente sullo stesso take (offset e lunghezza del take non cambiano)
    items, takes = item_map()
    for _, p in ipairs(api_pending) do
      local t = takes[p.usage.take]
      if t then
        local old_src = r.GetMediaItemTake_Source(t.take)
        local old_root = old_src and root_source(old_src)
        local old_path = old_root and r.GetMediaSourceFileName(old_root, "") or ""
        if norm(ctx.resolve_path(old_path)) == norm(p.rec.source) then
          r.SetMediaItemTake_Source(t.take, p.source)
          local new_src = r.GetMediaItemTake_Source(t.take)
          local new_path = new_src and r.GetMediaSourceFileName(new_src, "") or ""
          if norm(ctx.resolve_path(new_path)) == norm(p.rec.final) then
            S.relinked_takes = S.relinked_takes + 1
            p.rec.relinked = true
          else
            S.failed[#S.failed + 1] = basename(p.rec.source) .. ": verifica dopo il ricollegamento fallita"
          end
        else
          if r.PCM_Source_Destroy then r.PCM_Source_Destroy(p.source) end
          S.blocked[#S.blocked + 1] = basename(p.rec.source) .. " (" .. usage_label(p.usage) .. "): il take è cambiato; riferimento lasciato intatto"
        end
      else
        if r.PCM_Source_Destroy then r.PCM_Source_Destroy(p.source) end
      end
    end

    -- registro SRT, SRT collegati agli item
    if SRT then
      for _, rec in ipairs(media_changes) do
        if rec.relinked then SRT.remap_source(rec.source, rec.final) end
      end
      local items_now = item_map()
      for _, rec in ipairs(model.srt_recs) do
        if rec.final and norm(rec.final) ~= norm(rec.source) then
          for _, u in ipairs(rec.usages) do
            if u.type == "registry" then
              local key = u.entry.source
              for _, m in ipairs(media_changes) do if m.relinked and norm(m.source) == norm(key) then key = m.final end end
              local rok, rerr = SRT.register(key, rec.final, u.entry.lang, u.entry.kind)
              if rok then S.srt_registered = S.srt_registered + 1
              else S.failed[#S.failed + 1] = basename(rec.final) .. ": registro SRT fallito (" .. tostring(rerr) .. ")" end
            elseif u.type == "item_srt" and items_now[u.item] then
              r.GetSetMediaItemInfo_String(items_now[u.item], "P_EXT:RythmoBand_SRT_PATH", rec.final, true)
              r.GetSetMediaItemInfo_String(items_now[u.item], "P_EXT:RythmoBand_SRT_FILE", basename(rec.final), true)
              S.srt_items = S.srt_items + 1
            end
          end
        end
      end
    end
  end)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  if not ok then S.failed[#S.failed + 1] = "Errore durante il ricollegamento: " .. tostring(err) end
  if S.relinked_takes > 0 or S.srt_registered > 0 or S.srt_items > 0 then
    r.MarkProjectDirty(0)
    r.Undo_EndBlock2(0, "ZP Consolidate: raccogli sorgenti e SRT", -1)
  else
    r.Undo_EndBlock2(0, "ZP Consolidate: nessun riferimento cambiato", -1)
  end
end

---------------------------------------------------------------------------
-- Rapporto finale
---------------------------------------------------------------------------
function C.build_report(result, S, backup_path, rpp)
  local model = result.model
  local out = {}
  local function add(s) out[#out + 1] = s end
  local function list(title, items)
    if #items == 0 then return end
    add(""); add(title .. " (" .. #items .. "):")
    for _, line in ipairs(items) do add("  · " .. line) end
  end
  add("ZP Consolidate - rapporto " .. os.date("%Y-%m-%d %H:%M:%S"))
  add("Progetto: " .. tostring(rpp))
  if backup_path then add("Copia di sicurezza del RPP: " .. backup_path) end
  add("")
  add("Take esaminati: " .. model.take_count .. " in " .. model.item_count .. " item; file distinti: " .. #model.recs ..
    "; SRT/VTT distinti: " .. #model.srt_recs)
  add("Take ricollegati: " .. S.relinked_takes .. " (di cui SECTION/reverse/derivati: " .. S.relinked_sections ..
    "); SRT registrati: " .. S.srt_registered .. "; item SRT aggiornati: " .. S.srt_items)
  list("File copiati in Media", S.copied)
  list("Già in Media o copia identica riutilizzata", (function() local t = {}; for _, v in ipairs(S.in_media) do t[#t + 1] = v end; for _, v in ipairs(S.reused) do t[#t + 1] = v end; return t end)())
  list("Risolti riprovando dopo averli resi disponibili", S.retried)
  list("Risolti scegliendo un altro file", S.picked)
  list("Copie rinominate per evitare collisioni", S.renamed)
  list("Saltati dall'utente", S.skipped)
  list("Non raggiungibili (riferimento lasciato com'era)", S.unreachable)
  list("Riferimenti non ricostruibili con certezza, lasciati intatti", S.blocked)
  list("Dipendenze da gestire a mano", S.manual)
  list("Errori", S.failed)
  list("Avvisi", S.warnings)
  add("")
  add("Non analizzati: file referenziati da plug-in (campioni, IR, preset), font e immagini, file di render.")
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Pulizia facoltativa di Media: sposta (non cancella) i file che il progetto non usa
---------------------------------------------------------------------------
local function human_size(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  return string.format("%.0f KB", n / 1024)
end

-- Solo i file direttamente in Media: le sottocartelle (peaks, ecc.) e i file nascosti non si toccano.
function C.find_unused(model, media_dir)
  local used = {}
  local function mark(p) if p and p ~= "" then used[lkey(p)] = true end end
  for _, list in ipairs({ model.recs, model.srt_recs }) do
    for _, rec in ipairs(list) do mark(rec.source); mark(rec.cur); mark(rec.final) end
  end
  local prefix = lkey(media_dir) .. "/"
  local stems = {}
  for k in pairs(used) do
    if k:sub(1, #prefix) == prefix then stems[(split_ext(k:sub(#prefix + 1)))] = true end
  end
  local out, i = {}, 0
  while r.EnumerateFiles do
    local name = r.EnumerateFiles(media_dir, i)
    if not name then break end
    i = i + 1
    local lower = name:lower()
    local path = join(media_dir, name)
    local skip = name:sub(1, 1) == "." or lower:find(".zp-part", 1, true) or lower:match("%.reapeaks$") or lower:match("%.reapindex$")
    if not skip and not used[lkey(path)] then
      local base = lower:match("^(.-)%.%a%a%a?%.[sv][rt][tt]$") or lower:match("^(.-)%.[sv][rt][tt]$")
      if not (base and stems[base]) then
        local f = io.open(path, "rb")
        local size = f and f:seek("end") or 0
        if f then f:close() end
        out[#out + 1] = { name = name, path = path, size = size }
      end
    end
  end
  return out
end

function C.offer_cleanup(res, H)
  H = H or default_hooks()
  local out = { status = "skipped", moved = {}, failed = {} }
  if not (res.status == "done" or res.status == "done_no_changes" or res.status == "nothing" or res.status == "scanned") or not res.model then return out end
  local S = res.summary
  local cur_handle, cur_rpp = r.EnumProjects(-1, "")
  if cur_handle ~= res.project_handle or cur_rpp ~= res.rpp then return out end
  if #res.model.manual > 0 or #S.failed > 0 or #S.blocked > 0 then
    out.status = "not_safe"
    return out
  end
  local project_dir = cur_rpp:match("^(.*)[/\\][^/\\]+$")
  local media_dir = join(project_dir, "Media")
  local list = C.find_unused(res.model, media_dir)
  if #list == 0 then out.status = "none"; return out end
  local total = 0
  for _, f in ipairs(list) do total = total + f.size end
  local dest = join(project_dir, "Media non usati " .. os.date("%Y-%m-%d %H-%M-%S"))
  local lines = { "In Media ci sono " .. #list .. " file (" .. human_size(total) .. ") che il progetto non usa:" }
  for i, f in ipairs(list) do
    if i > 12 then lines[#lines + 1] = "  … e altri " .. (#list - 12); break end
    lines[#lines + 1] = "  · " .. f.name .. " (" .. human_size(f.size) .. ")"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Se confermi, salvo il progetto e SPOSTO questi file (non li cancello) in una cartella fuori da Media:"
  lines[#lines + 1] = dest
  lines[#lines + 1] = "Potrai cancellarla tu quando vuoi."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Non vengono analizzati i campioni/IR dei plug-in né altri progetti che usino questa cartella Media; con Undo oltre questo punto REAPER potrebbe cercare file spostati."
  lines[#lines + 1] = "Spostare i file?"
  if not H.confirm_cleanup(table.concat(lines, "\n")) then out.status = "declined"; return out end
  H.save_project()
  r.RecursiveCreateDirectory(dest, 0)
  for _, f in ipairs(list) do
    local target = join(dest, f.name)
    if exists(target) or not exists(f.path) then
      out.failed[#out.failed + 1] = f.name .. ": destinazione occupata o file scomparso"
    else
      local ok, err = os.rename(f.path, target)
      if ok and exists(target) and not exists(f.path) then out.moved[#out.moved + 1] = f.name
      else out.failed[#out.failed + 1] = f.name .. ": spostamento fallito (" .. tostring(err) .. ")" end
    end
  end
  out.status, out.dest = "done", dest
  return out
end

---------------------------------------------------------------------------
-- Avvio
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Numera item: nome traccia + numero progressivo, nell'ordine in cui stanno sulla traccia
---------------------------------------------------------------------------
function C.number_items()
  local tracks, renamed = r.CountSelectedTracks(0), 0
  if tracks == 0 then return nil, "Seleziona le tracce con gli item da numerare." end
  r.Undo_BeginBlock2(0)
  for t = 0, tracks - 1 do
    local track = r.GetSelectedTrack(0, t)
    local _, name = r.GetTrackName(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local take = r.GetActiveTake(r.GetTrackMediaItem(track, i))
      if take then
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name .. "#" .. (i + 1), true)
        renamed = renamed + 1
      end
    end
  end
  r.Undo_EndBlock2(0, "ZP Consolidate: numera item", -1)
  r.UpdateArrange()
  return renamed, tracks
end

function C.command_number(say, done)
  local renamed, tracks = C.number_items()
  if not renamed then say("Numera item: " .. tracks)
  else say(("Numera item: %d item rinominati su %d %s (Ctrl+Z annulla)."):format(renamed, tracks, tracks == 1 and "traccia" or "tracce")) end
  done()
end

if rawget(_G, "ZP_CONSOLIDATE_TEST") then
  C.norm, C.probe_file, C.format_file_line = norm, probe_file, format_file_line
  return C
end

---------------------------------------------------------------------------
-- Finestra (stesso stile degli altri strumenti ZP): due comandi e un aiuto
---------------------------------------------------------------------------
local HELP = [[ZP Consolidate ha tre comandi indipendenti. Per i primi due il progetto deve essere già salvato.

1. «Consolida progetto» copia in Media, byte per byte, i file usati dal progetto (audio, MIDI esterni, video, sorgenti SECTION/reverse di tutti i take, anche inattivi) e gli SRT/VTT collegati. Poi ricollega i take alle copie. Gli originali non vengono mossi né cancellati. Prima di cambiare i riferimenti salva il progetto e conserva una copia di sicurezza del RPP; i riferimenti cambiano in un solo blocco Undo.

Se una sorgente non è raggiungibile (per esempio un file Dropbox non ancora scaricato) puoi riprovare dopo averla resa disponibile, scegliere il file corretto, saltarla o annullare tutto. Se in Media c'è già un file con lo stesso nome, scegli se rinominare, sovrascrivere o saltare. Un SECTION/reverse che non si può ricostruire con certezza resta com'è e viene segnalato.

2. «Pulisci Media» non copia niente. Cerca i file direttamente in Media che nessun take e nessun SRT del progetto usa e mostra l'elenco. Se confermi, salva il progetto e SPOSTA quei file (non li cancella) in «Media non usati <data e ora>», una cartella accanto a Media, fuori da Media. Puoi cancellarla tu quando vuoi.
La pulizia lascia stare le sottocartelle (peaks, ecc.) e i file nascosti. Non analizza i campioni o le IR dei plug-in né altri progetti che usino la stessa cartella Media. Non viene proposta se ci sono errori, riferimenti lasciati intatti o dipendenze manuali: prima consolida e risolvi.

3. «Numera item» rinomina gli item delle tracce selezionate con il nome della traccia e un numero progressivo (Voce#1, Voce#2…), nell'ordine in cui stanno sulla traccia. Serve a ritrovare la sequenza dopo un montaggio pesante. Non tocca i file né i testi senza take; Ctrl+Z annulla.

Dopo il salvataggio di Consolida o Pulisci, Undo non riporta più il file salvato: per tornare indietro apri la copia di sicurezza indicata nel rapporto. Il rapporto completo è nella Console di REAPER.]]

local function summarize(res)
  local S = res.summary
  local function count(t) return #t end
  local lines = { "ZP Consolidate terminato.", "",
    "Copiati in Media: " .. count(S.copied),
    "Già in Media / identici riutilizzati: " .. (count(S.in_media) + count(S.reused)),
    "Risolti con Riprova: " .. count(S.retried) .. " · con file scelto: " .. count(S.picked),
    "Take ricollegati: " .. S.relinked_takes .. " (SECTION/reverse: " .. S.relinked_sections .. ")",
    "SRT/VTT registrati: " .. S.srt_registered .. " · item SRT aggiornati: " .. S.srt_items,
    "Saltati: " .. count(S.skipped) .. " · non raggiungibili: " .. count(S.unreachable) ..
      " · da verificare/intatti: " .. count(S.blocked) .. " · dipendenze manuali: " .. count(S.manual) ..
      " · errori: " .. count(S.failed) }
  if res.status == "project_changed" or res.status == "backup_failed" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "NESSUN RIFERIMENTO È STATO CAMBIATO (vedi dettagli)."
  elseif res.backup then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Il progetto aggiornato è stato salvato. Dopo il salvataggio, Undo non riporta più il file salvato: per tornare indietro apri la copia di sicurezza:"
    lines[#lines + 1] = res.backup
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Il rapporto completo è nella Console di REAPER."
  lines[#lines + 1] = "Per togliere da Media i file che non servono più usa «Pulisci Media»."
  return table.concat(lines, "\n")
end

-- Ogni comando riporta una riga di stato alla finestra tramite `say`.
function C.command_consolidate(say, done)
  C.run({
    on_done = function(res)
      if res.status == "cancelled" then
        say("Consolida annullato: non è stato copiato né cambiato nulla.")
        r.ShowMessageBox("Operazione annullata. Non è stato copiato né cambiato nulla.", TITLE, 0)
      elseif res.status == "nothing" then
        say("Niente da raccogliere: il progetto non referenzia file.")
      elseif res.status == "no_project" or res.status == "error" then
        say(res.status == "no_project" and "Progetto non salvato." or "Errore: vedi Console.")
      else
        r.ShowConsoleMsg("\n" .. tostring(res.report) .. "\n")
        local S = res.summary
        if res.status == "project_changed" or res.status == "backup_failed" then
          say("Nessun riferimento cambiato (vedi dettagli).")
        else
          say(("Consolida: copiati %d · già in Media %d · take ricollegati %d · errori %d."):format(
            #S.copied, #S.in_media + #S.reused, S.relinked_takes, #S.failed))
        end
        r.ShowMessageBox(summarize(res), TITLE, 0)
      end
      done()
    end,
  })
end

function C.command_clean(say, done)
  C.run({
    scan_only = true,
    on_done = function(res)
      if res.status == "no_project" or res.status == "error" then
        say(res.status == "no_project" and "Progetto non salvato." or "Errore nella scansione: vedi Console.")
        return done()
      end
      local clean = C.offer_cleanup(res)
      if clean.status == "done" then
        for _, f in ipairs(clean.failed) do r.ShowConsoleMsg("[ZP Consolidate] NON SPOSTATO: " .. f .. "\n") end
        r.ShowConsoleMsg("[ZP Consolidate] Spostati " .. #clean.moved .. " file non usati in " .. clean.dest .. "\n")
        say("Spostati " .. #clean.moved .. " file non usati in " .. clean.dest .. (#clean.failed > 0 and (" · non spostati: " .. #clean.failed) or ""))
        r.ShowMessageBox("Spostati " .. #clean.moved .. " file non usati in:\n" .. clean.dest ..
          (#clean.failed > 0 and ("\n\nNon spostati: " .. #clean.failed .. " (dettagli in Console)") or ""), TITLE, 0)
      elseif clean.status == "none" then
        say("Media non contiene file inutilizzati.")
        r.ShowMessageBox("Media non contiene file che il progetto non usa.", TITLE, 0)
      elseif clean.status == "declined" then
        say("Pulizia annullata: nessun file spostato.")
      elseif clean.status == "not_safe" then
        say("Pulizia non proposta: ci sono riferimenti da verificare. Consolida prima.")
        r.ShowMessageBox("Non propongo la pulizia: ci sono errori, riferimenti lasciati intatti o dipendenze manuali, quindi non posso sapere con certezza quali file in Media siano inutilizzati.\n\nRisolvi prima con «Consolida progetto» e controlla il rapporto.", TITLE, 0)
      else
        say("Pulizia non eseguita.")
      end
      done()
    end,
  })
end

local ok_ui, UI = pcall(dofile, (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".") .. sep .. "ZP_UI.lua")
if not ok_ui or type(UI) ~= "table" then
  r.ShowMessageBox("Impossibile caricare ZP_UI.lua. Verifica l'installazione di ZP Studio Suite.", TITLE, 0)
  return
end

local busy, last_cap = false, 0
local logs = { "Pronto. Scegli un comando." }
local function say(line)
  table.insert(logs, 1, os.date("%H:%M:%S ") .. line)
  while #logs > 8 do table.remove(logs) end
end
local function finished() busy = false end

local function label(text, x, y, color)
  gfx.setfont(1, "Arial", 17)
  UI.set_color(color or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(UI.fit_text(text, gfx.w - x - 24))
end

local function loop()
  local key = gfx.getchar()
  if key < 0 or key == 27 then
    r.SetExtState("ZP_CONSOLIDATE", "window", table.concat({ gfx.dock(-1, 0, 0, 0, 0) }, ","), true)
    gfx.quit()
    return
  end
  local clicked = gfx.mouse_cap & 1 == 1 and last_cap & 1 == 0
  last_cap = gfx.mouse_cap
  local width = math.max(240, gfx.w - 44)

  UI.fill_background()
  UI.draw_header({
    title = TITLE, title_size = 24, credit_size = 15, description_size = 17,
    fallback_icon = function(x, y, s) UI.draw_logo(x, y, s) end,
    description = "Raccogli i file in Media, ripulisci Media, numera gli item",
  })
  if UI.draw_button({ x = gfx.w - 56, y = 16, w = 34, h = 28 }, "?", false, true, clicked, "tab") or key == 63 then
    r.ShowMessageBox(HELP, TITLE .. " · Aiuto", 0)
    last_cap = gfx.mouse_cap
  end

  UI.draw_panel({ x = 22, y = 104, w = width, h = 92 }, "")
  label("1 · CONSOLIDA", 34, 110, UI.colors.muted)
  label("Copia in Media i file usati e ricollega i take.", 34, 132)
  if UI.draw_button({ x = 34, y = 156, w = 230, h = 32, font = 17 }, busy and "In corso…" or "Consolida progetto", false, not busy, clicked, "auto") then
    busy = true
    last_cap = gfx.mouse_cap
    C.command_consolidate(say, finished)
  end

  UI.draw_panel({ x = 22, y = 206, w = width, h = 92 }, "")
  label("2 · PULISCI MEDIA", 34, 212, UI.colors.muted)
  label("Sposta fuori da Media i file che il progetto non usa.", 34, 234)
  if UI.draw_button({ x = 34, y = 258, w = 230, h = 32, font = 17 }, busy and "In corso…" or "Pulisci Media", false, not busy, clicked, "sync") then
    busy = true
    last_cap = gfx.mouse_cap
    C.command_clean(say, finished)
  end

  UI.draw_panel({ x = 22, y = 308, w = width, h = 92 }, "")
  label("3 · NUMERA ITEM", 34, 314, UI.colors.muted)
  label("Rinomina gli item delle tracce selezionate: NomeTraccia#1, #2…", 34, 336)
  if UI.draw_button({ x = 34, y = 360, w = 230, h = 32, font = 17 }, busy and "In corso…" or "Numera item", false, not busy, clicked, "tab") then
    busy = true
    last_cap = gfx.mouse_cap
    C.command_number(say, finished)
  end

  local panel_h = math.max(90, gfx.h - 432)
  local bottom = 410 + panel_h
  UI.draw_panel({ x = 22, y = 410, w = width, h = panel_h }, "")
  label("STATO", 34, 415, UI.colors.muted)
  gfx.setfont(1, "Arial", 17)
  local y = 442
  for _, entry in ipairs(logs) do
    for _, line in ipairs(UI.wrap_text(entry, width - 24)) do
      if y + 21 > bottom then break end
      label(line, 34, y, UI.colors.muted)
      y = y + 21
    end
    if y + 21 > bottom then break end
  end
  gfx.update()
  r.defer(loop)
end

local d, x, y, w, h = (r.GetExtState("ZP_CONSOLIDATE", "window") .. ","):match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
gfx.init(TITLE, tonumber(w) or 650, math.max(tonumber(h) or 0, 582), tonumber(d) or 0, tonumber(x) or 200, tonumber(y) or 150)
loop()
