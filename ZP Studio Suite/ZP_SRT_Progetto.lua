-- @noindex
-- Registro persistente degli SRT/VTT appartenenti al progetto corrente.
-- I record sono conservati in PROJEXTSTATE (quindi nel file RPP), con i file
-- generati o importati sotto Media/. I sorgenti esterni restano invariati.

local M = {}
local SECTION = "ZP_SRT_FILES"
local sep = package.config:sub(1, 1)

local function project_path()
  local _, path = reaper.EnumProjects(-1, "")
  if not path or path == "" then return nil end
  return path
end

local function project_dir()
  local path = project_path()
  return path and path:match("^(.*)[/\\][^/\\]+$") or nil
end

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. sep .. b
end

local function rel_or_abs(path)
  local dir = project_dir()
  if dir and path:sub(1, #dir + 1) == dir .. sep then return path:sub(#dir + 2) end
  return path
end

local function resolve(path)
  if not path or path == "" then return "" end
  if path:match("^region:") then return path end
  if path:match("^[/\\]") or path:match("^%a:[/\\]") then return path end
  local dir = project_dir()
  return dir and join(dir, path) or path
end

local function encode(s)
  return (tostring(s or ""):gsub("[^%w%._%-]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function decode(s)
  return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function read_records()
  local _, count = reaper.GetProjExtState(0, SECTION, "count")
  local out = {}
  for i = 1, tonumber(count) or 0 do
    local _, value = reaper.GetProjExtState(0, SECTION, "item_" .. i)
    local src, path, lang, kind = value:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if src and path then
      out[#out + 1] = { source = resolve(decode(src)), path = resolve(decode(path)), lang = decode(lang), kind = decode(kind) }
    end
  end
  return out
end

local function write_records(records)
  for i, r in ipairs(records) do
    local value = table.concat({ encode(rel_or_abs(r.source)), encode(rel_or_abs(r.path)), encode(r.lang), encode(r.kind) }, "|")
    reaper.SetProjExtState(0, SECTION, "item_" .. i, value)
  end
  reaper.SetProjExtState(0, SECTION, "count", tostring(#records))
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function ensure_media()
  local dir = project_dir()
  if not dir then return nil, "Salva prima il progetto: gli SRT devono appartenere a una cartella Media." end
  local media = join(dir, "Media")
  if not reaper.RecursiveCreateDirectory then return nil, "REAPER non espone RecursiveCreateDirectory." end
  local ok, result = pcall(reaper.RecursiveCreateDirectory, media, 0)
  if not ok then return nil, "Impossibile creare: " .. media .. " (" .. tostring(result) .. ")" end
  return media
end

local function stem(path)
  local name = path:match("[^/\\]+$") or path
  name = name:gsub("%.[^%.]+$", "")
  return (name:gsub('[<>:"/\\|%?%*]', "_"):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function unique_target(path)
  if not file_exists(path) then return path end
  local base = path:gsub("%.[^%.]+$", "")
  local ext = path:match("(%.[^%.]+)$") or ""
  local n = 2
  repeat
    local candidate = base .. " (" .. n .. ")" .. ext
    if not file_exists(candidate) then return candidate end
    n = n + 1
  until n > 10000
  return nil
end

function M.entries()
  return read_records()
end

function M.remap_source(old_path, new_path)
  old_path, new_path = tostring(old_path or ""), tostring(new_path or "")
  if old_path == "" or new_path == "" or old_path == new_path then return false end
  local records, changed = read_records(), false
  for _, r in ipairs(records) do
    if r.source == old_path then r.source = new_path; changed = true end
  end
  if changed then write_records(records) end
  return changed
end

function M.find(source, lang, kind)
  source, lang = tostring(source or ""), tostring(lang or "")
  for _, r in ipairs(read_records()) do
    if r.source == source and r.lang == lang and (not kind or r.kind == kind) and file_exists(r.path) then return r.path end
  end
end

function M.output_path(source, lang, kind, extension)
  source, lang = tostring(source or ""), tostring(lang or "")
  kind = tostring(kind or "srt")
  extension = tostring(extension or "srt"):lower():gsub("^%.", "")
  if source == "" then return nil, "Sorgente SRT non specificata." end
  for _, r in ipairs(read_records()) do
    if r.source == source and r.lang == lang and r.kind == kind then return r.path end
  end
  local media, err = ensure_media()
  if not media then return nil, err end
  local suffix = lang ~= "" and ("." .. lang) or ""
  local name = stem(source) .. suffix .. "." .. extension
  local target = join(media, name)
  local records = read_records()
  local owner
  for _, r in ipairs(records) do if r.path == target then owner = r; break end end
  if (file_exists(target) and not (owner and owner.source == source and owner.lang == lang and owner.kind == kind)) then
    local n = 2
    repeat
      target = join(media, stem(source) .. suffix .. " (" .. n .. ")." .. extension)
      n = n + 1
    until not file_exists(target)
  end
  return target
end

function M.register(source, path, lang, kind)
  source, path = tostring(source or ""), tostring(path or "")
  if source == "" or path == "" then return false, "Sorgente o percorso SRT vuoto." end
  if not file_exists(path) then return false, "SRT non trovato: " .. path end
  local records = read_records()
  lang, kind = tostring(lang or ""), tostring(kind or "srt")
  for _, r in ipairs(records) do
    if r.source == source and r.lang == lang and r.kind == kind then
      r.path, r.kind = path, kind
      write_records(records)
      return true
    end
  end
  records[#records + 1] = { source = source, path = path, lang = lang, kind = kind }
  write_records(records)
  return true
end

function M.copy_to_media(source, srt_path, lang, kind)
  source, srt_path = tostring(source or ""), tostring(srt_path or "")
  if source == "" or srt_path == "" or not file_exists(srt_path) then return nil, "SRT sorgente assente." end
  kind = tostring(kind or "srt")
  local dir = project_dir()
  local media_prefix = dir and (join(dir, "Media") .. sep) or ""
  if media_prefix ~= "" and srt_path:sub(1, #media_prefix) == media_prefix then
    local ok, register_err = M.register(source, srt_path, lang, kind)
    if not ok then return nil, register_err end
    return srt_path
  end
  local extension = (srt_path:match("%.([^%.\\/]+)$") or "srt"):lower()
  local target, err = M.output_path(source, lang, kind, extension)
  if not target then return nil, err end
  if target ~= srt_path and file_exists(target) then
    target = unique_target(target)
    if not target then return nil, "Nessun nome libero per copiare l'SRT in Media." end
  end
  if target ~= srt_path then
    local input = io.open(srt_path, "rb")
    if not input then return nil, "Impossibile leggere: " .. srt_path end
    local output = io.open(target, "wb")
    if not output then input:close(); return nil, "Impossibile scrivere: " .. target end
    while true do
      local block = input:read(1024 * 1024)
      if not block then break end
      output:write(block)
    end
    input:close(); output:close()
  end
  local ok, register_err = M.register(source, target, lang, kind)
  if not ok then return nil, register_err end
  return target
end

return M
