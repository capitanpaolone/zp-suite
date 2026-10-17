-- @noindex

-- ZP Studio Suite — ZP Montaggio Parlato, logica pura (niente reaper.*: si prova fuori da REAPER).
-- Progetto: docs/PROGETTO_22_Centrale_Montaggio_Parlato.md (sezioni 13-15).
--
-- Fase 1 "struttura": dal parlato (parole di ZP Speech con i tempi), dall'energia del file e dal
-- copione ricava cosa tenere. Il testo fa fede; il software sgrossa, il fino si fa in Timeline.
--   * segnali di rifacimento: click forti a gruppo e/o parole del dizionario ("rifaccio", ...)
--   * rifacimento = si taglia dall'attacco della prima versione all'attacco della seconda
--   * stessa frase letta piu' volte senza segnale: vince l'ultima completa
--   * "alternativa": la lettura dopo resta, in una corsia sotto
--   * parlato che non sta nel copione e comandi: fuori
-- Tutti i tempi sono in secondi di SORGENTE (il file), come le parole di ZP Speech.

local M = {}

---------------------------------------------------------------------------
-- JSON (solo lettura, quanto basta per i documenti di ZP Speech)
---------------------------------------------------------------------------
function M.json_decode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == "" then error("json: stringa non chiusa") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        if n == "u" then
          local cp = tonumber(s:sub(i + 2, i + 5), 16); i = i + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
            local lo = tonumber(s:sub(i + 2, i + 5), 16)
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00); i = i + 6
          end
          out[#out + 1] = utf8.char(cp)
        else
          local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
          out[#out + 1] = map[n] or n; i = i + 2
        end
      else
        local j = s:find('["\\]', i) or #s + 1
        out[#out + 1] = s:sub(i, j - 1); i = j
      end
    end
  end
  value = function()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws(); local k = str(); ws(); pos = pos + 1 -- ':'
        t[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("json: valore inatteso a " .. pos) end
      pos = pos + #num; return tonumber(num)
    end
  end
  return value()
end

-- Parole di un documento "transcript" di ZP Speech -> { {s=, e=, text=}, ... } (secondi + offset)
function M.words_from_transcript(doc, offset)
  local out = {}
  offset = offset or 0
  for _, seg in ipairs((doc and doc.segments) or {}) do
    for _, w in ipairs(seg.words or {}) do
      if w.text and w.start_ms and w.end_ms then
        out[#out + 1] = { s = w.start_ms / 1000 + offset, e = w.end_ms / 1000 + offset, text = w.text }
      end
    end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end

---------------------------------------------------------------------------
-- Testo: normalizzazione e parole
---------------------------------------------------------------------------
local FOLD = {
  ["à"]="a",["á"]="a",["â"]="a",["ä"]="a",["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
  ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",["ò"]="o",["ó"]="o",["ô"]="o",["ö"]="o",
  ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",["ç"]="c",["ñ"]="n",
  ["À"]="a",["Á"]="a",["È"]="e",["É"]="e",["Ì"]="i",["Ò"]="o",["Ù"]="u",
}
-- numeri detti / scritti: la stessa cosa ("primo" novembre = "1" novembre)
local NUM = {
  zero="0", uno="1", una="1", primo="1", prima="1", due="2", secondo="2", tre="3", terzo="3",
  quattro="4", quarto="4", cinque="5", quinto="5", sei="6", sesto="6", sette="7", settimo="7",
  otto="8", ottavo="8", nove="9", nono="9", dieci="10", decimo="10", undici="11", dodici="12",
  tredici="13", quattordici="14", quindici="15", sedici="16", diciassette="17", diciotto="18",
  diciannove="19", venti="20", ventuno="21", ventidue="22", ventitre="23", ventiquattro="24",
  venticinque="25", ventisei="26", ventisette="27", ventotto="28", ventinove="29", trenta="30",
  trentuno="31", quaranta="40", cinquanta="50", sessanta="60", cento="100", mille="1000",
}

function M.tokens(text)
  text = tostring(text or ""):gsub("[\195\197][\128-\191]", function(c) return FOLD[c] or c end)
  text = text:lower():gsub("’", "'")
  local out = {}
  for w in text:gmatch("[%w]+") do out[#out + 1] = NUM[w] or w end
  return out
end

-- Parole -> gettoni: { {t=, w=indice parola, s=, e=}, ... }
function M.token_list(words)
  local out = {}
  for wi, w in ipairs(words) do
    for _, t in ipairs(M.tokens(w.text)) do out[#out + 1] = { t = t, w = wi, s = w.s, e = w.e } end
  end
  return out
end

-- Copione -> frasi { {text=, toks={...}}, ... }. Si spezza su . ! ? … ; e a capo.
function M.parse_copione(text)
  local frasi = {}
  text = tostring(text or ""):gsub("\r\n?", "\n"):gsub("…", ".")
  for chunk in (text .. "\n"):gmatch("(.-)[%.!%?;\n]+") do
    local clean = chunk:gsub("^%s+", ""):gsub("%s+$", "")
    local toks = M.tokens(clean)
    if #toks >= 2 then frasi[#frasi + 1] = { text = clean, toks = toks } end
  end
  return frasi
end

-- Due parole "uguali" per ritrovare una lettura: identiche, oppure lunghe e diverse di una lettera
-- (Whisper: "prepare il parlato" per "prepara il palato"). Serve solo a RITROVARE le letture:
-- le differenze vere si controllano dopo, parola per parola (Fase 2).
local function lev1(a, b)
  if a == b then return true end
  local la, lb = #a, #b
  if math.abs(la - lb) > 1 then return false end
  local i = 1
  while i <= la and i <= lb and a:sub(i, i) == b:sub(i, i) do i = i + 1 end
  if la == lb then return a:sub(i + 1) == b:sub(i + 1) end
  if la > lb then return a:sub(i + 1) == b:sub(i) end
  return a:sub(i) == b:sub(i + 1)
end
function M.simili(a, b)
  if a == b then return true end
  if #a < 4 or #b < 4 then return false end
  return lev1(a, b)
end
local simili = M.simili

---------------------------------------------------------------------------
-- Allineamento frasi del copione <-> parlato (LCS a finestre, partenze filtrate)
---------------------------------------------------------------------------
-- Restituisce le letture: { {k=frase, i1=, i2=, ratio=, pairs={ [indice copione]=indice gettone } }, ... }
-- senza sovrapposizioni (vince la piu' somigliante), in ordine di tempo.
function M.align(frasi, toks, min_ratio)
  min_ratio = min_ratio or 0.6
  local cand = {}
  for k, f in ipairs(frasi) do
    local n = #f.toks
    local heads = {}
    for j = 1, math.min(4, n) do heads[#heads + 1] = f.toks[j] end
    local lmax = math.floor(n * 1.4 + 0.5)
    for i = 1, #toks do
      local hit = false
      for _, h in ipairs(heads) do if simili(h, toks[i].t) then hit = true; break end end
      if hit then
        local m = math.min(lmax, #toks - i + 1)
        -- LCS tra f.toks e toks[i .. i+m-1], tabella completa per poter ricostruire le coppie
        local L = {}
        for a = 0, n do L[a] = {}; for b = 0, m do L[a][b] = 0 end end
        for a = 1, n do
          local ta, row, prev = f.toks[a], L[a], L[a - 1]
          for b = 1, m do
            if simili(ta, toks[i + b - 1].t) then row[b] = prev[b - 1] + 1
            else row[b] = (prev[b] > row[b - 1]) and prev[b] or row[b - 1] end
          end
        end
        local best, bl = 0, 0
        for b = 1, m do
          local r = 2 * L[n][b] / (n + b)
          if r > best then best, bl = r, b end
        end
        if best >= min_ratio then
          local pr, a, b = {}, n, bl
          while a > 0 and b > 0 do
            if simili(f.toks[a], toks[i + b - 1].t) and L[a][b] == L[a - 1][b - 1] + 1 then
              pr[a] = i + b - 1; a, b = a - 1, b - 1
            elseif L[a - 1][b] >= L[a][b - 1] then a = a - 1 else b = b - 1 end
          end
          -- la lettura comincia dalla prima parola che combacia (non da un "il" iniziale sciolto)
          local first, last = math.huge, 0
          for _, ti in pairs(pr) do if ti < first then first = ti end; if ti > last then last = ti end end
          local matched = 0; for _ in pairs(pr) do matched = matched + 1 end
          cand[#cand + 1] = { k = k, i1 = first, i2 = last, ratio = best, pairs = pr,
                              cover = matched / n }
        end
      end
    end
  end
  table.sort(cand, function(x, y)
    if math.abs(x.ratio - y.ratio) > 1e-9 then return x.ratio > y.ratio end
    return (x.i2 - x.i1) > (y.i2 - y.i1)
  end)
  local used, out = {}, {}
  for _, c in ipairs(cand) do
    local free = true
    for i = c.i1, c.i2 do if used[i] then free = false; break end end
    if free then
      for i = c.i1, c.i2 do used[i] = true end
      out[#out + 1] = c
    end
  end
  table.sort(out, function(x, y) return x.i1 < y.i1 end)
  return out
end

---------------------------------------------------------------------------
-- Dizionario dei comandi (deterministico, lo sceglie Paolo). "#" = un numero.
---------------------------------------------------------------------------
M.DIZIONARIO = {
  { "rifaccio", azione = "rifai" },
  { "riprovo", azione = "rifai" },
  { "versione", "alternativa", azione = "alternativa" },
  { "alternativa", azione = "alternativa" },
  { "silenzio", "di", "#", "secondi", azione = "silenzio" },
  { "silenzio", "di", "#", "secondo", azione = "silenzio" },
  { "versione", "#", azione = "nuova" },
  { "take", "#", azione = "nuova" },
  { "slide", "numero", "#", azione = "slide" },
  { "slide", "#", azione = "slide" },
  { "traccia", "numero", "#", azione = "slide" },
}

-- Dizionario dal testo delle preferenze: una riga "parole = azione" (azioni: rifai, alternativa,
-- silenzio, nuova, slide). Righe vuote o con # all'inizio ignorate.
function M.dizionario_da_testo(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local words, az = line:match("^%s*([^=#][^=]-)%s*=%s*(%a+)%s*$")
    if words then
      local e = { azione = az }
      for w in words:gmatch("%S+") do e[#e + 1] = (w == "#" or w == "N") and "#" or (M.tokens(w)[1] or w) end
      if #e > 0 then out[#out + 1] = e end
    end
  end
  return out
end

local function is_num(t) return t:match("^%d+$") ~= nil end

-- Comandi trovati fra i gettoni NON letti dal copione: { {azione=, i1=, i2=, n=numero}, ... }
function M.find_commands(toks, dict, in_text)
  local out, i = {}, 1
  dict = dict or M.DIZIONARIO
  while i <= #toks do
    local hit
    if not in_text[i] then
      for _, d in ipairs(dict) do
        local ok, num = true, nil
        for j = 1, #d do
          local tk = toks[i + j - 1]
          if not tk or in_text[i + j - 1] then ok = false; break end
          if d[j] == "#" then
            if is_num(tk.t) then num = tonumber(tk.t) else ok = false; break end
          elseif tk.t ~= d[j] then ok = false; break end
        end
        if ok then hit = { azione = d.azione, i1 = i, i2 = i + #d - 1, n = num }; break end
      end
    end
    if hit then out[#out + 1] = hit; i = hit.i2 + 1 else i = i + 1 end
  end
  return out
end

---------------------------------------------------------------------------
-- Energia (env): { hop = secondi, pk = {dB}, rms = {dB} } — una finestra ogni hop
---------------------------------------------------------------------------
local function db(x) if x <= 0 then return -120 end return 20 * math.log(x, 10) end
M.db = db

-- Accumulatore a blocchi: si chiama add() con i campioni (gia' in -1..1, canali massimizzati)
function M.env_new(sr, hop)
  local e = { hop = hop or 0.005, pk = {}, rms = {}, sr = sr }
  e._n = math.max(1, math.floor(sr * e.hop + 0.5)); e._c, e._p, e._s = 0, 0, 0
  return e
end
function M.env_add(e, v)
  local a = v < 0 and -v or v
  if a > e._p then e._p = a end
  e._s = e._s + v * v; e._c = e._c + 1
  if e._c >= e._n then
    local k = #e.pk + 1
    e.pk[k] = db(e._p); e.rms[k] = db(math.sqrt(e._s / e._c))
    e._c, e._p, e._s = 0, 0, 0
  end
end

function M.floor_db(env)
  local v = {}
  for i = 1, #env.rms do v[i] = env.rms[i] end
  table.sort(v)
  return v[math.max(1, math.floor(#v * 0.10))] or -90
end

-- Click forti: sale >15 dB in 5 ms, ricade >12 dB entro 40 ms, picco >= click_db.
-- A gruppo (entro 1,5 s) = un segnale { s=, e=, n=quanti }.
function M.find_clicks(env, click_db)
  click_db = click_db or -12
  local pk, hits = env.pk, {}
  for k = 9, #pk - 10 do
    local p = pk[k]
    if p >= click_db then
      local pre, post, top = -200, -200, true
      for j = k - 8, k - 2 do if pk[j] > pre then pre = pk[j] end end
      for j = k + 6, k + 9 do if pk[j] > post then post = pk[j] end end
      for j = k - 2, k + 2 do if pk[j] > p then top = false end end
      if top and p - pre > 15 and p - post > 12 then hits[#hits + 1] = (k - 1) * env.hop end
    end
  end
  local groups = {}
  for _, t in ipairs(hits) do
    local g = groups[#groups]
    if g and t - g.e <= 1.5 then g.e = t + 0.05; g.n = g.n + 1
    else groups[#groups + 1] = { s = t, e = t + 0.05, n = 1 } end
  end
  return groups
end

-- Attacco vero vicino a t (Whisper anticipa 70-75 ms): primo salto netto di energia in [t-0.12, t+0.25].
function M.attack(env, t)
  local hop = env.hop
  local k0 = math.max(1, math.floor((t - 0.12) / hop) + 1)
  local k1 = math.min(#env.pk, math.floor((t + 0.25) / hop) + 1)
  local top = -200
  for k = k0, k1 do if env.pk[k] > top then top = env.pk[k] end end
  for k = k0 + 1, k1 do
    if env.pk[k] >= top - 20 and env.pk[k] - env.pk[k - 1] > 6 then
      return math.max(0, (k - 1) * hop - 0.004)
    end
  end
  return t
end

M.STIRATA = 2.0   -- secondi: una parola piu' lunga e' stirata da Whisper sopra cio' che non ha capito

-- Tratti con voce (rms sopra fondo+12 dB) non coperti da parole affidabili: da ritrascrivere.
-- Una parola che dura piu' di M.STIRATA non e' affidabile (Whisper la stira sopra cio' che non capisce).
-- I segnali (click) spezzano i frammenti: mai un frammento a cavallo di un click.
function M.fragments_needed(env, words, signals, opts)
  opts = opts or {}
  local thr = (opts.floor or M.floor_db(env)) + 12
  local covered = {}
  local hop = env.hop
  for _, w in ipairs(words) do
    if w.e - w.s <= M.STIRATA then
      for k = math.max(1, math.floor((w.s - 0.15) / hop) + 1), math.min(#env.rms, math.floor((w.e + 0.15) / hop) + 1) do covered[k] = true end
    end
  end
  for _, g in ipairs(signals or {}) do
    for k = math.max(1, math.floor((g.s - 0.05) / hop) + 1), math.min(#env.rms, math.floor((g.e + 0.05) / hop) + 1) do covered[k] = "sig" end
  end
  local out, cur, quiet = {}, nil, 0
  for k = 1, #env.rms do
    local voiced = env.rms[k] > thr and not covered[k]
    if voiced then
      if not cur then cur = { s = (k - 1) * hop, e = k * hop, voiced = 0 } end
      cur.e = k * hop; cur.voiced = cur.voiced + hop; quiet = 0
    elseif cur then
      quiet = quiet + hop
      if quiet > 0.4 or covered[k] == "sig" then
        if cur.voiced >= (opts.min_voice or 0.5) then out[#out + 1] = cur end
        cur, quiet = nil, 0
      end
    end
  end
  if cur and cur.voiced >= (opts.min_voice or 0.5) then out[#out + 1] = cur end
  for _, f in ipairs(out) do f.s = math.max(0, f.s - 0.3); f.e = f.e + 0.3 end
  -- non attraversare un segnale
  for _, f in ipairs(out) do
    for _, g in ipairs(signals or {}) do
      if g.s > f.s and g.s < f.e then if g.s - f.s > f.e - g.e then f.e = g.s else f.s = g.e end end
    end
  end
  return out
end

-- Completa le parole con quelle del frammento ritrascritto (gia' con offset): le parole affidabili
-- restano, quelle del frammento riempiono solo i buchi. Le parole stirate (> M.STIRATA) che toccano il
-- tratto vengono tolte (il frammento le rimpiazza).
function M.merge_fragment(words, frag_words, f)
  if #frag_words == 0 then return words end
  local out = {}
  for _, w in ipairs(words) do
    local stretched = (w.e - w.s > M.STIRATA) and w.e > f.s and w.s < f.e
    if not stretched then out[#out + 1] = w end
  end
  local base = #out
  for _, w in ipairs(frag_words) do
    local clash = false
    for i = 1, base do
      local o = out[i]
      local ov = math.min(o.e, w.e) - math.max(o.s, w.s)
      if ov > 0.5 * math.min(o.e - o.s, w.e - w.s) then clash = true; break end
    end
    if not clash then out[#out + 1] = w end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end

---------------------------------------------------------------------------
-- Il piano (Fase 1, struttura)
---------------------------------------------------------------------------
-- in: { words, env (facoltativo), frasi (copione, facoltativo), signals (click), dict, segnale="click|parole|entrambi",
--       len = durata sorgente }
-- out: { keep = { {s,e} }, alt = { {s,e,k,dopo=s} }, tokens (con .stato), interventi = {...}, omesse = {k...}, letture }
-- stato di ogni gettone: "testo" | "fuori" | "comando" | "rifatto" | "superato" | "alt"
function M.plan(inp)
  local words, env, frasi = inp.words or {}, inp.env, inp.frasi or {}
  local toks = M.token_list(words)
  local segnale = inp.segnale or "entrambi"
  local att = function(t) return env and M.attack(env, t) or t end
  local letture = (#frasi > 0) and M.align(frasi, toks) or {}
  local in_text, owner = {}, {}
  for li, l in ipairs(letture) do
    for _, ti in pairs(l.pairs) do in_text[ti] = true end
    for i = l.i1, l.i2 do owner[i] = li end
  end
  -- senza copione: tutto e' testo (si lavora solo sui comandi e sui segnali)
  local has_text = #frasi > 0
  local cmds = M.find_commands(toks, inp.dict, has_text and in_text or {})
  local stato = {}
  for i = 1, #toks do stato[i] = (has_text and not owner[i]) and "fuori" or "testo" end
  local interventi = {}
  local function add(iv) interventi[#interventi + 1] = iv; return iv end

  -- segnali di rifacimento in ordine di tempo
  local sig = {}
  if segnale ~= "parole" then
    for _, g in ipairs(inp.signals or {}) do sig[#sig + 1] = { s = g.s, e = g.e, tipo = "click", n = g.n } end
  end
  for _, c in ipairs(cmds) do
    for i = c.i1, c.i2 do stato[i] = "comando" end
    local t1, t2 = toks[c.i1].s, toks[c.i2].e
    if c.azione == "rifai" and segnale ~= "click" then
      sig[#sig + 1] = { s = t1, e = t2, tipo = "parola", testo = words[toks[c.i1].w].text }
    end
    add({ tipo = "comando", azione = c.azione, s = t1, e = t2, n = c.n, i1 = c.i1, i2 = c.i2,
          testo = (function() local x = {}; for i = c.i1, c.i2 do x[#x + 1] = toks[i].t end; return table.concat(x, " ") end)(),
          sicurezza = "alta" })
  end
  table.sort(sig, function(a, b) return a.s < b.s end)

  -- tagli (source): { {s, e, perche} }
  -- Rifacimento: le prime parole dopo il segnale ("Il 30 e ...") si cercano all'indietro, entro
  -- 40 s, prima del segnale: da li' (attacco della prima versione) all'attacco della seconda si toglie.
  -- Non serve il copione: basta che la ripresa ripeta le stesse parole.
  local function is_cmd(i) return stato[i] == "comando" end
  local function same_run(j, after, n)
    local hit = 0
    for q = 0, n - 1 do
      local a, b = toks[j + q], toks[after + q]
      if not a or not b then break end
      if simili(a.t, b.t) then hit = hit + 1 elseif q == 0 then return 0 end
    end
    return hit
  end
  local cuts = {}
  for _, g in ipairs(sig) do
    local after
    for i = 1, #toks do if toks[i].s >= g.e - 0.01 and not is_cmd(i) then after = i; break end end
    local cut
    if after then
      local n = math.min(3, #toks - after + 1)
      local need = math.min(n, 2)
      local before
      for j = after - 1, 1, -1 do
        if toks[j].e < g.s - 40 then break end
        if toks[j].e <= g.s + 0.01 and not is_cmd(j) and same_run(j, after, n) >= need then before = j; break end
      end
      if before then
        cut = { s = att(toks[before].s), e = att(toks[after].s), i1 = before, i2 = after - 1, segnale = g, sicurezza = "alta" }
      else
        -- la ripresa non ripete parole di prima: si toglie dall'inizio della frase interrotta
        local j = after - 1
        while j > 1 and (toks[j].s > g.s or is_cmd(j)) do j = j - 1 end
        local k = j
        while k > 1 and toks[k].s - toks[k - 1].e < 0.35 do k = k - 1 end
        cut = { s = att(toks[k].s), e = att(toks[after].s), i1 = k, i2 = after - 1, segnale = g, sicurezza = "bassa" }
      end
    end
    if cut and cut.e > cut.s then
      cuts[#cuts + 1] = cut
      for i = cut.i1, cut.i2 do if stato[i] ~= "comando" then stato[i] = "rifatto" end end
      add({ tipo = "rifacimento", s = cut.s, e = cut.e, segnale = g.tipo, sicurezza = cut.sicurezza,
            testo = g.testo or (g.n and (g.n .. " click")), i1 = cut.i1, i2 = cut.i2, cut = cut })
    elseif g.tipo == "click" then
      add({ tipo = "click_solo", s = g.s, e = g.e, sicurezza = "bassa" })
    end
  end

  -- alternative: le letture dopo un comando "alternativa", fino al prossimo comando o pausa > 2,5 s
  local alt_of = {}
  for ci, c in ipairs(cmds) do
    if c.azione == "alternativa" then
      local stop = cmds[ci + 1] and toks[cmds[ci + 1].i1].s or math.huge
      local last_e = toks[c.i2].e
      for li, l in ipairs(letture) do
        if l.i1 > c.i2 and toks[l.i1].s < stop then
          if toks[l.i1].s - last_e > 2.5 then break end
          alt_of[li] = true; last_e = toks[l.i2].e
        end
      end
    end
  end

  -- vince l'ultima completa (escluse alternative e letture tagliate dai rifacimenti)
  local omesse, kept_by_k = {}, {}
  local function lettura_viva(li)
    local l = letture[li]
    for _, ti in pairs(l.pairs) do if stato[ti] == "testo" then return true end end
    return false
  end
  for k = 1, #frasi do
    local cands = {}
    for li, l in ipairs(letture) do if l.k == k and not alt_of[li] and lettura_viva(li) then cands[#cands + 1] = li end end
    if #cands == 0 then
      omesse[#omesse + 1] = k
      add({ tipo = "omessa", k = k, testo = frasi[k].text, sicurezza = "alta" })
    else
      local pick = cands[#cands]
      for c = #cands, 1, -1 do if letture[cands[c]].cover >= 0.8 then pick = cands[c]; break end end
      kept_by_k[k] = pick
      for _, li in ipairs(cands) do
        if li ~= pick then
          local l = letture[li]
          for i = l.i1, l.i2 do if stato[i] == "testo" then stato[i] = "superato" end end
          add({ tipo = "superata", k = k, s = toks[l.i1].s, e = toks[l.i2].e, li = li, sicurezza = "media", i1 = l.i1, i2 = l.i2 })
        end
      end
    end
  end
  local alt = {}
  for li in pairs(alt_of) do
    local l = letture[li]
    for i = l.i1, l.i2 do stato[i] = "alt" end
    local main = kept_by_k[l.k]
    local a = { s = att(toks[l.i1].s), e = toks[l.i2].e + 0.15, k = l.k,
                sotto = main and att(toks[letture[main].i1].s) or nil }
    alt[#alt + 1] = a
    add({ tipo = "alternativa", k = l.k, s = toks[l.i1].s, e = toks[l.i2].e, sicurezza = "alta", i1 = l.i1, i2 = l.i2, altref = a })
  end
  table.sort(alt, function(a, b) return a.s < b.s end)

  -- fuori testo e superati: un intervento per tratto (per la revisione)
  local run
  for i = 1, #toks + 1 do
    local st = stato[i]
    if st == "fuori" then
      if run then run.e = toks[i].e; run.i2 = i else run = { tipo = "fuori", s = toks[i].s, e = toks[i].e, i1 = i, i2 = i, sicurezza = "media" } end
    elseif run then
      local x = {}; for j = run.i1, run.i2 do x[#x + 1] = words[toks[j].w].text end
      run.testo = table.concat(x, " "):gsub("(%S+) %1", "%1")
      add(run); run = nil
    end
  end
  table.sort(interventi, function(a, b) return (a.s or -1) < (b.s or -1) end)
  for n, iv in ipairs(interventi) do
    iv.id = n
    if iv.i1 then iv.stati = {}; for i = iv.i1, iv.i2 do iv.stati[i] = stato[i] end end
  end
  local p = { alt = alt, toks = toks, stato = stato, words = words, letture = letture, frasi = frasi,
              interventi = interventi, omesse = omesse, cuts = cuts, comandi = cmds, env = env, len = inp.len }
  M.compute_keep(p)
  return p
end

-- Intervalli da tenere dai gettoni "testo"; tra due gruppi separati da materiale tolto si tiene un
-- po' di coda e di pausa prima dell'attacco (0,35 s max ciascuna): sgrossatura, il fino in Timeline.
-- Un rifacimento attivo si attacca esattamente: inizio su inizio.
function M.compute_keep(p)
  local toks, stato, env = p.toks, p.stato, p.env
  local att = function(t) return env and M.attack(env, t) or t end
  local cuts = {}
  for _, c in ipairs(p.cuts) do if not c.off then cuts[#cuts + 1] = c end end
  local groups, g = {}, nil
  for i = 1, #toks do
    if stato[i] == "testo" then
      if g and g.last == i - 1 then g.last = i; g.e = toks[i].e
      else g = { first = i, last = i, s = toks[i].s, e = toks[i].e }; groups[#groups + 1] = g end
    end
  end
  local keep = {}
  for gi, gr in ipairs(groups) do
    local s = att(gr.s)
    local prev_end = gi > 1 and groups[gi - 1].e or 0
    local pre = math.min(0.35, math.max(0, s - prev_end) * 0.5)
    for _, c in ipairs(cuts) do if math.abs(c.e - s) < 0.02 then pre = 0 end end
    local nxt = groups[gi + 1]
    local post_room = nxt and (att(nxt.s) - gr.e) or 0.6
    local post = math.min(0.35, math.max(0, post_room) * 0.5)
    for _, c in ipairs(cuts) do if c.s >= gr.e - 0.01 and c.s - gr.e < 0.6 then post = math.max(0, c.s - gr.e) end end
    local ks, ke = math.max(0, s - pre), gr.e + post
    if p.len then ke = math.min(ke, p.len) end
    local last = keep[#keep]
    if last and ks <= last.e + 0.005 then last.e = math.max(last.e, ke) else keep[#keep + 1] = { s = ks, e = ke } end
  end
  p.keep = keep
  return keep
end

-- Cambiare idea su un intervento: "tieni" rimette il materiale nel montato (o toglie l'alternativa).
function M.set_tieni(p, iv, tieni)
  iv.tieni = tieni and true or nil
  if iv.i1 then
    for i = iv.i1, iv.i2 do
      if tieni then
        if iv.tipo == "alternativa" then p.stato[i] = "fuori" elseif p.stato[i] ~= "comando" or iv.tipo == "comando" then p.stato[i] = "testo" end
      else p.stato[i] = iv.stati[i] end
    end
  end
  if iv.cut then iv.cut.off = tieni and true or nil end
  if iv.tipo == "alternativa" and iv.altref then iv.altref.off = tieni and true or nil end
  M.compute_keep(p)
end

-- Ripresa di un piano in testo (per controlli e note): "12.34-15.00 tieni" ...
function M.describe(p)
  local out = {}
  for _, k in ipairs(p.keep) do out[#out + 1] = string.format("TIENI %.3f-%.3f", k.s, k.e) end
  for _, a in ipairs(p.alt) do if not a.off then out[#out + 1] = string.format("ALT   %.3f-%.3f (frase %d)", a.s, a.e, a.k) end end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- WAV: lettura a blocchi (PCM 16/24/32, float 32, RIFF/RF64) e frammenti per la ritrascrizione
---------------------------------------------------------------------------
function M.wav_open(path)
  local f = io.open(path, "rb"); if not f then return nil, "non apro " .. tostring(path) end
  local head = f:read(12)
  if not head or #head < 12 then f:close(); return nil, "file corto" end
  local riff = head:sub(1, 4)
  if (riff ~= "RIFF" and riff ~= "RF64") or head:sub(9, 12) ~= "WAVE" then f:close(); return nil, "non e' un WAV" end
  local info, ds64_data = { path = path }, nil
  while true do
    local ch = f:read(8); if not ch or #ch < 8 then break end
    local id, size = ch:sub(1, 4), string.unpack("<I4", ch, 5)
    if id == "ds64" then
      local body = f:read(size); ds64_data = string.unpack("<I8", body, 9)
      if size % 2 == 1 then f:read(1) end
    elseif id == "fmt " then
      local body = f:read(size)
      info.format, info.channels, info.sr = string.unpack("<I2I2I4", body)
      info.block, info.bits = string.unpack("<I2I2", body, 13)
      if info.format == 0xFFFE and #body >= 26 then info.format = string.unpack("<I2", body, 25) end
      info.fmt_body = body
      if size % 2 == 1 then f:read(1) end
    elseif id == "data" then
      info.data_off = f:seek()
      info.data_len = (size == 0xFFFFFFFF and ds64_data) or size
      break
    else
      f:seek("cur", size + (size % 2))
    end
  end
  if not info.data_off or not info.sr then f:close(); return nil, "WAV senza fmt/data" end
  local fs = f:seek("end")
  info.data_len = math.min(info.data_len, fs - info.data_off)
  info.frames = info.data_len // info.block
  info.len = info.frames / info.sr
  info.f = f
  f:seek("set", info.data_off)
  local bps = info.bits // 8
  if info.format == 3 and info.bits == 32 then info.fmtc = "<f"; info.scale = 1
  elseif bps == 2 then info.fmtc = "<i2"; info.scale = 1 / 32768
  elseif bps == 3 then info.fmtc = "<i3"; info.scale = 1 / 8388608
  elseif bps == 4 then info.fmtc = "<i4"; info.scale = 1 / 2147483648
  else f:close(); return nil, "formato non gestito (" .. tostring(info.bits) .. " bit)" end
  info.bps = bps
  return info
end

-- Legge fino a max_frames frame e li manda all'accumulatore env. Restituisce i frame letti (0 = finito).
function M.wav_read_env(info, env, max_frames)
  local want = math.min(max_frames, info.frames - (info.pos or 0))
  if want <= 0 then return 0 end
  local data = info.f:read(want * info.block)
  if not data then return 0 end
  local got = #data // info.block
  local ch, bps, fmtc, sc = info.channels, info.bps, info.fmtc, info.scale
  local unpack, add = string.unpack, M.env_add
  local p = 1
  for _ = 1, got do
    local best = 0
    for _ = 1, ch do
      local v = unpack(fmtc, data, p) * sc; p = p + bps
      if (v < 0 and -v or v) > (best < 0 and -best or best) then best = v end
    end
    add(env, best)
  end
  info.pos = (info.pos or 0) + got
  return got
end

function M.wav_close(info) if info and info.f then info.f:close(); info.f = nil end end

-- Scrive il tratto [t0, t1] del WAV come WAV PCM semplice (per ritrascrivere un frammento).
function M.wav_fragment(src_path, dst_path, t0, t1)
  local info, err = M.wav_open(src_path)
  if not info then return false, err end
  local f0 = math.max(0, math.floor(t0 * info.sr))
  local f1 = math.min(info.frames, math.floor(t1 * info.sr))
  if f1 <= f0 then M.wav_close(info); return false, "tratto vuoto" end
  info.f:seek("set", info.data_off + f0 * info.block)
  local data = info.f:read((f1 - f0) * info.block)
  M.wav_close(info)
  local fmt = info.fmt_body
  local out = io.open(dst_path, "wb"); if not out then return false, "non scrivo " .. dst_path end
  out:write("RIFF", string.pack("<I4", 4 + 8 + #fmt + (#fmt % 2) + 8 + #data), "WAVE")
  out:write("fmt ", string.pack("<I4", #fmt), fmt, (#fmt % 2 == 1) and "\0" or "")
  out:write("data", string.pack("<I4", #data), data)
  out:close()
  return true
end

return M
