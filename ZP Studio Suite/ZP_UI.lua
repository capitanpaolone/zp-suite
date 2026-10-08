-- @noindex

-- ZP Studio Suite shared UI helpers
-- Small gfx primitives shared by ZP Studio Suite Lua windows.

local UI = {}

UI.VERSION = "v1.0.0"

UI.colors = {
  bg = {0.07, 0.07, 0.09, 1},
  panel = {0.10, 0.10, 0.14, 1},
  panel_border = {0.32, 0.31, 0.42, 1},
  title = {0.92, 0.88, 0.78, 1},
  credit = {0.56, 0.72, 0.86, 1},
  text = {0.92, 0.91, 0.94, 1},
  muted = {0.68, 0.66, 0.74, 1},
  disabled = {0.48, 0.48, 0.50, 1},
  blue = {0.16, 0.42, 0.60, 1},
  green = {0.12, 0.50, 0.25, 1},
  red = {0.55, 0.10, 0.10, 1}
}

local function set_color(c)
  gfx.set(c[1], c[2], c[3], c[4] or 1)
end

local function brighten(c, amount)
  return {
    math.min(1, (c[1] or 0) + amount),
    math.min(1, (c[2] or 0) + amount),
    math.min(1, (c[3] or 0) + amount),
    c[4] or 1
  }
end

function UI.set_color(c)
  set_color(c)
end

function UI.point_in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function UI.fit_text(text, max_w)
  text = tostring(text or "")
  if gfx.measurestr(text) <= max_w then return text end
  local suffix = "..."
  local suffix_w = gfx.measurestr(suffix)
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate) + suffix_w > max_w then break end
    out = candidate
  end
  return (out ~= "" and out:gsub("%s+$", "") or "") .. suffix
end

function UI.fill_background()
  set_color(UI.colors.bg)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
end

local function draw_rect(rect, filled)
  if gfx.roundrect then
    gfx.roundrect(rect.x, rect.y, rect.w, rect.h, rect.r or 4, true, filled)
  else
    gfx.rect(rect.x, rect.y, rect.w, rect.h, filled)
  end
end

local function button_colors(style)
  local colors = {
    normal = {0.13, 0.13, 0.19, 1},
    hover = {0.30, 0.30, 0.40, 1},
    active = {0.16, 0.42, 0.60, 1},
    border = {0.42, 0.44, 0.56, 1},
    text = {0.92, 0.91, 0.94, 1}
  }
  if style == "copy" or style == "save" or style == "play" or style == "play_now" then
    colors.normal = {0.08, 0.36, 0.18, 1}
    colors.hover = {0.14, 0.66, 0.28, 1}
    colors.active = {0.22, 0.92, 0.42, 1}
    colors.border = {0.52, 1.00, 0.62, 1}
  elseif style == "play_select" or style == "play_click" then
    colors.normal = {0.12, 0.24, 0.38, 1}
    colors.hover = {0.20, 0.54, 0.82, 1}
    colors.active = {0.20, 0.76, 1.00, 1}
    colors.border = {0.54, 0.90, 1.00, 1}
  elseif style == "stop" or style == "danger" then
    colors.normal = {0.48, 0.10, 0.10, 1}
    colors.hover = {0.76, 0.16, 0.14, 1}
    colors.active = {1.00, 0.18, 0.12, 1}
    colors.border = {1.00, 0.46, 0.38, 1}
  elseif style == "tab" then
    colors.normal = {0.13, 0.13, 0.19, 1}
    colors.hover = {0.22, 0.44, 0.70, 1}
    colors.active = {0.12, 0.62, 1.00, 1}
    colors.border = {0.54, 0.86, 1.00, 1}
  end
  return colors
end

function UI.draw_button(rect, label, active, enabled, clicked, style)
  enabled = enabled ~= false
  rect.r = rect.r or 4
  local hover = enabled and UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  local colors = button_colors(style)
  local fill = active and colors.active or (hover and colors.hover or colors.normal)
  if not enabled then fill = {0.08, 0.08, 0.11, 1} end
  gfx.set(0.02, 0.02, 0.03, enabled and 0.55 or 0.30)
  if gfx.roundrect then
    gfx.roundrect(rect.x + 1, rect.y + 2, rect.w, rect.h, rect.r or 4, true, true)
  else
    gfx.rect(rect.x + 1, rect.y + 2, rect.w, rect.h, true)
  end
  set_color(fill)
  draw_rect(rect, true)
  gfx.set(math.min(1, fill[1] + 0.16), math.min(1, fill[2] + 0.16), math.min(1, fill[3] + 0.18), enabled and 0.42 or 0.16)
  gfx.rect(rect.x + 2, rect.y + 2, rect.w - 4, math.max(2, math.floor(rect.h * 0.36)), true)
  if hover and enabled then
    gfx.set(math.min(1, fill[1] + 0.30), math.min(1, fill[2] + 0.30), math.min(1, fill[3] + 0.34), 0.34)
    gfx.rect(rect.x + 2, rect.y + math.floor(rect.h * 0.48), rect.w - 4, math.max(2, math.floor(rect.h * 0.35)), true)
  end
  if active and enabled then
    gfx.set(math.min(1, fill[1] + 0.34), math.min(1, fill[2] + 0.34), math.min(1, fill[3] + 0.38), 0.34)
    gfx.rect(rect.x + 2, rect.y + 2, rect.w - 4, rect.h - 4, true)
  end
  set_color(active and brighten(colors.border, 0.18) or (hover and brighten(colors.border, 0.12) or colors.border))
  draw_rect(rect, false)
  if hover and not active then
    gfx.set(0.86, 0.94, 1.0, 1.0)
    gfx.line(rect.x + 2, rect.y + 1, rect.x + rect.w - 3, rect.y + 1)
    gfx.line(rect.x + 2, rect.y + rect.h - 2, rect.x + rect.w - 3, rect.y + rect.h - 2)
  elseif active and enabled then
    gfx.set(0.96, 0.98, 1.0, 0.95)
    gfx.line(rect.x + 2, rect.y + 1, rect.x + rect.w - 3, rect.y + 1)
    gfx.line(rect.x + 2, rect.y + rect.h - 2, rect.x + rect.w - 3, rect.y + rect.h - 2)
  end

  local text_x = rect.x + 10
  local text_w = rect.w - 20
  local cy = rect.y + math.floor(rect.h * 0.5)
  if style == "copy" then
    gfx.set(enabled and 0.86 or 0.42, enabled and 0.94 or 0.42, enabled and 1.0 or 0.42, 1)
    gfx.rect(rect.x + 10, cy - 7, 10, 12, false)
    gfx.rect(rect.x + 14, cy - 3, 10, 12, false)
    text_x = rect.x + 30
    text_w = rect.w - 38
  elseif style == "play_select" or style == "play_click" then
    local ix = rect.x + 9
    gfx.set(enabled and 0.98 or 0.42, enabled and 0.82 or 0.42, enabled and 0.42 or 0.42, 1)
    gfx.line(ix, cy - 8, ix, cy + 8)
    gfx.triangle(ix + 1, cy - 8, ix + 1, cy - 2, ix + 10, cy - 5, true)
    gfx.set(enabled and 0.86 or 0.42, enabled and 0.94 or 0.42, enabled and 1.0 or 0.42, 1)
    gfx.triangle(ix + 15, cy - 6, ix + 15, cy + 6, ix + 26, cy, true)
    text_x = rect.x + 39
    text_w = rect.w - 45
  elseif style == "play" or style == "play_now" then
    gfx.set(enabled and 0.86 or 0.42, enabled and 0.94 or 0.42, enabled and 1.0 or 0.42, 1)
    gfx.triangle(rect.x + 11, cy - 6, rect.x + 11, cy + 6, rect.x + 22, cy, true)
    text_x = rect.x + 30
    text_w = rect.w - 38
  elseif style == "stop" then
    gfx.set(enabled and 1.0 or 0.42, enabled and 0.86 or 0.42, enabled and 0.82 or 0.42, 1)
    gfx.rect(rect.x + 12, cy - 6, 12, 12, true)
    text_x = rect.x + 32
    text_w = rect.w - 40
  elseif style == "save" then
    local ix = rect.x + 10
    local iy = cy - 8
    gfx.set(enabled and 0.90 or 0.42, enabled and 0.98 or 0.42, enabled and 0.90 or 0.42, 1)
    gfx.rect(ix, iy, 15, 16, false)
    gfx.rect(ix + 3, iy + 2, 8, 5, true)
    gfx.rect(ix + 4, iy + 10, 8, 4, false)
    text_x = rect.x + 31
    text_w = rect.w - 38
  end

  local font_size = rect.font or (rect.h <= 24 and 13 or 15)   -- rect.font: dimensione scelta dalla finestra
  gfx.setfont(1, "Arial", font_size)
  gfx.set(enabled and colors.text[1] or 0.48, enabled and colors.text[2] or 0.48, enabled and colors.text[3] or 0.48, 1)
  gfx.x = text_x
  gfx.y = rect.y + math.max(4, math.floor((rect.h - font_size) * 0.5))
  gfx.drawstr(UI.fit_text(label, text_w))
  return clicked and enabled and hover
end


local function script_dir_from_debug()
  local info = debug.getinfo(2, "S") or debug.getinfo(1, "S")
  local source = info and info.source or ""
  source = source:gsub("^@", "")
  return source:match("^(.*)[/\\]") or "."
end

-- Indirizzo file:// codificato: con il percorso "nudo" su macOS il comando open cerca un file
-- chiamato letteralmente "index.html#sezione" e non apre niente.
function UI.help_url(path, anchor)
  path = tostring(path):gsub("\\", "/")
  if not path:match("^/") then path = "/" .. path end          -- Windows: C:/... -> /C:/...
  local encoded = path:gsub("[^%w%-%._~/:]", function(c) return string.format("%%%02X", c:byte()) end)
  local suffix = (anchor and anchor ~= "") and ("#" .. tostring(anchor):gsub("#", "")) or ""
  return "file://" .. encoded .. suffix
end

function UI.open_url(url)
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if os_name:match("Win") then
    os.execute('start "" "' .. url .. '"')
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute("open " .. string.format("%q", url))
  else
    os.execute("xdg-open " .. string.format("%q", url) .. " >/dev/null 2>&1 &")
  end
end

function UI.open_help(anchor, page)
  UI.open_url(UI.help_url(script_dir_from_debug() .. "/help/" .. (page or "index.html"), anchor))
end

function UI.draw_help_button(rect, clicked, anchor)
  rect = rect or { x = gfx.w - 54, y = 18, w = 34, h = 28 }
  local hit = UI.draw_button(rect, "?", false, true, clicked, "tab")
  if hit then UI.open_help(anchor) end
  return hit
end

function UI.draw_header(opts)
  opts = opts or {}
  local x = opts.x or 22
  local y = opts.y or 16
  local icon_size = opts.icon_size or 34
  if opts.icon_id and opts.icon_id >= 0 then
    gfx.blit(opts.icon_id, 1, 0, 0, 0, opts.icon_src_size or 30, opts.icon_src_size or 30, x, y, icon_size, icon_size)
  elseif opts.fallback_icon then
    opts.fallback_icon(x, y, icon_size)
  end

  gfx.setfont(1, "Arial", opts.title_size or 21)
  set_color(UI.colors.title)
  gfx.x = x + icon_size + 10
  gfx.y = y + 2
  gfx.drawstr(opts.title or "")

  gfx.setfont(1, "Arial", opts.credit_size or 12)
  set_color(UI.colors.credit)
  gfx.x = x + icon_size + 10
  gfx.y = y + (opts.credit_offset or 28)
  gfx.drawstr(opts.credit or "ZP Studio Suite v1.0.5 - Paolo Balestri")

  if opts.description and opts.description ~= "" then
    gfx.setfont(1, "Arial", opts.description_size or 15)
    set_color(UI.colors.muted)
    gfx.x = x
    gfx.y = y + 52
    gfx.drawstr(UI.fit_text(opts.description, gfx.w - (x * 2)))
  end
end

---------------------------------------------------------------------------
-- Controlli "a tema": pannelli di zona, interruttori con LED, pulsanti tondi
-- del trasporto, pomelli. Disegno immediato come draw_button: si chiamano a ogni
-- giro e restituiscono se sono stati usati.
---------------------------------------------------------------------------

-- Rettangolo pieno con gli angoli tondi (gfx.roundrect disegna solo il contorno).
function UI.fill_round(x, y, w, h, r)
  r = math.max(0, math.min(r or 6, math.floor(math.min(w, h) / 2)))
  if r < 2 then gfx.rect(x, y, w, h, true) return end
  gfx.rect(x + r, y, w - 2 * r, h, true)
  gfx.rect(x, y + r, r, h - 2 * r, true)
  gfx.rect(x + w - r, y + r, r, h - 2 * r, true)
  gfx.circle(x + r, y + r, r, true, true)
  gfx.circle(x + w - r - 1, y + r, r, true, true)
  gfx.circle(x + r, y + h - r - 1, r, true, true)
  gfx.circle(x + w - r - 1, y + h - r - 1, r, true, true)
end

-- Pannello di una zona: fondo appena piu' chiaro, bordo, titolo piccolo in alto.
-- Restituisce il rettangolo utile, sotto il titolo.
function UI.draw_panel(rect, title, opts)
  opts = opts or {}
  local fill = opts.fill or {0.085, 0.090, 0.110, 1}
  set_color(fill)
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 7)
  set_color(opts.border or {0.22, 0.23, 0.28, 1})
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 7, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end
  local top = 8
  if title and title ~= "" then
    gfx.setfont(1, "Arial", 11, "b")
    gfx.set(0.58, 0.62, 0.70, 1)
    gfx.x, gfx.y = rect.x + 10, rect.y + 5
    gfx.drawstr(UI.fit_text(title, rect.w - 20))
    top = 22
  end
  return { x = rect.x + 10, y = rect.y + top, w = rect.w - 20, h = rect.h - top - 8 }
end

-- Interruttore: pulsante con una spia a sinistra (verde = acceso).
function UI.draw_toggle(rect, label, on, enabled, clicked)
  enabled = enabled ~= false
  local hover = enabled and UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  local fill = hover and {0.20, 0.21, 0.27, 1} or {0.13, 0.13, 0.17, 1}
  if not enabled then fill = {0.08, 0.08, 0.10, 1} end
  set_color(fill)
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 5)
  gfx.set(0.36, 0.38, 0.46, enabled and 1 or 0.5)
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 5, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end
  local cx, cy, r = rect.x + 13, rect.y + math.floor(rect.h / 2), 5
  if on and enabled then
    gfx.set(0.25, 0.95, 0.45, 0.25); gfx.circle(cx, cy, r + 3, true, true)
    gfx.set(0.30, 0.95, 0.48, 1)
  else
    gfx.set(0.22, 0.24, 0.28, 1)
  end
  gfx.circle(cx, cy, r, true, true)
  gfx.setfont(1, "Arial", 13, on and "b" or "")
  local v = enabled and (on and 0.96 or 0.78) or 0.45
  gfx.set(v, v, v + 0.02, 1)
  local text = UI.fit_text(label, rect.w - 32)
  local _, th = gfx.measurestr(text)
  gfx.x, gfx.y = rect.x + 25, rect.y + math.floor((rect.h - th) / 2)
  gfx.drawstr(text)
  return clicked and enabled and hover
end

-- Simboli disegnati (niente font di icone in gfx).
function UI.draw_symbol(kind, cx, cy, s)
  if kind == "rec" then
    gfx.circle(cx, cy, s * 0.42, true, true)
  elseif kind == "stop" then
    local h = math.floor(s * 0.70)
    gfx.rect(cx - h / 2, cy - h / 2, h, h, true)
  elseif kind == "pause" then
    local h, w = math.floor(s * 0.62), math.max(2, math.floor(s * 0.20))
    gfx.rect(cx - w - math.floor(w * 0.6), cy - h / 2, w, h, true)
    gfx.rect(cx + math.floor(w * 0.6), cy - h / 2, w, h, true)
  elseif kind == "play" then
    local h = s * 0.42
    gfx.triangle(cx - h * 0.75, cy - h, cx - h * 0.75, cy + h, cx + h * 0.95, cy)
  elseif kind == "prev" or kind == "next" then
    local h, d = s * 0.32, (kind == "prev") and -1 or 1
    -- due triangoli e una sbarra: indietro / avanti
    gfx.triangle(cx - d * h * 0.9, cy - h, cx - d * h * 0.9, cy + h, cx + d * h * 0.1, cy)
    gfx.triangle(cx + d * h * 0.1, cy - h, cx + d * h * 0.1, cy + h, cx + d * h * 1.1, cy)
    gfx.rect((d < 0) and (cx - h * 1.25) or (cx + h * 1.1), cy - h, math.max(2, s * 0.08), h * 2, true)
  elseif kind == "left" or kind == "right" then
    local h, d = s * 0.30, (kind == "left") and -1 or 1
    gfx.triangle(cx - d * h * 0.6, cy - h, cx - d * h * 0.6, cy + h, cx + d * h * 0.7, cy)
  elseif kind == "start" then
    local h = s * 0.30
    gfx.rect(cx - h * 1.0, cy - h, math.max(2, s * 0.08), h * 2, true)
    gfx.triangle(cx + h * 0.9, cy - h, cx + h * 0.9, cy + h, cx - h * 0.6, cy)
  end
end

-- Lucchetto: chiuso (acceso) o aperto.
function UI.draw_lock(cx, cy, s, locked)
  local bw, bh = math.floor(s * 0.62), math.floor(s * 0.46)
  local bx, by = cx - bw / 2, cy - bh / 2 + s * 0.14
  gfx.rect(bx, by, bw, bh, true)
  local r = bw * 0.32
  local ax = locked and cx or (cx + bw * 0.30)
  for t = 0, 1 do   -- archetto spesso 2 px
    if gfx.arc then gfx.arc(ax, by - 1, r - t, -math.pi / 2, math.pi / 2, true)
    else gfx.circle(ax, by - 1, r - t, false, true) end
  end
  if locked then gfx.line(ax - r, by - 1, ax - r, by); gfx.line(ax + r - 1, by - 1, ax + r - 1, by) end
end

-- Pulsante tondo del trasporto. kind: rec, stop, play, prev, next.
-- opts.caption: testo sotto il cerchio (dentro rect.h). Restituisce clic.
local ROUND_COLORS = {
  rec  = { normal = {0.62, 0.07, 0.06, 1}, hover = {0.82, 0.12, 0.10, 1}, active = {1.00, 0.16, 0.12, 1}, icon = {1, 0.93, 0.92, 1} },
  play = { normal = {0.08, 0.38, 0.18, 1}, hover = {0.12, 0.56, 0.26, 1}, active = {0.20, 0.82, 0.38, 1}, icon = {0.93, 1, 0.94, 1} },
  stop = { normal = {0.17, 0.18, 0.22, 1}, hover = {0.27, 0.28, 0.34, 1}, active = {0.40, 0.42, 0.50, 1}, icon = {0.95, 0.95, 0.97, 1} },
  -- pausa: grigia; accesa (in pausa) ambra
  pause = { normal = {0.17, 0.18, 0.22, 1}, hover = {0.27, 0.28, 0.34, 1}, active = {0.86, 0.58, 0.12, 1}, icon = {0.95, 0.95, 0.97, 1} },
}
function UI.draw_round_button(rect, kind, active, enabled, clicked, opts)
  opts = opts or {}
  enabled = enabled ~= false
  local cap_h = opts.caption and 16 or 0
  local d = math.min(rect.w, rect.h - cap_h)
  local r = math.floor(d / 2)
  local cx, cy = rect.x + math.floor(rect.w / 2), rect.y + r
  local mx, my = gfx.mouse_x - cx, gfx.mouse_y - cy
  local hover = enabled and (mx * mx + my * my) <= r * r
  local pal = ROUND_COLORS[kind] or ROUND_COLORS.stop
  local fill = active and pal.active or (hover and pal.hover or pal.normal)
  if not enabled then fill = {0.09, 0.09, 0.11, 1} end
  gfx.set(0, 0, 0, 0.45); gfx.circle(cx + 1, cy + 2, r, true, true)
  set_color(fill); gfx.circle(cx, cy, r, true, true)
  gfx.set(1, 1, 1, active and 0.75 or (hover and 0.45 or 0.22)); gfx.circle(cx, cy, r, false, true)
  if active then gfx.set(1, 1, 1, 0.35); gfx.circle(cx, cy, r + 3, false, true) end
  local ic = enabled and pal.icon or {0.45, 0.45, 0.47, 1}
  set_color(ic)
  UI.draw_symbol(kind, cx, cy, d * 0.62)
  if opts.caption then
    gfx.setfont(1, "Arial", 11, "b")
    gfx.set(0.70, 0.73, 0.80, 1)
    local t = UI.fit_text(opts.caption, rect.w + 16)
    local tw = gfx.measurestr(t)
    gfx.x, gfx.y = cx - tw / 2, rect.y + d + 3
    gfx.drawstr(t)
  end
  return clicked and enabled and hover
end

-- Pomello. k = { id, value, min, max, default, step, label, text, enabled, pressed }
--   pressed: il tasto del mouse e' appena sceso (lo sa chi chiama).
-- Si usa trascinando in su/giu', con la rotella, doppio clic = valore di partenza.
-- Restituisce il nuovo valore e se e' cambiato.
UI._knob = { drag = nil, last_press = {} }
function UI.draw_knob(rect, k)
  local enabled = k.enabled ~= false
  local lo, hi = k.min or 0, k.max or 1
  local step = k.step or ((hi - lo) / 100)
  local value = math.max(lo, math.min(hi, tonumber(k.value) or lo))
  -- inline: cerchio a sinistra e scritte a destra (per le strisce basse)
  local d = k.inline and (rect.h - 2) or math.min(rect.w, rect.h - 30)
  local r = math.floor(d / 2)
  local cx, cy = rect.x + math.floor(rect.w / 2), rect.y + r + 1
  if k.inline then cx, cy = rect.x + r + 1, rect.y + math.floor(rect.h / 2) end
  local hover = enabled and UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, cx - r - 4, cy - r - 4, 2 * r + 8, 2 * r + 8)
  local down = (gfx.mouse_cap & 1) == 1
  local new = value
  local function snap(v)
    v = lo + math.floor((v - lo) / step + 0.5) * step
    return math.max(lo, math.min(hi, v))
  end
  local drag = UI._knob.drag
  if enabled and not k.readonly then
    if k.pressed and hover then
      local now = reaper.time_precise()
      local last = UI._knob.last_press[k.id]
      if last and now - last < 0.35 and k.default ~= nil then
        new = k.default
        UI._knob.last_press[k.id] = nil
      else
        UI._knob.last_press[k.id] = now
        UI._knob.drag = { id = k.id, y0 = gfx.mouse_y, v0 = value }
      end
    elseif drag and drag.id == k.id then
      if down then
        -- 160 pixel = tutta la corsa; con Shift dieci volte piu' fine
        local span = ((gfx.mouse_cap & 8) == 8) and 1600 or 160
        new = snap(drag.v0 + (drag.y0 - gfx.mouse_y) * (hi - lo) / span)
      else
        UI._knob.drag = nil
      end
    end
    if hover and gfx.mouse_wheel ~= 0 then
      new = snap(value + ((gfx.mouse_wheel > 0) and step or -step))
      gfx.mouse_wheel = 0
    end
  end

  local a0, a1 = -math.pi * 0.75, math.pi * 0.75
  local frac = (hi > lo) and (new - lo) / (hi - lo) or 0
  local av = a0 + (a1 - a0) * frac
  local function pt(a, rr) return cx + rr * math.sin(a), cy - rr * math.cos(a) end
  -- corona: binario spento e parte accesa fino al valore
  local function arc(from, to, rr)
    local n = math.max(2, math.floor(math.abs(to - from) / 0.08))
    local px, py = pt(from, rr)
    for i = 1, n do
      local x2, y2 = pt(from + (to - from) * i / n, rr)
      gfx.line(px, py, x2, y2, 1)
      px, py = x2, y2
    end
  end
  gfx.set(0.20, 0.21, 0.26, 1)
  for t = 0, 2 do arc(a0, a1, r + 2 - t) end
  if enabled then
    gfx.set(0.25, 0.68, 1.00, 1)
    for t = 0, 2 do arc(a0, av, r + 2 - t) end
  end
  local active = drag and drag.id == k.id
  gfx.set(0, 0, 0, 0.45); gfx.circle(cx + 1, cy + 2, r - 4, true, true)
  if not enabled then gfx.set(0.09, 0.09, 0.11, 1)
  elseif active then gfx.set(0.30, 0.32, 0.40, 1)
  elseif hover then gfx.set(0.24, 0.25, 0.31, 1)
  else gfx.set(0.17, 0.18, 0.22, 1) end
  gfx.circle(cx, cy, r - 4, true, true)
  gfx.set(1, 1, 1, enabled and 0.25 or 0.1); gfx.circle(cx, cy, r - 4, false, true)
  local x1, y1 = pt(av, (r - 4) * 0.25)
  local x2, y2 = pt(av, r - 6)
  gfx.set(1, 1, 1, enabled and 0.95 or 0.35)
  gfx.line(x1, y1, x2, y2, 1); gfx.line(x1 + 1, y1, x2 + 1, y2, 1)

  if k.inline then
    local tx = rect.x + d + 8
    gfx.setfont(1, "Arial", 11)
    gfx.set(0.62, 0.66, 0.74, 1)
    gfx.x, gfx.y = tx, rect.y + math.floor(rect.h / 2) - 13
    gfx.drawstr(UI.fit_text(k.label or "", rect.x + rect.w - tx))
    gfx.setfont(1, "Arial", 12, "b")
    gfx.set(enabled and 0.95 or 0.5, enabled and 0.95 or 0.5, enabled and 0.97 or 0.5, 1)
    gfx.x, gfx.y = tx, rect.y + math.floor(rect.h / 2)
    gfx.drawstr(UI.fit_text(k.text or tostring(new), rect.x + rect.w - tx))
    return new, new ~= value, hover or active
  end
  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(enabled and 0.95 or 0.5, enabled and 0.95 or 0.5, enabled and 0.97 or 0.5, 1)
  local text = UI.fit_text(k.text or tostring(new), rect.w + 10)
  local tw = gfx.measurestr(text)
  gfx.x, gfx.y = cx - tw / 2, rect.y + d + 3
  gfx.drawstr(text)
  gfx.setfont(1, "Arial", 11)
  gfx.set(0.62, 0.66, 0.74, 1)
  local lb = UI.fit_text(k.label or "", rect.w + 10)
  tw = gfx.measurestr(lb)
  gfx.x, gfx.y = cx - tw / 2, rect.y + d + 17
  gfx.drawstr(lb)
  return new, new ~= value, hover or active
end

-- Testo a capo nella larghezza data. Restituisce le righe.
function UI.wrap_text(text, max_w)
  local lines = {}
  for para in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local cand = (line == "") and word or (line .. " " .. word)
      if gfx.measurestr(cand) <= max_w or line == "" then line = cand
      else lines[#lines + 1] = line; line = word end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- Benvenuto: ReaPack non puo' eseguire niente dopo l'installazione, quindi la prima volta che
-- uno strumento ZP carica questa libreria si apre "33 Benvenuto" (controllo installazione).
-- Una volta sola: la spunta resta in ExtState ZP_STUDIO_SUITE/benvenuto_visto.
do
  if reaper and reaper.GetExtState and reaper.GetExtState("ZP_STUDIO_SUITE", "benvenuto_visto") == "" then
    reaper.SetExtState("ZP_STUDIO_SUITE", "benvenuto_visto", "1", true)
    local path = script_dir_from_debug() .. "/33_Benvenuto_Controllo_Installazione.lua"
    local f = io.open(path, "r")
    if f and reaper.AddRemoveReaScript then
      f:close()
      local id = reaper.AddRemoveReaScript(true, 0, path, true)
      if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
    end
  end
end

return UI
