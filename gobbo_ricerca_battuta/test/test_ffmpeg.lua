-- ZP Remote: ricerca di FFmpeg (modulo condiviso) e coerenza con zp_remote_esporta.py
local FF = dofile("ZP Studio Suite/remote/zp_ffmpeg.lua")
local fail = 0
local function check(nome, cond) if not cond then print("FALLITO: " .. nome); fail = 1 end end
local function con(files) return function(p) return files[p] == true end end
check("niente FFmpeg", FF.resolve(con({}), "/usr/bin:/bin", "") == nil)
check("PATH ridotto del Finder: /usr/local/bin", FF.resolve(con({["/usr/local/bin/ffmpeg"]=true}), "/usr/bin:/bin:/usr/sbin:/sbin", "") == "/usr/local/bin/ffmpeg")
check("Homebrew Apple Silicon", FF.resolve(con({["/opt/homebrew/bin/ffmpeg"]=true}), "/usr/bin", nil) == "/opt/homebrew/bin/ffmpeg")
check("MacPorts", FF.resolve(con({["/opt/local/bin/ffmpeg"]=true}), "/usr/bin", nil) == "/opt/local/bin/ffmpeg")
check("PATH prima dei percorsi standard", FF.resolve(con({["/x/bin/ffmpeg"]=true, ["/usr/local/bin/ffmpeg"]=true}), "/x/bin/", nil) == "/x/bin/ffmpeg")
local p, da = FF.resolve(con({["/Users/a b/ffmpeg"]=true, ["/usr/local/bin/ffmpeg"]=true}), "/usr/bin", "/Users/a b/ffmpeg")
check("scelta dell'utente prima di tutto", p == "/Users/a b/ffmpeg" and da == "scelto")
check("scelta sparita: si torna ai percorsi", FF.resolve(con({["/usr/local/bin/ffmpeg"]=true}), "", "/sparito/ffmpeg") == "/usr/local/bin/ffmpeg")
check("versione letta", FF.parse_version("0\nffmpeg version 9.1-tessus Copyright (c)") == "9.1-tessus")
local v, err = FF.parse_version("1\nBad CPU type in executable")
check("binario che non parte", v == nil and err:find("Bad CPU", 1, true))
-- stesso ordine nell'esportatore Python
local py = io.open("ZP Studio Suite/remote/zp_remote_esporta.py"):read("a")
local lista = py:match("FFMPEG_CANDIDATI%s*=%s*%((.-)%)")
check("FFMPEG_CANDIDATI presente nell'esportatore", lista ~= nil)
local i = 0
for c in (lista or ""):gmatch('"([^"]+)"') do i = i + 1; check("candidato " .. i .. " uguale nei due file", FF.CANDIDATI[i] == c) end
check("stesso numero di candidati", i == #FF.CANDIDATI)
print(fail == 0 and "TUTTI OK" or "CI SONO ERRORI")
os.exit(fail == 0 and 0 or 1)
