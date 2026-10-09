-- @noindex

-- ZP Studio Suite for REAPER
-- 35 ZP Colori: finestrella "clicca e colora" (la stessa logica della toolbar ZP Colori, in
-- ZP_Colori.lua). Si apre e si chiude dalla toolbar ZP come gli altri strumenti, si puo'
-- agganciare: stretta e alta = colori in griglia da 4 per riga, larga e bassa = due file.
-- Modo Item / Traccia / Tutto come nella toolbar (lo stesso modo, salvato in ExtState).

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local UI = dofile(here .. sep .. "ZP_UI.lua")
local C = dofile(here .. sep .. "ZP_Colori.lua")
local T = UI.T or function(s) return s end

local SECTION = "ZP_COLORI"
local S = { status = T("Seleziona, poi clicca un colore."), ok = true, last_cap = 0 }
C.notify = function(msg, ok) S.status, S.ok = msg, ok ~= false end

local TEAL = { 0.10, 0.74, 0.60, 1 }

-- Icone della toolbar ZP Colori (Data/toolbar_icons/200: tre stati da 60x60 affiancati).
local ICON = {}
do
  local dir = reaper.GetResourcePath() .. sep .. "Data" .. sep .. "toolbar_icons" .. sep .. "200" .. sep
  for i, n in ipairs({ "Item", "Traccia", "Tutto", "Togli" }) do
    local id = gfx.loadimg(i, dir .. "ZP_tbC_" .. n .. ".png")
    if id and id >= 0 then ICON[n:lower()] = id end
  end
end

-- Pulsante con l'icona della toolbar e la parola accanto (solo icona se e' stretto).
-- state: 0 normale, 1 mouse sopra, 2 acceso. Restituisce true se cliccato.
local function icon_button(x, y, w, h, key, label, on, clicked)
  local hover = UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
  local id = ICON[key]
  UI.set_color(on and { 0.07, 0.20, 0.17, 1 } or (hover and { 0.16, 0.16, 0.22, 1 } or UI.colors.panel))
  UI.fill_round(x, y, w, h, 5)
  UI.set_color(on and TEAL or (hover and { 0.80, 0.82, 0.88, 1 } or UI.colors.panel_border))
  gfx.roundrect(x, y, w - 1, h - 1, 5, true)
  local s = h - 8
  local tx = x + 8
  if id then
    local frame = on and 2 or (hover and 1 or 0)
    gfx.blit(id, 1, 0, frame * 60, 0, 60, 60, x + 4, y + 4, s, s)
    tx = x + s + 10
  end
  gfx.setfont(1, "Arial", 15, on and "b" or nil)
  local tw = gfx.measurestr(label)
  if not id or tx + tw <= x + w - 4 then
    UI.set_color(on and TEAL or UI.colors.text)
    gfx.x, gfx.y = tx, y + math.floor((h - 15) / 2)
    gfx.drawstr(label)
  end
  return clicked and hover
end

local function text(s, x, y, size, col, bold)
  gfx.setfont(1, "Arial", size, bold and "b" or nil)
  UI.set_color(col or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(s)
end

local function swatch(x, y, w, h, n, clicked)
  local p = C.PALETTE[n]
  local hover = UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
  gfx.set(p[2] / 255, p[3] / 255, p[4] / 255, 1)
  UI.fill_round(x, y, w, h, 5)
  if p[2] + p[3] + p[4] < 200 then -- colori scuri (nero): bordo grigio, se no sparirebbero sul fondo
    gfx.set(0.55, 0.55, 0.60, 1); gfx.roundrect(x, y, w - 1, h - 1, 5, true)
  end
  if hover then
    gfx.set(1, 1, 1, 1)
    gfx.roundrect(x, y, w - 1, h - 1, 5, true); gfx.roundrect(x + 1, y + 1, w - 3, h - 3, 4, true)
    S.hover = T(p[1])
    if clicked then C.color(n) end
  end
end

local function draw()
  UI.fill_background()
  local clicked = gfx.mouse_cap & 1 == 1 and S.last_cap & 1 == 0
  S.last_cap = gfx.mouse_cap
  S.hover = nil
  local mode = C.get_mode()
  local wide = gfx.w > gfx.h * 2.2
  local pad = 10
  if wide then
    -- larga e bassa (agganciata sotto l'arrangiamento): modi a sinistra, due file da 10, Togli a destra
    local bh = math.max(22, math.floor((gfx.h - 2 * pad - 8) / 3))
    for i, m in ipairs(C.MODES) do
      if icon_button(pad, pad + (i - 1) * (bh + 4), 92, bh, m, T(C.MODE_NAMES[m]), m == mode, clicked) then C.set_mode(m) end
    end
    local tw = 100
    local gx, gw = pad + 102, gfx.w - pad * 2 - 102 - tw - 8
    local per_row = math.ceil(#C.PALETTE / 2)
    local cw, ch = math.floor((gw - (per_row - 1) * 6) / per_row), math.floor((gfx.h - 2 * pad - 24 - 6) / 2)
    for n = 1, #C.PALETTE do
      local c, r = (n - 1) % per_row, (n - 1) // per_row
      swatch(gx + c * (cw + 6), pad + r * (ch + 6), cw, ch, n, clicked)
    end
    if icon_button(gfx.w - pad - tw, pad, tw, math.min(44, 2 * ch + 6), "togli", T("Togli"), false, clicked) then C.apply(0, T("Colore tolto")) end
    text(UI.fit_text(S.hover or S.status, gw), gx, gfx.h - pad - 18, 15, S.hover and UI.colors.text or (S.ok and TEAL or { 1, 0.45, 0.4, 1 }))
  else
    -- stretta e alta: modi in alto, griglia da 4 per riga, Togli e stato sotto
    local w = gfx.w - 2 * pad
    local mw = math.floor((w - 8) / 3)
    for i, m in ipairs(C.MODES) do
      if icon_button(pad + (i - 1) * (mw + 4), pad, mw, 40, m, T(C.MODE_NAMES[m]), m == mode, clicked) then C.set_mode(m) end
    end
    local top = pad + 50
    local bottom = gfx.h - pad - 90
    local cw = math.floor((w - 3 * 6) / 4)
    local rows = math.ceil(#C.PALETTE / 4)
    local ch = math.max(18, math.min(cw, math.floor((bottom - top - (rows - 1) * 6) / rows)))
    for n = 1, #C.PALETTE do
      local c, r = (n - 1) % 4, (n - 1) // 4
      swatch(pad + c * (cw + 6), top + r * (ch + 6), cw, ch, n, clicked)
    end
    local y = top + rows * (ch + 6) + 2
    if icon_button(pad, y, w, 40, "togli", T("Togli colore"), false, clicked) then C.apply(0, T("Colore tolto")) end
    local msg = S.hover or S.status
    gfx.setfont(1, "Arial", 15)
    local lines = UI.wrap_text(msg, w)
    for i = 1, math.min(2, #lines) do
      text(lines[i], pad, y + 48 + (i - 1) * 18, 15, S.hover and UI.colors.text or (S.ok and TEAL or { 1, 0.45, 0.4, 1 }))
    end
  end
end

local function loop()
  local c = gfx.getchar()
  if c < 0 or c == 27 then
    reaper.SetExtState(SECTION, "finestra", table.concat({ gfx.dock(-1, 0, 0, 0, 0) }, ","), true)
    gfx.quit()
    return
  end
  draw()
  gfx.update()
  reaper.defer(loop)
end

if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
C.refresh_buttons()
local d, px, py, pw, ph = (reaper.GetExtState(SECTION, "finestra") .. ","):match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
gfx.init(T("ZP Colori"), tonumber(pw) or 300, tonumber(ph) or 430, tonumber(d) or 0, tonumber(px) or 260, tonumber(py) or 160)
loop()
