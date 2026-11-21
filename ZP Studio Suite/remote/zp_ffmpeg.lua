-- @noindex
-- ZP Remote: dove cercare FFmpeg. Unica fonte per il Benvenuto (33) e per Crea pacchetto;
-- zp_remote_esporta.py usa lo stesso ordine (FFMPEG_CANDIDATI) e un test controlla che coincida.
-- Ordine: FFmpeg scelto dall'utente ("Scegli FFmpeg...") -> PATH -> /usr/local/bin -> /opt/homebrew/bin -> /opt/local/bin
-- Con REAPER aperto dal Finder il PATH e' ridotto (/usr/bin:/bin:...): per questo i percorsi standard
-- si controllano sempre, e il lanciatore passa all'esportatore il percorso trovato (--ffmpeg).
local M = {}
M.SEZIONE, M.CHIAVE = "ZP_Remote", "ffmpeg_path"
M.CANDIDATI = { "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/opt/local/bin/ffmpeg" }
M.PAGINA = "https://ffmpeg.org/download.html"

-- pura: exists(percorso) -> bool. Restituisce percorso e provenienza ("scelto", "PATH", "standard") o nil.
function M.resolve(exists, path, preferito)
  if preferito and preferito ~= "" and exists(preferito) then return preferito, "scelto" end
  for dir in tostring(path or ""):gmatch("[^:]+") do
    local p = dir:gsub("/+$", "") .. "/ffmpeg"
    if exists(p) then return p, "PATH" end
  end
  for _, p in ipairs(M.CANDIDATI) do
    if exists(p) then return p, "standard" end
  end
  return nil, nil
end

-- pura: legge l'uscita di "ffmpeg -version" (formato di reaper.ExecProcess: codice, a capo, testo)
function M.parse_version(out)
  if not out then return nil, "nessuna risposta" end
  local code, testo = tostring(out):match("^(%-?%d+)\n(.*)$")
  if tonumber(code) ~= 0 then return nil, ((testo or tostring(out)):gsub("%s+$", "")):sub(1, 160) end
  return testo:match("ffmpeg version (%S+)") or "?", nil
end

-- con REAPER
function M.preferito(r) return r.GetExtState(M.SEZIONE, M.CHIAVE) end
function M.trova(r)
  return M.resolve(function(p) return r.file_exists(p) end, os.getenv("PATH"), M.preferito(r))
end
function M.versione(r, p)
  if not p then return nil, "non trovato" end
  return M.parse_version(r.ExecProcess('"' .. p .. '" -version', 4000))
end
function M.scegli(r)
  local ok, file = r.GetUserFileNameForRead("", "Scegli l'eseguibile di FFmpeg", "")
  if ok and file and file ~= "" then r.SetExtState(M.SEZIONE, M.CHIAVE, file, true); return file end
  return nil
end
return M
