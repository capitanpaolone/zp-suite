-- Test della logica di 37_ZP_Consolidate.lua con un REAPER simulato. Lancio dalla radice del repo.
-- Il file system e' vero (cartella temporanea); le API REAPER sono simulate: Undo/Redo reale, riapertura del RPP
-- e comportamento dei sorgenti offline vanno provati dentro REAPER (vedi docs, collaudo manuale).
local SUITE = "ZP Studio Suite/"
local fails = 0
local function check(n, c, d) print((c and "ok   " or "FAIL ") .. n .. ((c or d == nil) and "" or ("  -- " .. tostring(d)))); if not c then fails = fails + 1 end end

local ROOT = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "") .. "/zp_consolidate_test_" .. os.time() .. "_" .. math.random(1000, 9999)
local function sh(c) os.execute(c) end
local function q(p) return "'" .. p .. "'" end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end
local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end
local function listdir(p)
  local t = {}
  local h = io.popen("ls -A " .. q(p) .. " 2>/dev/null")
  for l in h:lines() do t[#t + 1] = l end
  h:close(); table.sort(t); return t
end
local function blob(seed, n) return string.rep(string.char(65 + seed % 26), n or 3000) .. seed end

---------------------------------------------------------------------------
-- REAPER simulato
---------------------------------------------------------------------------
local P
local C
local counter = 0
local function guid() counter = counter + 1; return string.format("{00000000-0000-0000-0000-%012d}", counter) end
local function root_src(s) while s.parent do s = s.parent end; return s end

local function chunk_of(it)
  local L = { "<ITEM", "POSITION " .. it.pos, "LENGTH " .. it.len, "IGUID " .. it.guid, "NAME \"" .. it.name .. "\"" }
  for i, tk in ipairs(it.takes) do
    if i > 1 then L[#L + 1] = "TAKE" end
    L[#L + 1] = "GUID " .. tk.guid
    local s = tk.src
    if s.type == "SECTION" then
      L[#L + 1] = "<SOURCE SECTION"
      L[#L + 1] = "LENGTH " .. s.section.len; L[#L + 1] = "MODE " .. s.section.mode
      L[#L + 1] = "STARTPOS " .. s.section.start; L[#L + 1] = "OVERLAP 0.01"
      L[#L + 1] = "<SOURCE WAVE"; L[#L + 1] = 'FILE "' .. s.parent.path .. '"'; L[#L + 1] = ">"; L[#L + 1] = ">"
    elseif s.type == "MIDI" and s.path == "" then
      L[#L + 1] = "<SOURCE MIDI"; L[#L + 1] = ">"
    else
      L[#L + 1] = "<SOURCE " .. s.type; L[#L + 1] = 'FILE "' .. s.path .. '"'; L[#L + 1] = ">"
    end
  end
  L[#L + 1] = ">"
  return table.concat(L, "\n") .. "\n"
end

local function install_mock()
  local R = {}
  R.GetOS = function() return "OSX64" end
  R.time_precise = os.clock
  R.EnumProjects = function(i, b) if P.no_path then return "PROJ", "" end; return "PROJ", P.rpp end
  R.CountMediaItems = function() return #P.items end
  R.GetMediaItem = function(_, i) return P.items[i + 1] end
  R.GetSetMediaItemInfo_String = function(it, key, val, set)
    if key == "GUID" then return true, it.guid end
    if key == "P_NAME" then if set then it.name = val end; return true, it.name end
    if set then it.ext[key] = val; P.state = P.state + 1 end
    return true, it.ext[key] or ""
  end
  R.GetMediaItemInfo_Value = function(it, k) return k == "D_POSITION" and it.pos or it.len end
  R.GetActiveTake = function(it) return it.takes[1] end
  R.CountTakes = function(it) return #it.takes end
  R.GetTake = function(it, i) return it.takes[i + 1] end
  R.GetMediaItemTake_Source = function(tk) return tk.src end
  R.GetMediaSourceType = function(s) return s.type end
  R.GetMediaSourceFileName = function(s) if s.type == "SECTION" then return s.parent.path end; return s.path or "" end
  R.GetMediaSourceParent = function(s) return s.parent end
  R.GetSetMediaItemTakeInfo_String = function(tk) return true, tk.guid end
  R.GetTakeName = function(tk) return tk.name or "" end
  R.GetMediaItemTakeInfo_Value = function(tk, k) return ({ D_STARTOFFS = tk.offs or 0, D_PLAYRATE = 1, D_PITCH = 0 })[k] end
  R.GetItemStateChunk = function(it) return true, chunk_of(it) end
  R.SetItemStateChunk = function(it, text)
    if P.refuse_chunk then return false end
    local info = C.parse_item_chunk(text)
    if #info.sources ~= #it.takes then return false end
    for i, s in ipairs(info.sources) do
      local tk = it.takes[i]
      local path = s.files[1].path
      if tk.src.type == "SECTION" then tk.src.parent.path = path else tk.src.path = path end
    end
    P.state = P.state + 1
    return true
  end
  R.PCM_Source_CreateFromFile = function(path) if not exists(path) then return nil end; return { type = "WAVE", path = path } end
  R.SetMediaItemTake_Source = function(tk, s) tk.src = s; P.state = P.state + 1 end
  R.PCM_Source_Destroy = function() end
  R.Undo_BeginBlock2 = function() P.undo_open = true end
  R.Undo_EndBlock2 = function(_, label) P.undo_open = false; P.undo[#P.undo + 1] = label end
  R.PreventUIRefresh = function(n) P.prevent = (P.prevent or 0) + n end
  R.UpdateArrange = function() end
  R.MarkProjectDirty = function() P.dirty = true end
  R.GetProjectStateChangeCount = function() return P.state end
  R.RecursiveCreateDirectory = function(p) sh("mkdir -p " .. q(p)) end
  R.EnumerateFiles = function(dir, i)   -- come REAPER: solo file, non le sottocartelle
    local files = {}
    local h = io.popen("ls -Ap " .. q(dir) .. " 2>/dev/null")
    for l in h:lines() do if l:sub(-1) ~= "/" then files[#files + 1] = l end end
    h:close(); table.sort(files)
    return files[i + 1]
  end
  R.GetProjExtState = function(_, sec, key) return 1, P.pext[sec .. "/" .. key] or "" end
  R.SetProjExtState = function(_, sec, key, val) P.pext[sec .. "/" .. key] = val; P.state = P.state + 1 end
  R.ShowConsoleMsg = function() end
  R.ShowMessageBox = function() return 1 end
  reaper = R
end

local function new_case(name)
  local d = ROOT .. "/" .. name .. "/"
  sh("mkdir -p " .. q(d .. "proj") .. " " .. q(d .. "ext") .. " " .. q(d .. "ext2"))
  P = { items = {}, state = 0, undo = {}, pext = {}, rpp = d .. "proj/test.rpp", d = d, ext = d .. "ext/", ext2 = d .. "ext2/", media = d .. "proj/Media/", saves = 0 }
  write(P.rpp, "<REAPER_PROJECT>\nORIGINAL\n>\n")
  return P
end
local function add_take(it, src, name) it.takes[#it.takes + 1] = { guid = guid(), src = src, name = name } end
local function add_item(label, path, opts)
  opts = opts or {}
  local it = { guid = guid(), name = label, pos = #P.items * 2, len = 1, takes = {}, ext = {} }
  add_take(it, opts.src or { type = opts.type or "WAVE", path = path }, label)
  P.items[#P.items + 1] = it
  return it
end
local function item(label) for _, it in ipairs(P.items) do if it.name == label then return it end end end
local function tpath(label, idx) local tk = item(label).takes[idx or 1]; return root_src(tk.src).path end

local SRTM
local function make_hooks(s)
  s = s or {}
  local H, h = {}, { unreach = {}, coll = {}, msgs = {}, saved = 0 }
  local queue = {}
  H.confirm = function(_, t) h.preflight = t; return not s.refuse end
  H.message = function(_, t) h.msgs[#h.msgs + 1] = t end
  H.ask_unreachable = function(rec, t) h.unreach[#h.unreach + 1] = { rec = rec, text = t }; return s.unreachable and s.unreachable(#h.unreach, rec, h) or "skip" end
  H.ask_collision = function(rec, t) h.coll[#h.coll + 1] = { rec = rec, text = t }; return s.collision and s.collision(#h.coll, rec) or "cancel" end
  H.pick_file = function(rec) return s.pick and s.pick(rec) end
  H.sleep = function() if s.on_sleep then s.on_sleep() end end
  H.log = function() end
  H.save_project = function() h.saved = h.saved + 1; P.saves = P.saves + 1; P.saved_state = P.state end
  H.defer = function(f) queue[#queue + 1] = f end
  h.queue = queue
  return H, h
end
local function run(H, h)
  local res
  C.run({ hooks = H, srt_module_path = SUITE .. "ZP_SRT_Progetto.lua", on_done = function(x) res = x end })
  local guard = 0
  while #h.queue > 0 and guard < 100000 do local f = table.remove(h.queue, 1); f(); guard = guard + 1 end
  return res
end
local function same(a, b) local x = read(a); return x ~= nil and x == read(b) end

install_mock()
_G.ZP_CONSOLIDATE_TEST = true
C = dofile(SUITE .. "37_ZP_Consolidate.lua")
SRTM = dofile(SUITE .. "ZP_SRT_Progetto.lua")

---------------------------------------------------------------------------
print("== sorgente esterna, già in Media, take inattivo, SECTION, SRT, dedup")
do
  local p = new_case("basic")
  sh("mkdir -p " .. q(p.media))
  write(p.ext .. "a.wav", blob(1)); write(p.ext .. "z.wav", blob(2)); write(p.media .. "b.wav", blob(3))
  write(p.ext .. "c.wav", blob(4)); write(p.ext .. "d.wav", blob(5))
  write(p.ext .. "a.srt", "SRT-A"); write(p.ext .. "sub.srt", "SRT-SUB"); write(p.ext .. "d.srt", "SRT-D"); write(p.ext .. "d.it.srt", "SRT-D-IT")
  local ia = add_item("A", p.ext .. "a.wav")
  add_take(ia, { type = "WAVE", path = p.ext .. "z.wav" }, "z")            -- inattivo
  add_item("A2", p.ext .. "a.wav")                                          -- stesso file
  add_item("B", p.media .. "b.wav")
  add_item("C", nil, { src = { type = "SECTION", parent = { type = "WAVE", path = p.ext .. "c.wav" }, section = { start = 0.25, len = 0.5, mode = 3 } } })
  add_item("D", nil, { src = { type = "SECTION", parent = { type = "WAVE", path = p.ext .. "d.wav" }, section = { start = 0.5, len = 0.3, mode = 0 } } })
  add_item("MID", nil, { type = "MIDI", src = { type = "MIDI", path = "" } })
  local itxt = { guid = guid(), name = "TXT", pos = 40, len = 1, takes = {}, ext = { ["P_EXT:RythmoBand_SRT_PATH"] = p.ext .. "sub.srt" } }
  P.items[#P.items + 1] = itxt
  SRTM.register(p.ext .. "a.wav", p.ext .. "a.srt", "", "srt")
  local sec_before = chunk_of(item("C")):gsub('FILE "[^"]*"', "FILE x")
  local sec_before_d = chunk_of(item("D")):gsub('FILE "[^"]*"', "FILE x")
  local H, h = make_hooks()
  local res = run(H, h)
  check("esito done", res and res.status == "done", res and res.status)
  check("preflight: 7 take ma 5 file distinti", h.preflight:find("Take esaminati: 7", 1, true) and h.preflight:find("File distinti referenziati dai take: 5", 1, true), h.preflight)
  check("preflight cita SECTION e MIDI incorporato", h.preflight:find("SECTION/reverse/derivati: 2", 1, true) and h.preflight:find("MIDI incorporati nel progetto: 1", 1, true))
  for _, n in ipairs({ "a.wav", "z.wav", "c.wav", "d.wav", "a.srt", "sub.srt", "d.srt", "d.it.srt" }) do check("copia identica " .. n, same(p.ext .. n, p.media .. n)) end
  check("originali presenti", exists(p.ext .. "a.wav") and exists(p.ext .. "c.wav"))
  check("nessun .zp-part", not table.concat(listdir(p.media), ","):find("zp%-part"))
  check("A e A2 puntano a Media", tpath("A") == p.media .. "a.wav" and tpath("A2") == p.media .. "a.wav")
  check("take inattivo -> Media", tpath("A", 2) == p.media .. "z.wav")
  check("B invariato", tpath("B") == p.media .. "b.wav")
  check("C reverse/SECTION: nuovo FILE, resto identico", tpath("C") == p.media .. "c.wav" and chunk_of(item("C")):gsub('FILE "[^"]*"', "FILE x") == sec_before)
  check("D SECTION: offset/lunghezza conservati", tpath("D") == p.media .. "d.wav" and chunk_of(item("D")):gsub('FILE "[^"]*"', "FILE x") == sec_before_d)
  check("tipo SECTION preservato", item("C").takes[1].src.type == "SECTION" and item("C").takes[1].src.section.mode == 3)
  local e = SRTM.entries()[1]
  check("registro SRT: source e path in Media", e and e.source == p.media .. "a.wav" and e.path == p.media .. "a.srt")
  check("item SRT: P_EXT aggiornato", itxt.ext["P_EXT:RythmoBand_SRT_PATH"] == p.media .. "sub.srt" and itxt.ext["P_EXT:RythmoBand_SRT_FILE"] == "sub.srt")
  check("backup RPP identico all'originale", res.backup and read(res.backup) == "<REAPER_PROJECT>\nORIGINAL\n>\n", res.backup)
  check("progetto salvato prima e dopo", h.saved == 2, h.saved)
  check("un solo blocco Undo", #P.undo == 1 and P.undo[1] == "ZP Consolidate: raccogli sorgenti e SRT" and P.undo_open == false, table.concat(P.undo, "|"))
  check("rapporto con percorso backup", res.report:find(res.backup, 1, true))
  -- seconda esecuzione: niente da fare
  local H2, h2 = make_hooks()
  local res2 = run(H2, h2)
  check("seconda esecuzione senza modifiche e senza dialoghi", res2.status == "done_no_changes" or res2.status == "nothing", res2.status)
end

print("== collisioni: rinomina, sovrascrivi, identico, salta, nome doppio, annulla")
do
  local p = new_case("coll")
  sh("mkdir -p " .. q(p.media))
  write(p.ext .. "e.wav", blob(10)); write(p.media .. "e.wav", blob(11, 4000))
  write(p.ext .. "f.wav", blob(12)); write(p.media .. "f.wav", blob(12))
  write(p.ext .. "g.wav", blob(13)); write(p.media .. "g.wav", blob(14, 4000))
  write(p.ext .. "s.wav", blob(15)); write(p.media .. "s.wav", blob(16, 4000))
  write(p.ext .. "h.wav", blob(17)); write(p.ext2 .. "h.wav", blob(18))
  for _, n in ipairs({ "E", "F", "G", "S" }) do add_item(n, p.ext .. n:lower() .. ".wav") end
  add_item("H1", p.ext .. "h.wav"); add_item("H2", p.ext2 .. "h.wav")
  local keep_e, keep_s = read(p.media .. "e.wav"), read(p.media .. "s.wav")
  local answers = { e = "rename", g = "overwrite", s = "skip" }
  local H, h = make_hooks({ collision = function(_, rec) return answers[rec.source:match("[^/]+$"):sub(1, 1)] end })
  local res = run(H, h)
  check("esito done", res.status == "done", res.status)
  check("dialogo solo per E, G, S (F identico riusato)", #h.coll == 3, #h.coll)
  check("E: esistente intatto, nuova rinominata", read(p.media .. "e.wav") == keep_e and same(p.ext .. "e.wav", p.media .. "e (2).wav") and tpath("E") == p.media .. "e (2).wav")
  check("F: riusata, nessun duplicato", not exists(p.media .. "f (2).wav") and tpath("F") == p.media .. "f.wav")
  check("G: sovrascritta", same(p.ext .. "g.wav", p.media .. "g.wav") and tpath("G") == p.media .. "g.wav")
  check("S: saltata, nulla cambia", read(p.media .. "s.wav") == keep_s and tpath("S") == p.ext .. "s.wav")
  check("H1/H2: nomi uguali da cartelle diverse non si sovrascrivono", same(p.ext .. "h.wav", p.media .. "h.wav") and same(p.ext2 .. "h.wav", p.media .. "h (2).wav") and tpath("H2") == p.media .. "h (2).wav")
  check("nessun residuo temporaneo", not table.concat(listdir(p.media), ","):find("zp%-part") and not table.concat(listdir(p.media), ","):find("previous"))

  local p2 = new_case("coll_cancel")
  sh("mkdir -p " .. q(p2.media))
  write(p2.ext .. "k.wav", blob(20)); write(p2.media .. "k.wav", blob(21, 4000)); write(p2.ext .. "m.wav", blob(22))
  add_item("M", p2.ext .. "m.wav"); add_item("K", p2.ext .. "k.wav")
  local H2, h2 = make_hooks({ collision = function() return "cancel" end })
  local res2 = run(H2, h2)
  check("annulla: cancelled, nessuna copia, RPP e take intatti", res2.status == "cancelled" and not exists(p2.media .. "m.wav") and read(p2.rpp):find("ORIGINAL") and tpath("M") == p2.ext .. "m.wav" and #P.undo == 0 and h2.saved == 0)
  check("annulla: cartella progetto senza backup", #listdir(p2.d .. "proj") == 2, table.concat(listdir(p2.d .. "proj"), ","))
end

print("== sorgente non raggiungibile: riprova, instabile, file alternativo, salta, annulla")
do
  local p = new_case("unreach")
  write(p.ext .. "ok.wav", blob(30)); write(p.ext2 .. "alt.wav", blob(31)); write(p.ext2 .. "q.hidden", blob(32))
  add_item("P", p.ext .. "p.wav"); add_item("Q", p.ext .. "q.wav"); add_item("W", p.ext .. "w.wav")
  add_item("X", p.ext .. "x.wav"); add_item("OK", p.ext .. "ok.wav")
  write(p.ext2 .. "p.hidden", blob(33))
  local calls, growth = {}, false
  local H, h = make_hooks({
    pick = function() return p.ext2 .. "alt.wav" end,
    on_sleep = function() if growth then local f = io.open(p.ext .. "q.wav", "ab"); f:write("0000"); f:close(); growth = false end end,
    unreachable = function(n, rec, hh)
      local name = rec.source:match("([^/]+)%.wav$")
      calls[name] = (calls[name] or 0) + 1
      if name == "p" then
        if calls.p == 2 then sh("cp " .. q(p.ext2 .. "p.hidden") .. " " .. q(p.ext .. "p.wav")) end
        return "retry"
      elseif name == "q" then
        if calls.q == 1 then sh("cp " .. q(p.ext2 .. "q.hidden") .. " " .. q(p.ext .. "q.wav")); growth = true end
        return "retry"
      elseif name == "w" then return "pick"
      end
      return "skip"
    end })
  local res = run(H, h)
  check("esito done", res.status == "done", res.status)
  check("preflight non parla di mancanti definitivi", h.preflight:find("non raggiungibili ora: 4", 1, true) and h.preflight:find("non dati per mancanti", 1, true), h.preflight)
  check("dialogo mostra percorso e take interessato", h.unreach[1].text:find(p.ext .. "p.wav", 1, true) and h.unreach[1].text:find("item 1", 1, true) and h.unreach[1].text:find("Dropbox", 1, true))
  check("P: assente al primo Riprova, disponibile al secondo", calls.p == 2 and same(p.ext .. "p.wav", p.media .. "p.wav") and tpath("P") == p.media .. "p.wav", calls.p)
  check("Q: file che cresce respinto, poi accettato", calls.q == 2 and same(p.ext .. "q.wav", p.media .. "q.wav"), calls.q)
  check("W: file alternativo copiato e collegato", same(p.ext2 .. "alt.wav", p.media .. "alt.wav") and tpath("W") == p.media .. "alt.wav")
  check("X: saltato, riferimento intatto", tpath("X") == p.ext .. "x.wav" and not exists(p.media .. "x.wav"))
  check("rapporto: riprova, scelto, saltato", res.report:find("riprovando", 1, true) and res.report:find("scegliendo", 1, true) and res.report:find("Saltati dall'utente", 1, true))

  local p2 = new_case("unreach_cancel")
  write(p2.ext .. "u.wav", blob(40))
  add_item("U", p2.ext .. "u.wav"); add_item("V", p2.ext .. "v.wav")
  local H2, h2 = make_hooks({ unreachable = function() return "cancel" end })
  local res2 = run(H2, h2)
  check("annulla su non raggiungibile: nessuna modifica", res2.status == "cancelled" and not exists(p2.media .. "u.wav") and #P.undo == 0 and h2.saved == 0 and read(p2.rpp):find("ORIGINAL"))
  local H3, h3 = make_hooks({ refuse = true })
  check("rifiuto al riepilogo: cancelled", run(H3, h3).status == "cancelled")
end

print("== limiti: chunk non ricostruibile, backup, progetto cambiato, progetto senza percorso")
do
  local p = new_case("limits")
  sh("mkdir -p " .. q(p.media))
  write(p.ext .. "r.wav", blob(50))
  add_item("R", nil, { src = { type = "SECTION", parent = { type = "WAVE", path = p.ext .. "r.wav" }, section = { start = 0, len = 1, mode = 0 } } })
  P.refuse_chunk = true
  local H, h = make_hooks()
  local res = run(H, h)
  check("SetItemStateChunk rifiutato: riferimento originale mantenuto e segnalato", tpath("R") == p.ext .. "r.wav" and #res.summary.blocked == 1, tpath("R"))
  local p2 = new_case("limits2")
  write(p2.ext .. "t.wav", blob(51)); add_item("T", p2.ext .. "t.wav")
  local H2, h2 = make_hooks({ on_sleep = nil })
  local orig_confirm = H2.confirm
  H2.confirm = function(a, b) P.state = P.state + 5; return true end   -- il progetto cambia dopo la scansione
  local res2 = run(H2, h2)
  check("progetto cambiato durante la raccolta: nessun ricollegamento", res2.status == "project_changed" and tpath("T") == p2.ext .. "t.wav" and #P.undo == 0)
  local p3 = new_case("limits3"); P.no_path = true
  local H3, h3 = make_hooks()
  check("progetto non salvato: si ferma subito", run(H3, h3).status == "no_project" and #h3.msgs == 1)
end

print("== pulizia facoltativa di Media: sposta i non usati fuori da Media, mai cancella")
do
  local p = new_case("clean")
  sh("mkdir -p " .. q(p.media .. "peaks"))
  write(p.media .. "usato.wav", blob(60)); write(p.media .. "usato.srt", "S"); write(p.media .. "usato.it.srt", "S-IT")
  write(p.media .. "orfano.wav", blob(61)); write(p.media .. "orfano2.wav", blob(62)); write(p.media .. ".nascosto", "x")
  write(p.media .. "peaks/x.reapeaks", "p"); write(p.media .. "usato.wav.reapeaks", "p")
  add_item("U", p.media .. "usato.wav")
  local H, h = make_hooks()
  local res = run(H, h)
  check("niente da raccogliere: nessuna modifica", res.status == "nothing" or res.status == "done_no_changes", res.status)
  local asked
  H.confirm_cleanup = function(text) asked = text; return true end
  local clean = C.offer_cleanup(res, H)
  check("pulizia: elenca solo gli orfani", asked and asked:find("orfano.wav", 1, true) and asked:find("orfano2.wav", 1, true) and not asked:find("usato.srt", 1, true) and not asked:find("nascosto", 1, true), asked)
  check("pulizia: promette spostamento, non cancellazione", asked:find("SPOSTO", 1, true) and asked:find("non li cancello", 1, true))
  check("pulizia: spostati 2, in cartella fuori da Media", clean.status == "done" and #clean.moved == 2 and clean.dest and not clean.dest:find("/Media/", 1, true) and exists(clean.dest .. "/orfano.wav") and exists(clean.dest .. "/orfano2.wav"))
  check("pulizia: usati, sidecar, nascosti e peaks restano", exists(p.media .. "usato.wav") and exists(p.media .. "usato.srt") and exists(p.media .. "usato.it.srt") and exists(p.media .. ".nascosto") and exists(p.media .. "peaks/x.reapeaks") and exists(p.media .. "usato.wav.reapeaks"))
  check("pulizia: orfani tolti da Media", not exists(p.media .. "orfano.wav") and not exists(p.media .. "orfano2.wav"))
  check("pulizia: progetto salvato prima dello spostamento", h.saved >= 1)
  -- rifiuto
  write(p.media .. "altro.wav", blob(63))
  H.confirm_cleanup = function() return false end
  local c2 = C.offer_cleanup(res, H)
  check("pulizia rifiutata: nulla si muove", c2.status == "declined" and exists(p.media .. "altro.wav"))
  -- non sicura: riferimento bloccato
  res.summary.blocked[#res.summary.blocked + 1] = "x"
  H.confirm_cleanup = function() error("non deve chiedere") end
  check("pulizia non offerta se ci sono riferimenti bloccati", C.offer_cleanup(res, H).status == "not_safe")
  res.summary.blocked = {}
  -- file usato solo da un take inattivo non va mai considerato orfano
  local p2 = new_case("clean2")
  sh("mkdir -p " .. q(p2.media))
  write(p2.media .. "a.wav", blob(70)); write(p2.media .. "inattivo.wav", blob(71)); write(p2.media .. "libero.wav", blob(72))
  local ia = add_item("A", p2.media .. "a.wav"); add_take(ia, { type = "WAVE", path = p2.media .. "inattivo.wav" }, "i")
  local H2, h2 = make_hooks()
  local r2 = run(H2, h2)
  local asked2
  H2.confirm_cleanup = function(t) asked2 = t; return false end
  C.offer_cleanup(r2, H2)
  check("take inattivo conta come usato", asked2 and asked2:find("libero.wav", 1, true) and not asked2:find("inattivo.wav", 1, true), asked2)
  -- solo scansione (pulsante «Pulisci Media»): niente copie, niente modifiche, poi la pulizia funziona
  local p3 = new_case("clean3")
  sh("mkdir -p " .. q(p3.media))
  write(p3.media .. "a.wav", blob(80)); write(p3.media .. "libero.wav", blob(81))
  local ext = ROOT .. "/ext3.wav"; write(ext, blob(82))
  add_item("A", p3.media .. "a.wav"); add_item("E", ext)
  local H3, h3 = make_hooks()
  H3.confirm = function() error("la scansione non deve chiedere conferme di raccolta") end
  local r3
  C.run({ hooks = H3, scan_only = true, srt_module_path = SUITE .. "ZP_SRT_Progetto.lua", on_done = function(x) r3 = x end })
  local g3 = 0
  while #h3.queue > 0 and g3 < 100000 do local f = table.remove(h3.queue, 1); f(); g3 = g3 + 1 end
  check("scan_only: stato scanned, nessuna copia in Media", r3 and r3.status == "scanned" and not exists(p3.media .. "ext3.wav"))
  local asked3
  H3.confirm_cleanup = function(t) asked3 = t; return false end
  C.offer_cleanup(r3, H3)
  check("scan_only: la pulizia vede solo il file davvero libero", asked3 and asked3:find("libero.wav", 1, true) and not asked3:find("a.wav (", 1, true), asked3)
end

sh("rm -rf " .. q(ROOT))
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
