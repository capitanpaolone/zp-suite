-- @noindex

-- ZP Studio Suite: zoom proporzionale per le finestre gfx.
--
-- Uso: lo script imposta ZP_GFX_SCALE_FN(w, h) -> fattore di scala e poi, in testa al file,
--   local gfx = gfx
--   gfx = dofile(".../ZP_GfxScale.lua").wrap(gfx)
-- Da quel punto, nel file, "gfx" e' un involucro: lo script disegna in coordinate LOGICHE
-- (gfx.w, gfx.h, gfx.mouse_x/y, gfx.x/y, font, rect, line, blit...) e l'involucro le porta
-- alla finestra reale moltiplicando per il fattore. La tabella gfx vera di REAPER non viene
-- sostituita, quindi le funzioni native continuano a leggere i loro valori come sempre.
--
-- Garanzie: senza ZP_GFX_SCALE_FN, o con fattore esattamente 1, wrap() restituisce/usa la
-- tabella gfx originale: comportamento identico a prima. Solo grafica: nessun dato di
-- progetto, audio o ExtState viene toccato.

local M = {}
local floor, max = math.floor, math.max

function M.wrap(real)
  if type(real) ~= "table" then return real end
  local fn = rawget(_G, "ZP_GFX_SCALE_FN")
  if type(fn) ~= "function" then return real end

  local function sc()
    local w, h = real.w, real.h
    if not w or not h or w <= 0 or h <= 0 then return 1 end
    local s = fn(w, h)
    if type(s) ~= "number" or s ~= s or s < 0.25 or s > 8 then return 1 end
    -- fattori a un passo di 1/64: niente vibrazioni quando si trascina il bordo
    return floor(s * 64 + 0.5) / 64
  end

  local function P(v, s) return floor(v * s + 0.5) end

  -- funzioni che ricevono coordinate/dimensioni
  local W = {}
  W.rect = function(x, y, w, h, ...)
    local s = sc(); local x0, y0 = P(x, s), P(y, s)
    local w1, h1 = P(x + w, s) - x0, P(y + h, s) - y0
    if w > 0 and w1 < 1 then w1 = 1 end
    if h > 0 and h1 < 1 then h1 = 1 end
    return real.rect(x0, y0, w1, h1, ...)
  end
  if real.setclip then
    W.setclip = function(x, y, w, h)
      local s = sc(); local x0, y0 = P(x, s), P(y, s)
      return real.setclip(x0, y0, max(0, P(x + w, s) - x0), max(0, P(y + h, s) - y0))
    end
  end
  W.roundrect = function(x, y, w, h, r, ...)
    local s = sc(); local x0, y0 = P(x, s), P(y, s)
    return real.roundrect(x0, y0, max(1, P(x + w, s) - x0), max(1, P(y + h, s) - y0), r * s, ...)
  end
  W.line = function(x1, y1, x2, y2, ...)
    local s = sc()
    return real.line(P(x1, s), P(y1, s), P(x2, s), P(y2, s), ...)
  end
  W.lineto = function(x, y, ...) local s = sc(); return real.lineto(P(x, s), P(y, s), ...) end
  W.rectto = function(x, y) local s = sc(); return real.rectto(P(x, s), P(y, s)) end
  W.circle = function(x, y, r, ...) local s = sc(); return real.circle(P(x, s), P(y, s), r * s, ...) end
  W.arc = function(x, y, r, ...) local s = sc(); return real.arc(P(x, s), P(y, s), r * s, ...) end
  W.triangle = function(...)
    local s = sc(); local n = select("#", ...); local a = { ... }
    -- ZP_UI passa anche un "true" finale, che REAPER ignora: si scalano solo i numeri
    for i = 1, n do if type(a[i]) == "number" then a[i] = P(a[i], s) end end
    return real.triangle(table.unpack(a, 1, n))
  end
  W.gradrect = function(x, y, w, h, r, g, b, a, drdx, dgdx, dbdx, dadx, drdy, dgdy, dbdy, dady)
    local s = sc(); local x0, y0 = P(x, s), P(y, s)
    local function d(v) return v and v / s or v end
    return real.gradrect(x0, y0, max(1, P(x + w, s) - x0), max(1, P(y + h, s) - y0), r, g, b, a,
      d(drdx), d(dgdx), d(dbdx), d(dadx), d(drdy), d(dgdy), d(dbdy), d(dady))
  end
  -- blit(src, scale, rotation, srcx, srcy, srcw, srch, destx, desty, destw, desth, rotxoffs, rotyoffs)
  W.blit = function(...)
    local s = sc(); local n = select("#", ...); local a = { ... }
    if a[8] ~= nil then a[8] = P(a[8], s) end
    if a[9] ~= nil then a[9] = P(a[9], s) end
    if a[10] ~= nil then a[10] = P(a[10], s) end
    if a[11] ~= nil then a[11] = P(a[11], s) end
    if a[10] == nil or a[11] == nil then a[2] = (a[2] or 1) * s end   -- senza destw/desth conta "scale"
    if a[12] ~= nil then a[12] = a[12] * s end
    if a[13] ~= nil then a[13] = a[13] * s end
    return real.blit(table.unpack(a, 1, max(n, 3)))
  end
  W.setfont = function(idx, name, size, ...)
    if name == nil or size == nil then return real.setfont(idx, name, size, ...) end
    local s = sc()
    return real.setfont(idx, name, max(6, P(size, s)), ...)
  end
  W.drawstr = function(str, flags, right, bottom)
    if right ~= nil or bottom ~= nil then
      local s = sc()
      return real.drawstr(str, flags, right and P(right, s), bottom and P(bottom, s))
    end
    return real.drawstr(str, flags)
  end
  W.measurestr = function(str)
    local w, h = real.measurestr(str); local s = sc(); return w / s, h / s
  end
  W.measurechar = function(c)
    local w, h = real.measurechar(c); local s = sc(); return w / s, h / s
  end

  -- variabili in coordinate logiche (lettura)
  local V = {
    w = function(s) return real.w / s end,
    h = function(s) return real.h / s end,
    x = function(s) return real.x / s end,
    y = function(s) return real.y / s end,
    mouse_x = function(s) return real.mouse_x / s end,
    mouse_y = function(s) return real.mouse_y / s end,
    texth = function(s) return real.texth / s end,
  }
  -- variabili in coordinate logiche (scrittura)
  local SET = {
    x = function(v, s) real.x = P(v, s) end,
    y = function(v, s) real.y = P(v, s) end,
  }

  return setmetatable({}, {
    __index = function(_, k)
      if k == "_real" then return real end   -- misure vere della finestra (da salvare, non in logiche)
      local s = sc()
      if s == 1 then return real[k] end
      local f = W[k]; if f then return f end
      local v = V[k]; if v then return v(s) end
      return real[k]
    end,
    __newindex = function(_, k, v)
      local s = sc()
      local set = SET[k]
      if set and s ~= 1 then set(v, s) else real[k] = v end
    end,
  })
end

return M
