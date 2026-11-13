-- @noindex
-- Provenienza ZP:
--   Proprietà: ZP Remote / logica del recupero WAV senza manifest.
--   Origine: progetto ZP Remote (ZP_Solo_Recorder_WebRemote/reaper), copiato il 2026-11-13; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; incluso nel pacchetto.

-- ZP Remote — recupero WAV senza manifest: logica pura (nessuna chiamata a REAPER, provabile da sola).
-- Uso: WAV BWF/RIFF che arrivano senza consegna.json. Ogni file va su una traccia nuova, al cursore di edit.
-- Non sostituisce l'importatore normale (zp_remote_importer.lua), che resta rigido e verifica gli hash.
local M = {}

-- Stessa regola dell'importatore normale: niente / \ né caratteri di controllo; niente nomi vuoti, "." o "..".
function M.nome_valido(name)
  if type(name) ~= "string" or name == "" or name == "." or name == ".." then return false, "nome vuoto o non valido" end
  if name:find("[/\\]") then return false, "il nome contiene / o \\" end
  if name:find("%c") then return false, "il nome contiene caratteri di controllo" end
  return true
end

local function u16(s, i) local a, b = s:byte(i, i + 1); if not b then return nil end; return a + b * 256 end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); if not d then return nil end; return a + b * 256 + c * 65536 + d * 16777216 end

-- Legge l'intestazione RIFF/WAVE: ritorna info oppure nil, motivo.
-- head = primi byte del file (anche 64 KB); file_size = dimensione reale (serve a RF64 e al controllo dei file troncati).
-- leggi(offset, n) è facoltativa: legge n byte dal file a partire da offset (da 0) e serve a proseguire la ricerca dei blocchi
-- oltre 'head' (es. un blocco JUNK/bext/iXML lungo prima di 'data').
-- Accetta anche RF64/BW64 solo se riconosce 'fmt ' e 'data' (la lunghezza 'data' può essere 0xFFFFFFFF: allora è sconosciuta).
-- Un file troncato (data dichiara più audio di quanto il file ne contiene) è accettato con info.troncato = true.
function M.leggi_intestazione(head, file_size, leggi)
  if type(head) ~= "string" or #head < 12 then return nil, "file troppo corto" end
  local tag = head:sub(1, 4)
  if tag ~= "RIFF" and tag ~= "RF64" and tag ~= "BW64" then return nil, "non è un file RIFF/WAVE" end
  if head:sub(9, 12) ~= "WAVE" then return nil, "non è un file WAVE" end
  local base, pos = 0, 12 -- base: offset (da 0) del primo byte di 'head'; pos: offset (da 0) del prossimo blocco
  local fmt, data_len, data_off
  while true do
    local rel = pos - base + 1 -- posizione (da 1) del blocco dentro 'head'
    if rel + 7 > #head then
      -- il blocco successivo è oltre la finestra letta: ne leggo un'altra solo se il file continua
      if not leggi or (file_size and pos + 8 > file_size) then break end
      local w = leggi(pos, 65536)
      if not w or #w < 8 then break end
      head, base, rel = w, pos, 1
    end
    local id, len = head:sub(rel, rel + 3), u32(head, rel + 4)
    if not len then break end
    if id == "fmt " then
      if rel + 8 + 15 > #head then return nil, "blocco fmt incompleto" end
      fmt = { formato = u16(head, rel + 8), canali = u16(head, rel + 10), sr = u32(head, rel + 12), bit = u16(head, rel + 22) }
    elseif id == "data" then
      data_len, data_off = len, pos + 8 -- data_off: offset (da 0) del primo byte audio
      break
    end
    pos = pos + 8 + len + (len % 2)
  end
  if not fmt then return nil, "manca il blocco fmt" end
  if not data_off then return nil, "manca il blocco data" end
  if not fmt.canali or fmt.canali < 1 or not fmt.sr or fmt.sr < 1 then return nil, "formato audio non valido" end
  local info = { canali = fmt.canali, sr = fmt.sr, bit = fmt.bit, data_len = data_len }
  if fmt.bit and fmt.bit > 0 then
    local frame = fmt.canali * (fmt.bit / 8)
    local presenti = file_size and math.max(0, file_size - data_off) or nil -- byte audio realmente presenti
    local len = data_len
    if len == 0xFFFFFFFF then len = presenti end -- lunghezza sconosciuta (RF64/streaming): vale ciò che c'è
    if len then
      if presenti and presenti < len then
        info.troncato = true
        info.durata_dichiarata_s = len / (frame * fmt.sr)
        len = presenti
      end
      info.durata_s = len / (frame * fmt.sr)
      if len < frame then return nil, "nessun campione audio nel blocco data" end
    end
  end
  return info
end

-- Selezione multipla di js_ReaScriptAPI: una stringa con gli elementi separati da NUL.
-- Windows: cartella\0file1\0file2...  macOS: percorsi completi \0 percorso2 ...  Un solo file: il percorso intero.
function M.percorsi_da_selezione(list)
  local parts = {}
  for piece in tostring(list or ""):gmatch("[^\0]+") do parts[#parts + 1] = piece end
  if #parts <= 1 then return parts end
  for i = 2, #parts do
    if parts[i]:find("[/\\]") then return parts end -- il secondo elemento è un percorso: sono tutti percorsi completi
  end
  local dir = parts[1]:gsub("[/\\]+$", "")
  local paths = {}
  for i = 2, #parts do paths[#paths + 1] = dir .. "/" .. parts[i] end
  return paths
end

-- Nome traccia dal nome del file, senza estensione.
function M.nome_traccia(name)
  local base = tostring(name):gsub("%.[Ww][Aa][Vv]$", "")
  return base ~= "" and base or "WAV recuperato"
end

-- Nome libero nella cartella media: non sovrascrive mai. taken è un insieme {nome_minuscolo=true}.
function M.nome_libero(name, taken)
  local lower = function(s) return s:lower() end
  if not taken[lower(name)] then taken[lower(name)] = true; return name end
  local base, ext = name:match("^(.*)(%.[^.]*)$")
  if not base then base, ext = name, "" end
  local n = 2
  while true do
    local cand = ("%s_%d%s"):format(base, n, ext)
    if not taken[lower(cand)] then taken[lower(cand)] = true; return cand end
    n = n + 1
  end
end

-- Piano dell'import. files = { {path=..., name=..., size=..., head=...}, ... }, cursore_s = posizione del cursore di edit,
-- taken = nomi già presenti nella cartella media di destinazione.
-- Ritorna { voci = {{path,name,media_name,track_name,position_s,durata_s,info}}, saltati = {{name,motivo}} }.
function M.piano(files, cursore_s, taken)
  taken = taken or {}
  local voci, saltati, visti = {}, {}, {}
  for _, f in ipairs(files or {}) do
    local name = f.name
    local ok, why = M.nome_valido(name)
    if not ok then saltati[#saltati + 1] = { name = tostring(name), motivo = why }
    elseif visti[f.path or name] then saltati[#saltati + 1] = { name = name, motivo = "scelto due volte" }
    else
      visti[f.path or name] = true
      local info, e = M.leggi_intestazione(f.head, f.size, f.leggi)
      if info and f.reaper_len ~= nil and f.reaper_len <= 0 then info, e = nil, "REAPER non riesce a leggere l'audio (durata 0)" end
      if not info then saltati[#saltati + 1] = { name = name, motivo = e }
      else
        voci[#voci + 1] = { path = f.path, name = name, media_name = M.nome_libero(name, taken), track_name = M.nome_traccia(name),
          position_s = cursore_s, durata_s = info.durata_s, info = info }
      end
    end
  end
  return { voci = voci, saltati = saltati }
end

function M.messaggio(piano)
  local n, s = #piano.voci, #piano.saltati
  local t = {}
  if n > 0 then
    t[#t + 1] = ("Manca il percorso: ho inserito %d file in nuove tracce, al cursore di edit."):format(n)
    t[#t + 1] = "I file NON sono verificati (manca il manifest): controllali prima di usarli."
    t[#t + 1] = "Sono stati copiati nella cartella Media del progetto; gli originali non sono stati toccati."
    for _, v in ipairs(piano.voci) do
      if v.info and v.info.troncato then
        t[#t + 1] = ("ATTENZIONE: %s è troncato: dichiara %.2f s ma ne contiene %.2f."):format(v.name, v.info.durata_dichiarata_s or 0, v.info.durata_s or 0)
      end
    end
  else
    t[#t + 1] = "Nessun file inserito."
  end
  if s > 0 then
    t[#t + 1] = ("Saltati %d file:"):format(s)
    for _, x in ipairs(piano.saltati) do t[#t + 1] = ("  - %s: %s"):format(x.name, x.motivo) end
  end
  return table.concat(t, "\n")
end

return M
