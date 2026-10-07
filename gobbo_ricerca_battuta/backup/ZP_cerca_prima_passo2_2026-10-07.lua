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

local function fold_data(s)
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
    local v = fold_map[value] or value:lower()
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

function M.fold(s) return (fold_data(s)) end

local function decode_query(q)
  q = tostring(q or "")
  if q:sub(1,3) == "“" and q:sub(-3) == "”" then return q:sub(4,-4), true end
  if #q >= 2 and q:sub(1,1) == '"' and q:sub(-1) == '"' then return q:sub(2,-2), true end
  return q, false
end

function M.find(text, query)
  local raw, exact = decode_query(query)
  local needle = M.fold(raw)
  if needle == "" then return nil end
  local hay, starts, ends, _, starts_word, ends_word = fold_data(text)
  local from = 1
  while true do
    local a,b = hay:find(needle, from, true)
    if not a then return nil end
    local os, oe = starts[a], ends[b]
    local ok = exact and starts_word[os] and ends_word[oe]
      or (not exact and starts_word[os])
    if ok then return os, oe end
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

function M.word_matches(word, query)
  return M.find(word, query) ~= nil
end

if not reaper then return M end
return M
