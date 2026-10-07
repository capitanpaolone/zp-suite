-- @noindex
-- Ricerca pura condivisa dai Gobbi.
local M = {}

local fold_map = {
  ["à"]="a",["á"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",
  ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
  ["ò"]="o",["ó"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",
  ["ç"]="c",["ñ"]="n",
  ["À"]="a",["Á"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",
  ["È"]="e",["É"]="e",["Ê"]="e",["Ë"]="e",["Ì"]="i",["Í"]="i",["Î"]="i",["Ï"]="i",
  ["Ò"]="o",["Ó"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",["Ù"]="u",["Ú"]="u",["Û"]="u",["Ü"]="u",
  ["Ç"]="c",["Ñ"]="n",
}
local upper_map = {
  ["à"]="À",["á"]="Á",["â"]="Â",["ä"]="Ä",["ã"]="Ã",["å"]="Å",
  ["è"]="È",["é"]="É",["ê"]="Ê",["ë"]="Ë",["ì"]="Ì",["í"]="Í",["î"]="Î",["ï"]="Ï",
  ["ò"]="Ò",["ó"]="Ó",["ô"]="Ô",["ö"]="Ö",["õ"]="Õ",["ù"]="Ù",["ú"]="Ú",["û"]="Û",["ü"]="Ü",
  ["ç"]="Ç",["ñ"]="Ñ",
}
local lower_map = {}
for lower, upper in pairs(upper_map) do lower_map[upper] = lower end
local lower_upper = {}
for lower, upper in pairs(upper_map) do lower_upper[lower], lower_upper[upper] = true, true end

local function chars(s)
  local out, i = {}, 1
  while i <= #s do
    local b = s:byte(i)
    local n = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
    local c = s:sub(i, i+n-1)
    out[#out+1] = { value=c, first=i, last=i+n-1 }
    i = i+n
  end
  return out
end

local non_word = {
  ["’"]=true,["‘"]=true,["“"]=true,["”"]=true,["«"]=true,["»"]=true,["‹"]=true,["›"]=true,
  ["—"]=true,["–"]=true,["…"]=true,["·"]=true,["•"]=true,[" "]=true,
  ["、"]=true,["。"]=true,["，"]=true,["．"]=true,["！"]=true,["？"]=true,
  ["："]=true,["；"]=true,["（"]=true,["）"]=true,["［"]=true,["］"]=true,["｛"]=true,["｝"]=true,
}
for cp=0x2000,0x200B do non_word[utf8.char(cp)] = true end
non_word[utf8.char(0x3000)] = true

local function word_char(c)
  if not c or c == "" then return false end
  if c:match("^[%w_]$") then return true end
  if c:byte(1) >= 128 then return not non_word[c] end
  return false
end

-- keep_accents: solo minuscole (È->è), gli accenti contano: per Sostituisci
local function fold_data(s, keep_accents)
  s = tostring(s or "")
  local folded, starts, ends = {}, {}, {}
  local list, i = chars(s), 1
  while i <= #list do
    local ch = list[i]
    local value, last = ch.value, ch.last
    if value == "\r" then
      value = "\n"
      if list[i+1] and list[i+1].value == "\n" then last = list[i+1].last; i = i+1 end
    end
    local v = (keep_accents and lower_map[value]) or (not keep_accents and fold_map[value]) or value:lower()
    folded[#folded+1] = v
    for _ = 1, #v do starts[#starts+1], ends[#ends+1] = ch.first, last end
    i = i+1
  end
  local list, starts_word, ends_word = chars(s), {}, {}
  for i, ch in ipairs(list) do
    starts_word[ch.first] = not word_char(i > 1 and list[i-1].value or nil)
    ends_word[ch.last] = not word_char(list[i+1] and list[i+1].value or nil)
  end
  return table.concat(folded), starts, ends, s, starts_word, ends_word
end

function M.fold(s, keep_accents) return (fold_data(s, keep_accents)) end

local function decode_query(q)
  q = tostring(q or "")
  if q:sub(1,3) == "“" and q:sub(-3) == "”" then return q:sub(4,-4), true end
  if #q >= 2 and q:sub(1,1) == '"' and q:sub(-1) == '"' then return q:sub(2,-2), true end
  return q, false
end

-- mode "replace": parola intera e accenti che contano ("è" non trova "e" ne' "effetti").
-- Altrimenti ricerca: inizio parola, accenti e maiuscole ignorati, "..." = parola intera.
function M.find(text, query, from_original, mode)
  local raw, exact = decode_query(query)
  local keep = mode == "replace"
  if keep then exact = true end
  local needle = M.fold(raw, keep)
  if needle == "" then return nil end
  local hay, starts, ends, _, starts_word, ends_word = fold_data(text, keep)
  local from = 1
  while true do
    local a,b = hay:find(needle, from, true)
    if not a then return nil end
    local os, oe = starts[a], ends[b]
    local ok = exact and starts_word[os] and ends_word[oe]
      or (not exact and starts_word[os])
    if ok and os >= (from_original or 1) then return os, oe end
    from = a + 1
  end
end

function M.count(items, query, current_item, current_offset)
  local total, current = 0, nil
  local raw = decode_query(query)
  if M.fold(raw) == "" then return 0, nil end
  for _, item in ipairs(items or {}) do
    local text = type(item) == "table" and (item.notes or item.text or "") or item
    local offset = M.find(text, query)
    if offset then
      total = total + 1
      if item == current_item and (not current_offset or current_offset == offset) then current = total end
    end
  end
  return total, current
end

local function is_space(c)
  return c == " " or c == "\t" or c == "\n" or c == "\r" or c == " " or c == "　"
    or (c and c:byte(1) >= 0xE2 and c:byte(1) <= 0xE3 and c >= " " and c <= "​")
end

function M.results(items, query, max_results, mode)
  local out, total = {}, 0
  max_results = math.max(0, tonumber(max_results) or 500)
  local ordered = {}
  for i, item in ipairs(items or {}) do ordered[i] = {item=item, order=i} end
  table.sort(ordered, function(a,b)
    local ap,bp=a.item.pos or 0,b.item.pos or 0
    return ap==bp and a.order<b.order or ap<bp
  end)
  for _, entry in ipairs(ordered) do
    local item=entry.item
    local text = type(item) == "table" and (item.notes or item.text or "") or tostring(item or "")
    local a,b = M.find(text, query, nil, mode)
    if a then
      total = total + 1
      if #out < max_results then
        local list = chars(text)
        local first_i, last_i
        for i,ch in ipairs(list) do
          if ch.first == a then first_i = i end
          if ch.last == b then last_i = i; break end
        end
        first_i, last_i = first_i or 1, last_i or first_i or 1
        local left, right = math.max(1, first_i - 30), math.min(#list, last_i + 30)
        -- taglia sulle parole intere: a sinistra dopo il PRIMO spazio della finestra, a destra
        -- prima dell'ULTIMO (prima teneva solo la parola trovata: "…d'abete…")
        if left > 1 then
          for i = left, first_i - 2 do if is_space(list[i].value) then left = i + 1; break end end
        end
        if right < #list then
          for i = right, last_i + 2, -1 do if is_space(list[i].value) then right = i - 1; break end end
        end
        local start_byte = list[left] and list[left].first or 1
        local end_byte = list[right] and list[right].last or #text
        local prefix, suffix = left > 1 and "…" or "", right < #list and "…" or ""
        local snippet = prefix .. text:sub(start_byte, end_byte) .. suffix
        local snip_a = #prefix + a - start_byte + 1
        local snip_b = #prefix + b - start_byte + 1
        out[#out+1] = {item=item, offset_start=a, offset_end=b, snippet=snippet, snip_a=snip_a, snip_b=snip_b}
      end
    end
  end
  return out, total
end

local function uppercase(s)
  local out = {}
  for _, ch in ipairs(chars(s)) do out[#out+1] = upper_map[ch.value] or ch.value:upper() end
  return table.concat(out)
end

local function smart_case(original, replacement)
  if replacement == "" then return replacement end
  local all_upper, letters, first_letter_upper = true, 0, false
  for _, ch in ipairs(chars(original)) do
    local c = ch.value
    local upper = c:match("^[A-Z]$") ~= nil or lower_upper[c] and upper_map[c] == nil
    local lower = c:match("^[a-z]$") ~= nil or upper_map[c] ~= nil
    if upper or lower then
      if letters == 0 then first_letter_upper = upper end
      letters = letters + 1
      if not upper then all_upper = false end
    end
  end
  -- una sola maiuscola ("E", "È" a inizio frase) e' iniziale, non tutto maiuscolo
  if letters >= 2 and all_upper then return uppercase(replacement) end
  if first_letter_upper then
    local first = chars(replacement)[1]
    if first then return (upper_map[first.value] or first.value:upper()) .. replacement:sub(first.last + 1) end
  end
  return replacement
end

-- Sostituisce sempre parole intere, con gli accenti che contano (mode "replace").
function M.replace(text, query, replacement, all)
  text, replacement = tostring(text or ""), tostring(replacement or "")
  if M.fold(decode_query(query)) == "" then return text, 0 end
  local chunks, cursor, search_from, n = {}, 1, 1, 0
  while true do
    local a,b = M.find(text, query, search_from, "replace")
    if not a then break end
    chunks[#chunks+1] = text:sub(cursor, a-1)
    chunks[#chunks+1] = smart_case(text:sub(a,b), replacement)
    n, cursor, search_from = n+1, b+1, b+1
    if not all then break end
  end
  if n == 0 then return text, 0 end
  chunks[#chunks+1] = text:sub(cursor)
  return table.concat(chunks), n
end

function M.word_matches(word, query)
  return M.find(word, query) ~= nil
end

if not reaper then return M end
return M
