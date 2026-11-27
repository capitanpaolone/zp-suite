-- @noindex
-- ZP Studio Suite: copione Excel (.xlsx) con timecode -> battute SRT.
-- Stesse regole di SRT Tools (tools/srt_tools.html, "TXT / Excel -> SRT"):
-- colonne riconosciute dalle intestazioni, personaggio davanti alla battuta,
-- reazioni in coda al testo, fine stimata dal successivo inizio.
local M = {}

M.GAP_MS = 80           -- stacco prima della battuta successiva
M.LAST_MS = 4000        -- durata dell'ultima battuta
M.HEADERS = {
  start    = { 'timecode', 'start', 'in', 'inizio', 'tc in' },
  finish   = { 'end', 'out', 'fine', 'tc out' },
  text     = { 'translation', 'text', 'testo', 'dialogue', 'dialogo' },
  role     = { 'role', 'character', 'personaggio' },
  reaction = { 'reaction sound', 'reaction', 'reazione' },
  name     = { 'file name', 'filename', 'file', 'nome file', 'clip', 'video', 'nome video' },
}

local function trim(s) return (s:match('^%s*(.-)%s*$')) end

local ENTITY = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }
local function decode(s)
  s = s:gsub('&#x(%x+);', function(h) return utf8.char(tonumber(h, 16)) end)
  s = s:gsub('&#(%d+);', function(d) return utf8.char(tonumber(d)) end)
  s = s:gsub('&(%a+);', function(n) return ENTITY[n] end)
  -- Excel scrive i caratteri di controllo come _xHHHH_ (es. _x000D_ = ritorno a capo).
  s = s:gsub('_x(%x%x%x%x)_', function(h)
    local n = tonumber(h, 16)
    if n == 13 then return '' end
    if n < 32 then return ' ' end
  end)
  return s
end

-- Testo di un nodo <si> o <is>: tutti i <t>, senza le letture fonetiche.
local function rich_text(xml)
  xml = xml:gsub('<rPh.-</rPh>', '')
  local out = {}
  for body in xml:gmatch('<t[^>]*>(.-)</t>') do out[#out + 1] = body end
  return decode(table.concat(out))
end

function M.shared_strings(xml)
  local list = {}
  if not xml then return list end
  xml = xml:gsub('<si/>', '<si></si>')
  for body in xml:gmatch('<si>(.-)</si>') do list[#list + 1] = rich_text(body) end
  return list
end

local function column_index(ref)
  local n = 0
  for c in ref:gmatch('%u') do n = n * 26 + (c:byte() - 64) end
  return n
end

-- Righe del foglio: { number = riga di Excel, values = { [colonna] = stringa } }.
function M.sheet_rows(xml, shared)
  local rows = {}
  local data = xml:match('<sheetData>(.-)</sheetData>') or ''
  for row_attrs, body in data:gmatch('<row([^>]*)>(.-)</row>') do
    local row = { number = tonumber(row_attrs:match('%sr="(%d+)"')) or (#rows + 1), values = {} }
    local pos, next_col = 1, 1
    while true do
      local a, b, attrs = body:find('<c([%s/][^>]*)>', pos)
      if not a then break end
      pos = b + 1
      local col = column_index(attrs:match('%sr="(%u+)%d+"') or '')
      if col == 0 then col = next_col end
      next_col = col + 1
      if attrs:sub(-1) ~= '/' then
        local e1, e2 = body:find('</c>', pos, true)
        local inner = body:sub(pos, (e1 or #body + 1) - 1)
        pos = (e2 or #body) + 1
        local kind = attrs:match('%st="(%w+)"')
        local v = inner:match('<v[^>]*>(.-)</v>')
        local value
        if kind == 's' then value = v and shared[tonumber(v) + 1]
        elseif kind == 'inlineStr' then value = rich_text(inner)
        elseif kind == 'e' then value = '#ERRORE'
        elseif v then value = decode(v) end
        if value and value ~= '' then row.values[col] = value end
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

-- Fogli nell'ordine del file: { name, path } (path dentro lo zip).
function M.sheet_list(workbook_xml, rels_xml)
  local target = {}
  for tag in (rels_xml or ''):gmatch('<Relationship%s[^>]*>') do
    local id, t = tag:match('%sId="([^"]*)"'), tag:match('%sTarget="([^"]*)"')
    if id and t then target[id] = t:sub(1, 1) == '/' and t:sub(2) or ('xl/' .. t) end
  end
  local list = {}
  for tag in workbook_xml:gmatch('<sheet%s[^>]*>') do
    local id = tag:match('r:id="([^"]*)"')
    list[#list + 1] = { name = decode(tag:match('%sname="([^"]*)"') or ''), path = target[id] }
  end
  return list
end

local function max_column(row)
  local n = 0
  for col in pairs(row.values) do if col > n then n = col end end
  return n
end

-- Intestazione = prima riga con qualcosa dentro. Restituisce le colonne e la riga.
function M.detect_columns(rows)
  local header
  for _, row in ipairs(rows) do
    for _, v in pairs(row.values) do if trim(v) ~= '' then header = row break end end
    if header then break end
  end
  local map = {}
  if not header then return map end
  for key, names in pairs(M.HEADERS) do
    for col = 1, max_column(header) do
      local label = trim(header.values[col] or ''):lower()
      for _, name in ipairs(names) do
        if label == name then map[key] = col break end
      end
      if map[key] then break end
    end
  end
  return map, header.number
end

-- Millisecondi da "MM:SS,mmm", "HH:MM:SS,mmm", "H:MM:SS" o frazione di giorno di Excel.
function M.time_ms(value)
  local text = trim(tostring(value or ''))
  if text == '' then return nil end
  local clean = text:gsub('%.', ',', 1)
  local m, s, ms = clean:match('^(%d%d):(%d%d),(%d%d%d)$')
  if m then return (tonumber(m) * 60 + tonumber(s)) * 1000 + tonumber(ms) end
  local h
  h, m, s, ms = clean:match('^(%d%d):(%d%d):(%d%d),(%d%d%d)$')
  if h then return (tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)) * 1000 + tonumber(ms) end
  h, m, s = text:match('^(%d%d?):(%d%d):(%d%d)$')
  if h and tonumber(m) < 60 and tonumber(s) < 60 then
    return (tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)) * 1000
  end
  if text:match('^%d*%.%d+$') and tonumber(text) < 1 then return math.floor(tonumber(text) * 86400000 + 0.5) end
  return nil
end

function M.format_time(ms)
  ms = math.max(0, math.floor(ms + 0.5))
  return string.format('%02d:%02d:%02d,%03d', ms // 3600000, ms % 3600000 // 60000, ms % 60000 // 1000, ms % 1000)
end

-- Battute dal foglio. opts: roles (default true), reactions (default true).
function M.cues(rows, map, first_row, opts)
  opts = opts or {}
  if not map.start or not map.text then return nil, 'Nel foglio mancano la colonna dei tempi (Timecode) o quella del testo (Translation).' end
  local cues, invalid = {}, {}
  local function clean(row, col)
    if not col then return '' end
    return (trim(row.values[col] or ''):gsub('%s+', ' '))
  end
  for _, row in ipairs(rows) do
    if row.number >= first_row then
      local text = clean(row, map.text)
      local reaction = opts.reactions ~= false and clean(row, map.reaction) or ''
      if reaction ~= '' then text = text ~= '' and (text .. ' ' .. reaction) or reaction end
      if text ~= '' then
        local start = M.time_ms(row.values[map.start])
        local finish = map.finish and M.time_ms(row.values[map.finish]) or nil
        if not start or (map.finish and (not finish or finish <= start)) then
          invalid[#invalid + 1] = row.number
        else
          local role = opts.roles ~= false and clean(row, map.role) or ''
          cues[#cues + 1] = { start = start, finish = finish, row = row.number,
            text = role ~= '' and (role .. ': ' .. text) or text }
        end
      end
    end
  end
  -- Una riga piena con il tempo sbagliato non si scarta in silenzio.
  if #invalid > 0 then
    local shown = {}
    for i = 1, math.min(20, #invalid) do shown[i] = tostring(invalid[i]) end
    return nil, 'Timecode mancanti o non validi alle righe: ' .. table.concat(shown, ', ') .. (#invalid > 20 and '…' or '') .. '.'
  end
  if #cues == 0 then return nil, 'Nessuna battuta trovata nel foglio.' end
  table.sort(cues, function(a, b) if a.start ~= b.start then return a.start < b.start end return a.row < b.row end)
  for i, cue in ipairs(cues) do
    if not cue.finish then
      local nxt
      for j = i + 1, #cues do if cues[j].start > cue.start then nxt = cues[j] break end end
      cue.finish = nxt and math.max(cue.start + 1, nxt.start - M.GAP_MS) or (cue.start + M.LAST_MS)
    end
  end
  return cues
end

function M.to_srt(cues)
  local out = {}
  for i, cue in ipairs(cues) do
    out[#out + 1] = i .. '\n' .. M.format_time(cue.start) .. ' --> ' .. M.format_time(cue.finish) .. '\n' .. cue.text .. '\n'
  end
  return table.concat(out, '\n')
end

-- Copione per il testo libero del Gobbo: una battuta per riga, senza tempi.
function M.to_text(cues)
  local out = {}
  for i, cue in ipairs(cues) do out[i] = cue.text end
  return table.concat(out, '\n')
end

-- Colonne che possono contenere il testo da importare: prima quelle con un'intestazione nota
-- (Translation, Testo...), poi le altre colonne di frasi (es. una per lingua).
M.NOT_TEXT = { episode = true, episodio = true, gender = true, genere = true, ['voice actor'] = true, actor = true,
  attore = true, doppiatore = true, scene = true, scena = true, loop = true, anello = true, ['#'] = true, n = true, ['n.'] = true, id = true }
function M.text_columns(rows, map, header_row)
  local header
  for _, row in ipairs(rows) do if row.number == header_row then header = row break end end
  if not header then return {} end
  local used = {}
  for _, key in ipairs({ 'start', 'finish', 'role', 'reaction', 'name' }) do if map[key] then used[map[key]] = true end end
  local known, others = {}, {}
  for col = 1, max_column(header) do
    local label = trim(header.values[col] or '')
    local low = label:lower()
    if label ~= '' and not used[col] and not M.NOT_TEXT[low] then
      local recognised = false
      for _, name in ipairs(M.HEADERS.text) do if low == name then recognised = true break end end
      local filled, phrases = 0, 0
      for _, row in ipairs(rows) do
        local v = row.number > header_row and trim(row.values[col] or '') or ''
        if v ~= '' then
          filled = filled + 1
          if v:find('%s') and v:find('[%a\128-\255]') and not M.time_ms(v) then phrases = phrases + 1 end
        end
      end
      local entry = { col = col, label = label }
      if recognised then known[#known + 1] = entry
      elseif filled > 0 and phrases * 2 >= filled then others[#others + 1] = entry end
    end
  end
  for _, entry in ipairs(others) do known[#known + 1] = entry end
  return known
end

local function column_name(col)
  local out = ''
  while col > 0 do out = string.char(65 + (col - 1) % 26) .. out; col = (col - 1) // 26 end
  return out
end

-- Legge l'xlsx e restituisce le battute di un foglio che ha tempi e testo.
-- member(name) restituisce il contenuto di un file dentro lo zip.
-- opts.choose(domanda, voci) -> numero della voce, o nil per annullare: viene chiamata solo quando
-- i fogli adatti sono più di uno, o quando un foglio ha più colonne di testo (es. più lingue).
-- Senza opts.choose prende il primo foglio e la prima colonna. Annullato = nil, nil.
function M.read(member, opts)
  opts = opts or {}
  local workbook = member('xl/workbook.xml')
  if not workbook or workbook == '' then return nil, 'Il file non sembra un Excel .xlsx leggibile.' end
  local sheets = M.sheet_list(workbook, member('xl/_rels/workbook.xml.rels'))
  local shared = M.shared_strings(member('xl/sharedStrings.xml'))
  local found = {}
  for _, sheet in ipairs(sheets) do
    local xml = sheet.path and member(sheet.path)
    if xml and xml ~= '' then
      local rows = M.sheet_rows(xml, shared)
      local map, header_row = M.detect_columns(rows)
      if map.start then
        local columns = M.text_columns(rows, map, header_row)
        if #columns > 0 then
          found[#found + 1] = { name = sheet.name, rows = rows, map = map, header_row = header_row, columns = columns }
        end
      end
    end
  end
  if #found == 0 then return nil, 'Nessun foglio con una colonna dei tempi (Timecode) e una del testo (Translation).' end
  local sheet = found[1]
  if #found > 1 and opts.choose then
    local names = {}
    for i, f in ipairs(found) do names[i] = f.name end
    local pick = opts.choose('Quale foglio importo?', names)
    if not pick then return nil, nil end
    sheet = found[pick]
  end
  local column = sheet.columns[1]
  if #sheet.columns > 1 and opts.choose then
    local names = {}
    for i, c in ipairs(sheet.columns) do names[i] = column_name(c.col) .. ' — ' .. c.label end
    local pick = opts.choose('Quale colonna di testo importo?', names)
    if not pick then return nil, nil end
    column = sheet.columns[pick]
  end
  sheet.map.text = column.col
  local cues, err = M.cues(sheet.rows, sheet.map, sheet.header_row + 1, opts)
  if not cues then return nil, 'Foglio «' .. sheet.name .. '»: ' .. err end
  return cues, sheet.name, column.label
end

-- Copione SENZA tempi, a blocchi: la colonna del nome file/video apre un blocco (di solito e' una cella
-- unita su piu' righe: solo la prima riga ha il nome) e le righe seguenti con il nome vuoto ne fanno parte.
-- Restituisce { { name, text, rows = { numeri di riga } }, ... }, nome del foglio, etichetta della colonna.
-- Il testo di un blocco e' una battuta per riga. opts.choose come in M.read (foglio / colonna di testo).
function M.read_groups(member, opts)
  opts = opts or {}
  local workbook = member('xl/workbook.xml')
  if not workbook or workbook == '' then return nil, 'Il file non sembra un Excel .xlsx leggibile.' end
  local sheets = M.sheet_list(workbook, member('xl/_rels/workbook.xml.rels'))
  local shared = M.shared_strings(member('xl/sharedStrings.xml'))
  local found = {}
  for _, sheet in ipairs(sheets) do
    local xml = sheet.path and member(sheet.path)
    if xml and xml ~= '' then
      local rows = M.sheet_rows(xml, shared)
      local map, header_row = M.detect_columns(rows)
      if map.name and header_row then
        local columns = M.text_columns(rows, { name = map.name }, header_row)
        if #columns > 0 then
          found[#found + 1] = { name = sheet.name, rows = rows, map = map, header_row = header_row, columns = columns }
        end
      end
    end
  end
  if #found == 0 then return nil, 'Nessun foglio con una colonna dei nomi (File name) e una di testo.' end
  local sheet = found[1]
  if #found > 1 and opts.choose then
    local names = {}
    for i, f in ipairs(found) do names[i] = f.name end
    local pick = opts.choose('Quale foglio importo?', names)
    if not pick then return nil, nil end
    sheet = found[pick]
  end
  local column = sheet.columns[1]
  if #sheet.columns > 1 and opts.choose then
    local names = {}
    for i, c in ipairs(sheet.columns) do names[i] = column_name(c.col) .. ' — ' .. c.label end
    local pick = opts.choose('Quale colonna di testo importo?', names)
    if not pick then return nil, nil end
    column = sheet.columns[pick]
  end
  local groups, current = {}, nil
  for _, row in ipairs(sheet.rows) do
    if row.number > sheet.header_row then
      local name = trim(row.values[sheet.map.name] or '')
      if name ~= '' then
        current = { name = name, lines = {}, rows = {} }
        groups[#groups + 1] = current
      end
      local text = trim((row.values[column.col] or ''):gsub('\r\n', '\n'):gsub('\r', '\n'))
      if current and text ~= '' then
        current.lines[#current.lines + 1] = text
        current.rows[#current.rows + 1] = row.number
      end
    end
  end
  local out = {}
  for _, g in ipairs(groups) do
    if #g.lines > 0 then out[#out + 1] = { name = g.name, text = table.concat(g.lines, '\n'), rows = g.rows } end
  end
  if #out == 0 then return nil, 'Nessun testo trovato nella colonna scelta.' end
  return out, sheet.name, column.label
end

-- Confronto fra il nome di un blocco e quello di un video: senza estensione, maiuscole e spazi ai bordi.
function M.match_key(name)
  name = trim(tostring(name or '')):gsub('%.%w%w?%w?%w?$', ''):lower()
  return name
end

-- Menu a comparsa per scegliere foglio o colonna (si apre al puntatore; senza finestra ne usa una provvisoria).
function M.menu(title, labels)
  if not gfx or not gfx.showmenu then return 1 end
  local state = gfx.getchar(65536)
  local temporary = state < 0 or (state & 1) == 0
  if temporary then
    local x, y = 200, 200
    if reaper and reaper.GetMousePosition then x, y = reaper.GetMousePosition() end
    gfx.init('ZP Studio Suite', 0, 0, 0, x, y)
    gfx.x, gfx.y = 0, 0
  else
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  end
  local items = { '#' .. title:gsub('|', '/'), '' }
  for i, label in ipairs(labels) do items[i + 2] = (label:gsub('|', '/'):gsub('^[#!<>]', ' %0')) end
  local choice = gfx.showmenu(table.concat(items, '|'))
  if temporary then gfx.quit() end
  if choice < 2 then return nil end
  return choice - 1
end

-- Testo di una battuta SRT/VTT. La voce del VTT (<v Nome>) diventa "Nome: ",
-- i tag di formato spariscono, il resto fra <> resta (es. <sospira>).
local FORMAT_TAGS = { i = true, b = true, u = true, s = true, c = true, v = true, font = true, lang = true, ruby = true, rt = true }
function M.clean_cue_text(text)
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
  local function voice(name) return name ~= '' and (name .. ': ') or '' end
  text = text:gsub('<[vV]%s+([^>]-)%s*>', voice):gsub('<[vV]%.[^%s>]*%s+([^>]-)%s*>', voice)
  text = text:gsub('<(/?)([%a]*)([^>]*)>', function(slash, name, rest)
    if FORMAT_TAGS[name:lower()] and (rest == '' or rest:match('^[%s%.]')) then return '' end
    if name == '' and slash == '' and rest:match('^%d[%d:%.]*$') then return '' end   -- <00:00:01.000>
  end)
  text = text:gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&nbsp;', ' ')
  return trim(text)
end

local function read_all(path)
  local f = io.open(path, 'rb'); if not f then return nil end
  local s = f:read('a'); f:close(); return s
end

-- Converte un .xlsx in un .srt accanto al file. Restituisce il percorso dell'SRT e il numero di battute.
-- confirm(messaggio) decide se sostituire un SRT diverso che c'e' gia'; senza conferma restituisce nil, nil.
function M.convert_file(xlsx_path, member, confirm, opts)
  local cues, info = M.read(member, opts)
  if not cues then return nil, info end   -- info nil = annullato
  local srt = M.to_srt(cues)
  local out = xlsx_path:gsub('%.[^%.\\/]+$', '') .. '.srt'
  local old = read_all(out)
  if old ~= srt then
    if old and not (confirm and confirm(out)) then return nil, nil end
    local f, err = io.open(out, 'wb'); if not f then return nil, 'Impossibile scrivere ' .. out .. (err and ('\n' .. err) or '') end
    f:write(srt); f:close()
  end
  return out, #cues
end

-- Per le finestre "Scegli SRT/VTT": se il file scelto e' un Excel lo converte e restituisce l'SRT.
-- Restituisce: percorso (invariato se non e' Excel) oppure nil, errore (errore nil = annullato).
function M.resolve_choice(path, api, script_dir)
  local ext = (path:match('%.([^%.\\/]+)$') or ''):lower()
  if ext == 'xls' then
    return nil, 'Il vecchio formato .xls non si legge da qui.\nSalvalo come .xlsx, oppure convertilo con SRT Tools (26).'
  end
  if ext ~= 'xlsx' then return path end
  local testo = dofile(script_dir .. 'ZP_Testo_Copione.lua')
  local osname = api.GetOS()
  local out, n = M.convert_file(path, function(name) return testo.zip_member(path, name, osname) end, function(existing)
    return api.ShowMessageBox('Accanto al file Excel esiste già:\n' .. existing ..
      '\n\nLo sostituisco con la nuova conversione?', 'ZP Studio Suite', 4) == 6
  end, { choose = M.menu })
  if not out then return nil, n and ('Copione Excel non importato.\n\n' .. n) or nil end
  return out
end

return M
