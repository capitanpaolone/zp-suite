-- Test di ZP_GfxScale.lua con un gfx finto che registra le chiamate.
-- Uso: lua test_gfx_scale.lua "<cartella ZP Studio Suite>"
local _info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local dir = arg[1] or ((_info or "./") .. "../../ZP Studio Suite")
local fails, total = 0, 0
local function check(name, cond, extra)
  total = total + 1
  if not cond then fails = fails + 1; print("FAIL  " .. name .. (extra and ("  " .. tostring(extra)) or "")) end
end
local function same(a, b) return math.abs(a - b) < 1e-9 end

local function make_real(w, h)
  local calls = {}
  local G = { w = w, h = h, x = 0, y = 0, mouse_x = 0, mouse_y = 0, texth = 14, mouse_cap = 0 }
  for _, n in ipairs({ "rect", "roundrect", "line", "circle", "arc", "triangle", "blit", "gradrect", "setfont", "set", "lineto", "rectto" }) do
    G[n] = function(...) calls[#calls + 1] = { n, ... } end
  end
  G.drawstr = function(s) calls[#calls + 1] = { "drawstr", s, G.x, G.y }; G.x = G.x + #s * 7 end
  G.measurestr = function(s) return #s * 7, G.texth end
  return G, calls
end
local function load_mod() return dofile(dir .. "/ZP_GfxScale.lua") end

-- 1) senza ZP_GFX_SCALE_FN: la tabella originale, identica
ZP_GFX_SCALE_FN = nil
do
  local G = make_real(780, 530)
  check("senza FN restituisce l'originale", load_mod().wrap(G) == G)
end

-- 1b) real nil (test headless senza gfx): restituisce nil senza errori
do
  ZP_GFX_SCALE_FN = function() return 1.5 end
  check("real nil restituisce nil", load_mod().wrap(nil) == nil)
end

-- 2) fattore 1 (finestra di partenza): le funzioni sono quelle native, nessuna conversione
ZP_GFX_SCALE_FN = function(w, h) return math.min(w / 780, h / 530) end
do
  local G = make_real(780, 530)
  local g = load_mod().wrap(G)
  check("s=1: rect nativa", g.rect == G.rect)
  check("s=1: w/h", g.w == 780 and g.h == 530)
  g.x, g.y = 11, 22
  check("s=1: x,y scritti uguali", G.x == 11 and G.y == 22)
end

-- 3) fattore 1.5 (1170x795): coordinate logiche -> reali
do
  local G, calls = make_real(1170, 795)
  local g = load_mod().wrap(G)
  check("s=1.5: w logica", same(g.w, 780), g.w)
  check("s=1.5: h logica", same(g.h, 530), g.h)
  G.mouse_x, G.mouse_y = 300, 150
  check("s=1.5: mouse logico", same(g.mouse_x, 200) and same(g.mouse_y, 100))
  g.rect(10, 20, 100, 40, true)
  local c = calls[#calls]
  check("s=1.5: rect", c[1] == "rect" and c[2] == 15 and c[3] == 30 and c[4] == 150 and c[5] == 60 and c[6] == true,
    table.concat({ tostring(c[2]), tostring(c[3]), tostring(c[4]), tostring(c[5]) }, ","))
  g.setfont(1, "Arial", 16, 98)
  c = calls[#calls]
  check("s=1.5: font 16 -> 24", c[1] == "setfont" and c[4] == 24 and c[5] == 98, c[4])
  g.setfont(1)
  check("s=1.5: setfont(idx) invariato", calls[#calls][1] == "setfont" and calls[#calls][3] == nil)
  g.x, g.y = 40, 60
  check("s=1.5: x,y reali", G.x == 60 and G.y == 90)
  g.drawstr("abc")
  c = calls[#calls]
  check("s=1.5: drawstr alla posizione reale", c[3] == 60 and c[4] == 90)
  check("s=1.5: x logica dopo drawstr", same(g.x, (60 + 21) / 1.5), g.x)
  local mw, mh = g.measurestr("abcd")
  check("s=1.5: measurestr logica", same(mw, 28 / 1.5) and same(mh, 14 / 1.5), mw)
  g.line(0, 0, 100, 50)
  c = calls[#calls]
  check("s=1.5: line", c[2] == 0 and c[4] == 150 and c[5] == 75)
  g.circle(50, 50, 10, true)
  c = calls[#calls]
  check("s=1.5: circle", c[2] == 75 and c[3] == 75 and same(c[4], 15))
  g.blit(3, 1, 0, 60, 0, 60, 60, 20, 20, 32, 32)
  c = calls[#calls]
  check("s=1.5: blit dest scalata, sorgente intatta",
    c[5] == 60 and c[7] == 60 and c[9] == 30 and c[10] == 30 and c[11] == 48 and c[12] == 48, table.concat({ c[9], c[10], c[11], c[12] }, ","))
  g.blit(3, 1, 0)
  check("s=1.5: blit senza dest -> scale*s", same(calls[#calls][3], 1.5))
  g.triangle(0, 0, 10, 0, 5, 10)
  c = calls[#calls]
  check("s=1.5: triangle", c[4] == 15 and c[7] == 15)
  g.triangle(0, 0, 10, 0, 5, 10, true)  -- come in ZP_UI: "true" finale
  c = calls[#calls]
  check("s=1.5: triangle con true finale", c[4] == 15 and c[7] == 15 and c[8] == true)
  g.set(1, 0, 0)  -- passa invariata
  check("s=1.5: set passa", calls[#calls][1] == "set" and calls[#calls][3] == 0)
  check("s=1.5: mouse_cap passa", g.mouse_cap == 0)
  g.rect(0, 0, 1, 1)
  c = calls[#calls]
  check("s=1.5: rect 1px resta almeno 1", c[4] >= 1 and c[5] >= 1)
end

-- 3b) _real: misure vere della finestra (per salvarle), anche con fattore 1
do
  ZP_GFX_SCALE_FN = function() return 1.5 end
  local G = make_real(1170, 795); local g = load_mod().wrap(G)
  check("_real a s=1.5 e' la tabella vera", g._real == G and g._real.w == 1170 and g.w == 780)
  ZP_GFX_SCALE_FN = function() return 1 end
  g = load_mod().wrap(G)
  check("_real a s=1 non rompe niente", g.w == 1170 and (g._real == nil or g._real == G))
end

-- 4) i rettangoli adiacenti restano adiacenti (nessuna fessura) a scale non intere
for _, sc in ipairs({ 1.1, 1.3333, 1.77, 2.2 }) do
  ZP_GFX_SCALE_FN = function() return sc end
  local G, calls = make_real(1000, 700)
  local g = load_mod().wrap(G)
  local ok = true
  for x = 0, 200, 37 do
    g.rect(x, 5, 37, 10); g.rect(x + 37, 5, 37, 10)
    local a, b = calls[#calls - 1], calls[#calls]
    if a[2] + a[4] ~= b[2] then ok = false end
  end
  check("rect adiacenti senza fessure a s=" .. sc, ok)
end

-- 5) fattori assurdi o finestra non ancora creata -> scala 1
do
  ZP_GFX_SCALE_FN = function() return 0 / 0 end
  local G = make_real(500, 500); local g = load_mod().wrap(G)
  check("NaN -> originale", g.rect == G.rect)
  ZP_GFX_SCALE_FN = function() return 99 end
  g = load_mod().wrap(G)
  check("fattore enorme -> originale", g.rect == G.rect)
  ZP_GFX_SCALE_FN = function(w, h) return w / 300 end
  local G0 = make_real(0, 0); g = load_mod().wrap(G0)
  check("finestra 0x0 -> originale", g.rect == G0.rect)
end

-- 6) setclip: assente resta nil, presente viene scalato
do
  ZP_GFX_SCALE_FN = function() return 1.5 end
  local G_no = make_real(900, 600)
  local g_no = load_mod().wrap(G_no)
  check("setclip assente resta nil", g_no.setclip == nil)

  local G_yes, calls = make_real(900, 600)
  G_yes.setclip = function(...) calls[#calls + 1] = { "setclip", ... } end
  local g_yes = load_mod().wrap(G_yes)
  g_yes.setclip(10, 20, 100, 50)
  local c = calls[#calls]
  check("setclip scalato a s=1.5", c and c[1] == "setclip" and c[2] == 15 and c[3] == 30 and c[4] == 150 and c[5] == 75)
end

print(string.format("%d controlli, %d falliti", total, fails))
if fails == 0 then print("TUTTI OK") else print("ERRORI") end
os.exit(fails == 0 and 0 or 1)
