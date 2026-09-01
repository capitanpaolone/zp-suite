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

  local font_size = rect.h <= 24 and 13 or 15
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

function UI.open_help(anchor)
  local help_path = script_dir_from_debug() .. "/help/index.html"
  local suffix = ""
  if anchor and anchor ~= "" then suffix = "#" .. tostring(anchor):gsub("#", "") end
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  local target = help_path .. suffix
  if os_name:match("Win") then
    os.execute('start "" "' .. target:gsub('"', '\\"') .. '"')
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute("open " .. string.format("%q", target))
  else
    os.execute("xdg-open " .. string.format("%q", target) .. " >/dev/null 2>&1 &")
  end
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

return UI
