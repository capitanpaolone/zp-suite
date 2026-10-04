-- @noindex

--[[
ZP Studio Suite for REAPER
26_SRT_Tools.lua
Opens offline SRT Tools or submits a WAV transcription to the shared ZP Speech Service.
]]

local function join(a, b)
  local sep = package.config:sub(1, 1)
  if a:sub(-1) == sep then return a .. b end
  return a .. sep .. b
end

-- La cartella dello script, qualunque sia il posto in cui e' installato.
local script_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local tool_path = join(join(script_dir, "tools"), "srt_tools.html")

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function open_srt_tools()
  local f = io.open(tool_path, "r")
  if not f then
    reaper.ShowMessageBox("SRT Tools non trovato:\n\n" .. tool_path, "ZP Studio Suite", 0)
    return
  end
  f:close()

  local osname = reaper.GetOS()
  local quoted = shell_quote(tool_path)
  if osname:match("OSX") or osname:match("macOS") then
    os.execute("open " .. quoted .. " >/dev/null 2>&1 &")
  elseif osname:match("Win") then
    os.execute('start "" ' .. string.format("%q", tool_path))
  else
    os.execute("xdg-open " .. quoted .. " >/dev/null 2>&1 &")
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local value = f:read("*a")
  f:close()
  return value
end

local function show_reascript_console()
  local command = 40056 -- View: Show ReaScript console
  if reaper.GetToggleCommandState(command) == 0 then
    reaper.Main_OnCommand(command, 0)
  end
end

local function start_status_window(title, message)
  gfx.init(title, 520, 116, 0)
  gfx.setfont(1, "Arial", 16)
  local phase = 0
  local closed = false
  local active = true
  local current_status = message
  local current_detail = nil

  local function draw(status, detail)
    gfx.set(0.12, 0.13, 0.15, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)
    gfx.set(0.95, 0.96, 0.98, 1)
    gfx.x, gfx.y = 18, 16
    gfx.drawstr(status)
    gfx.set(0.25, 0.28, 0.32, 1)
    gfx.rect(18, 48, gfx.w - 36, 16, 1)
    if not detail then
      local width = 110
      local x = 18 + (phase % (gfx.w - 36 + width)) - width
      gfx.set(0.25, 0.68, 0.95, 1)
      gfx.rect(x, 48, width, 16, 1)
      phase = phase + 8
    else
      gfx.set(0.25, 0.72, 0.48, 1)
      gfx.rect(18, 48, gfx.w - 36, 16, 1)
    end
    gfx.set(0.78, 0.81, 0.85, 1)
    gfx.x, gfx.y = 18, 78
    gfx.drawstr(detail or message)
    gfx.update()
  end

  local function tick()
    if closed then return end
    if gfx.getchar() < 0 then
      closed = true
      gfx.quit()
      return
    end
    draw(current_status, current_detail)
    if active then reaper.defer(tick) end
  end

  tick()
  return function(status, detail)
    if closed then return end
    if gfx.getchar() < 0 then
      closed = true
      gfx.quit()
      return
    end
    current_status = status
    current_detail = detail
    active = false
    draw(current_status, current_detail)
  end
end

local function start_audio_transcription()
  local osname = reaper.GetOS()
  if not (osname:match("OSX") or osname:match("macOS")) then
    reaper.ShowMessageBox("La trascrizione condivisa ZP Speech è configurata su questo Mac. Gli strumenti SRT offline restano disponibili.", "ZP Speech", 0)
    return
  end
  local home = os.getenv("HOME")
  if not home or home == "" then
    reaper.ShowMessageBox("Non riesco a individuare la cartella utente.", "ZP Speech", 0)
    return
  end
  local cli = join(join(join(join(home, "Library"), "Application Support"), "ZP"),
    "runtimes/speech/bin/zp-speech")
  local check = io.open(cli, "rb")
  if not check then
    reaper.ShowMessageBox(
      "ZP Speech non è installato. Avvia prima install_speech_service.sh da ZP Tools.",
      "ZP Speech", 0)
    return
  end
  check:close()

  local ok, source = reaper.GetUserFileNameForRead("", "Scegli un WAV da trascrivere", "wav")
  if not ok or not source or source == "" then return end
  if not source:lower():match("%.wav$") then
    reaper.ShowMessageBox("ZP Speech richiede un file WAV.", "ZP Speech", 0)
    return
  end

  local output = source:gsub("%.[^%.\\/]+$", "") .. ".srt"
  if read_file(output) then
    local answer = reaper.ShowMessageBox(
      "Esiste già un SRT con questo nome.\n\nVuoi sostituirlo?\n\n" .. output,
      "ZP Speech", 4)
    if answer ~= 6 then return end
  end

  local tmp = os.tmpname()
  os.remove(tmp)
  local status_path = tmp .. ".status"
  local log_path = tmp .. ".log"
  local uid_pipe = io.popen("/usr/bin/id -u 2>/dev/null", "r")
  local uid = uid_pipe and uid_pipe:read("*l") or nil
  if uid_pipe then uid_pipe:close() end
  if uid and uid:match("^%d+$") then
    local plist = join(join(join(home, "Library"), "LaunchAgents"), "com.zp.speech-service.plist")
    os.execute("/bin/launchctl kickstart gui/" .. uid ..
      "/com.zp.speech-service >/dev/null 2>&1 || /bin/launchctl bootstrap 'gui/" .. uid ..
      "' " .. shell_quote(plist) .. " >/dev/null 2>&1")
  end

  local task = shell_quote(cli) .. " request " .. shell_quote(source) ..
    " --format srt --output " .. shell_quote(output) ..
    " > " .. shell_quote(log_path) .. " 2>&1; printf '%s\\n' \"$?\" > " .. shell_quote(status_path)
  os.execute("(" .. task .. ") </dev/null >/dev/null 2>&1 &")
  show_reascript_console()
  reaper.ShowConsoleMsg("\n[ZP Speech] Trascrizione avviata\n  Audio: " .. source ..
    "\n  SRT:   " .. output .. "\n")
  local set_status = start_status_window("ZP Speech", "Trascrizione in corso…")

  local next_check = 0
  local function poll()
    if os.clock() < next_check then
      reaper.defer(poll)
      return
    end
    next_check = os.clock() + 0.5
    local code = read_file(status_path)
    if not code then
      reaper.defer(poll)
      return
    end
    os.remove(status_path)
    local result = tonumber(code:match("%d+"))
    if result == 0 then
      reaper.ShowConsoleMsg("[ZP Speech] Trascrizione completata\n  SRT: " .. output ..
        "\nPuoi copiare il percorso dalla ReaScript console.\n")
      set_status("Trascrizione completata", output)
    else
      local detail = read_file(log_path) or "Nessun dettaglio disponibile."
      if #detail > 1600 then detail = detail:sub(-1600) end
      reaper.ShowConsoleMsg("[ZP Speech] Trascrizione non riuscita\n" .. detail .. "\n")
      set_status("Trascrizione non riuscita", "Dettagli disponibili nella ReaScript console.")
    end
    os.remove(log_path)
  end
  reaper.defer(poll)
end

local choice = reaper.ShowMessageBox(
  "Aprire SRT Tools?\n\nSì: apri gli strumenti SRT offline.\nNo: trascrivi un WAV tramite ZP Speech condiviso.",
  "ZP Studio Suite", 4)
if choice == 6 then
  open_srt_tools()
elseif choice == 7 then
  start_audio_transcription()
end
