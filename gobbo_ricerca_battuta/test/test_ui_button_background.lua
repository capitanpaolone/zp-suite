-- Regressione: gfx.roundrect disegna un contorno, anche con un settimo argomento.
-- Controlla il fondo reale sotto le etichette, inclusa la composizione alpha.
local ui_path = arg[1] or 'ZP Studio Suite/ZP_UI.lua'
local sample_x, sample_y = 60, 27
local pixel, color, label_color
local checks = 0
local function blend()
    for i = 1, 3 do
        pixel[i] = color[i] * color[4] + pixel[i] * (1 - color[4])
    end
end
local function set_color(r, g, b, a)
    color = {r, g, b, a or 1}
end
local function rect(x, y, w, h, filled)
    if filled ~= false and filled ~= 0 and sample_x >= x and sample_x < x + w
        and sample_y >= y and sample_y < y + h then blend() end
end
local function circle(x, y, radius, filled)
    if filled and (sample_x - x)^2 + (sample_y - y)^2 <= radius^2 then blend() end
end
local function luminance(rgb)
    local result = 0
    for i, weight in ipairs({0.2126, 0.7152, 0.0722}) do
        local channel = rgb[i]
        local linear = channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055)^2.4
        result = result + weight * linear
    end
    return result
end
local function near(actual, expected, label)
    checks = checks + 1
    assert(math.abs(actual - expected) < 0.000001, label)
end
for _, roundrect_available in ipairs({true, false}) do
    gfx = {
        set = set_color, rect = rect, circle = circle, line = function() end,
        setfont = function() end, measurestr = function(text) return #text * 6, 15 end,
        drawstr = function() label_color = {color[1], color[2], color[3]} end,
        mouse_x = -1, mouse_y = -1,
    }
    -- Il campione e' interno al pulsante: un contorno nativo non lo colora.
    if roundrect_available then gfx.roundrect = function() end end
    local ui = dofile(ui_path)
    for _, state in ipairs({'normal', 'hover', 'active'}) do
        local baseline
        for _, panel in ipairs({{0.075, 0.075, 0.08}, {0.86, 0.86, 0.78}, {0.95, 0.95, 0.95}}) do
            pixel = {panel[1], panel[2], panel[3]}
            gfx.mouse_x, gfx.mouse_y = state == 'hover' and 60 or -1, state == 'hover' and 27 or -1
            local clicked = ui.draw_button({x=10,y=10,w=180,h=28}, 'Riposiziona sul player', state=='active', true, false, 'neutral')
            assert(not clicked, 'il disegno non deve attivare il comando')
            if baseline then
                for i=1,3 do near(pixel[i], baseline[i], 'fondo del pulsante dipendente dal tema: '..state) end
            else baseline = {pixel[1],pixel[2],pixel[3]} end
            local foreground, background = luminance(label_color), luminance(pixel)
            local ratio = (math.max(foreground,background)+0.05)/(math.min(foreground,background)+0.05)
            checks = checks + 1
            assert(ratio >= (state=='active' and 3 or 4.5), 'contrasto etichetta insufficiente: '..state..' '..ratio)
        end
    end
    gfx.mouse_x, gfx.mouse_y = 60, 27
    pixel = {0.95,0.95,0.95}
    assert(ui.draw_button({x=10,y=10,w=180,h=28}, 'Cerca', false, true, true, 'neutral'), 'clic perso')
    assert(not ui.draw_button({x=10,y=10,w=180,h=28}, 'Cerca', false, false, true, 'neutral'), 'clic su comando disabilitato')
end
print(checks..' verifiche fondo e contrasto pulsanti')
print('TUTTI OK')
