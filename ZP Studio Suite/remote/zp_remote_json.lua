-- @noindex

-- Strict JSON decoder for REAPER Lua. No eval/load and no external dependencies.
local M = {}
local NULL = {}
M.null = NULL

local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp/64), 0x80 + cp%64) end
  if cp < 0x10000 then return string.char(0xE0 + math.floor(cp/4096), 0x80 + math.floor(cp/64)%64, 0x80 + cp%64) end
  return string.char(0xF0 + math.floor(cp/262144), 0x80 + math.floor(cp/4096)%64, 0x80 + math.floor(cp/64)%64, 0x80 + cp%64)
end

function M.decode(src)
  assert(type(src) == "string", "JSON input deve essere testo")
  local i, n = 1, #src
  local function error_at(msg) error(("JSON non valido alla posizione %d: %s"):format(i, msg), 0) end
  local function ws() while i <= n and src:sub(i,i):match("[ \t\r\n]") do i=i+1 end end
  local parse_value
  local function parse_string()
    if src:sub(i,i) ~= '"' then error_at("attesa stringa") end
    i=i+1; local out={}; local start=i
    while i <= n do
      local b=src:byte(i)
      if b == 34 then out[#out+1]=src:sub(start,i-1); i=i+1; return table.concat(out) end
      if b < 32 then error_at("carattere di controllo nella stringa") end
      if b == 92 then
        out[#out+1]=src:sub(start,i-1); i=i+1
        local e=src:sub(i,i); local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if map[e] then out[#out+1]=map[e]; i=i+1
        elseif e == 'u' then
          local hex=src:sub(i+1,i+4); if not hex:match('^%x%x%x%x$') then error_at("escape Unicode incompleto") end
          local cp=tonumber(hex,16); i=i+5
          if cp >= 0xD800 and cp <= 0xDBFF then
            if src:sub(i,i+1) ~= '\\u' then error_at("surrogato alto senza coppia") end
            local low=src:sub(i+2,i+5); if not low:match('^%x%x%x%x$') then error_at("surrogato basso non valido") end
            local l=tonumber(low,16); if l < 0xDC00 or l > 0xDFFF then error_at("surrogato basso non valido") end
            cp=0x10000+(cp-0xD800)*0x400+(l-0xDC00); i=i+6
          elseif cp >= 0xDC00 and cp <= 0xDFFF then error_at("surrogato basso isolato") end
          out[#out+1]=utf8(cp)
        else error_at("escape non valido") end
        start=i
      else i=i+1 end
    end
    error_at("stringa non terminata")
  end
  local function parse_number()
    local s=i
    if src:sub(i,i)=='-' then i=i+1 end
    if src:sub(i,i)=='0' then i=i+1 else
      if not src:sub(i,i):match('[1-9]') then error_at("numero non valido") end
      repeat i=i+1 until i>n or not src:sub(i,i):match('%d')
    end
    if src:sub(i,i)=='.' then i=i+1; if not src:sub(i,i):match('%d') then error_at("decimali incompleti") end; repeat i=i+1 until i>n or not src:sub(i,i):match('%d') end
    if src:sub(i,i):match('[eE]') then i=i+1; if src:sub(i,i):match('[+-]') then i=i+1 end; if not src:sub(i,i):match('%d') then error_at("esponente incompleto") end; repeat i=i+1 until i>n or not src:sub(i,i):match('%d') end
    local v=tonumber(src:sub(s,i-1)); if not v or v ~= v or v == math.huge or v == -math.huge then error_at("numero fuori intervallo") end
    return v
  end
  local function parse_array()
    i=i+1; ws(); local a={}; if src:sub(i,i)==']' then i=i+1; return a end
    while true do a[#a+1]=parse_value(); ws(); local c=src:sub(i,i); if c==']' then i=i+1; return a elseif c~=',' then error_at("attesa , o ]") end; i=i+1; ws() end
  end
  local function parse_object()
    i=i+1; ws(); local o={}; if src:sub(i,i)=='}' then i=i+1; return o end
    while true do
      if src:sub(i,i)~='"' then error_at("chiave oggetto non stringa") end
      local k=parse_string(); if o[k] ~= nil then error_at("chiave duplicata: "..k) end
      ws(); if src:sub(i,i)~=':' then error_at("atteso :") end; i=i+1; ws(); o[k]=parse_value(); ws()
      local c=src:sub(i,i); if c=='}' then i=i+1; return o elseif c~=',' then error_at("attesa , o }") end; i=i+1; ws()
    end
  end
  parse_value=function()
    ws(); local c=src:sub(i,i)
    if c=='"' then return parse_string() elseif c=='{' then return parse_object() elseif c=='[' then return parse_array()
    elseif c=='-' or c:match('%d') then return parse_number()
    elseif src:sub(i,i+3)=='true' then i=i+4; return true
    elseif src:sub(i,i+4)=='false' then i=i+5; return false
    elseif src:sub(i,i+3)=='null' then i=i+4; return NULL end
    error_at("valore non valido")
  end
  local value=parse_value(); ws(); if i<=n then error_at("contenuto dopo il valore finale") end
  return value
end
return M
