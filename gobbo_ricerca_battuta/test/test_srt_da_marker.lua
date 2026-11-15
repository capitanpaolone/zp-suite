-- Test della logica pura di 31_SRT_da_Marker_Audio.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/31_SRT_da_Marker_Audio.lua")
local P = dofile("ZP Studio Suite/28_Collega_Marker.lua")   -- parser SRT del 28, per il giro completo
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
check("formato tempo", M.time(0) == "00:00:00,000" and M.time(3725.0405) == "01:02:05,041")
local c = M.cues({ { src = 5, text = "B" }, { src = 1.5, text = " A " }, { src = 9, text = "C" } }, 12)
check("ordinate per tempo, testo ripulito", #c == 3 and c[1].text == "A" and c[1].start == 1.5)
check("fine = inizio della successiva", c[1].stop == 5 and c[2].stop == 9)
check("ultima: fino alla fine del file (12 s)", c[3].stop == 12)
c = M.cues({ { src = 1, text = "A" } }, 100)
check("ultima: massimo 8 s", c[1].stop == 9)
c = M.cues({ { src = 1, text = "A" }, { src = 1.0004, text = "A copia" }, { src = 2, text = "" } }, 10)
check("stesso punto da due pezzi: una battuta; vuoti ignorati", #c == 1)
c = M.cues({ { src = 1, text = "A" }, { src = 1.1, text = "B" } }, 10)
check("durata minima 0,3 s", math.abs(c[1].stop - 1.3) < 1e-9)
-- giro completo: marker -> SRT -> parser del 28 -> stessi tempi e testi
local orig = { { src = 0.52, text = "Prima battuta" }, { src = 48.3, text = "Seconda, con virgola" }, { src = 193.21, text = "Ultima" } }
local back = P.parse_srt(M.srt(M.cues(orig, 209)))
local same = #back == 3
for i, b in ipairs(back) do same = same and math.abs(b.start - orig[i].src) < 0.001 and b.text == orig[i].text end
check("giro completo con il parser del 28: identico", same)
do
  local cues = M.cues({ { src = 1, text = "Uno" }, { src = 2, text = "BAD_001" }, { src = 3, text = "#nota" }, { src = 4, text = "Due" } }, 10)
  check("servizio: segnaposto e marker SOLO esclusi dall'SRT", #cues == 2 and cues[1].text == "Uno" and cues[2].text == "Due")
end
-- Durata sul marker (REAPER 7.86): la fine e' quella scritta, non l'inizio della battuta dopo
c = M.cues({ { src = 1, text = "A", len = 1.5 }, { src = 5, text = "B", len = 0 }, { src = 9, text = "C" } }, 12)
check("marker con durata: fine vera", c[1].stop == 2.5)
check("marker senza durata: fine stimata come prima", c[2].stop == 9 and c[3].stop == 12)
c = M.cues({ { src = 1, text = "A", len = 0.05 } }, 12)
check("durata minima anche con la durata scritta", math.abs(c[1].stop - 1.3) < 1e-9)
do
  local parsed = P.parse_srt("1\n00:00:01,000 --> 00:00:02,500\nUno\n\n2\n00:00:05,000 --> 00:00:04,000\nDue\n")
  check("il 28 legge anche la fine della battuta", parsed[1].stop == 2.5 and parsed[2].stop == nil and parsed[2].start == 5)
  -- giro completo con le durate: SRT -> marker con durata -> SRT identico
  local src = "1\n00:00:01,000 --> 00:00:02,500\nUno\n\n2\n00:00:05,000 --> 00:00:07,250\nDue\n"
  local markers = {}
  for i, cue in ipairs(P.parse_srt(src)) do markers[i] = { src = cue.start, text = cue.text, len = cue.stop - cue.start } end
  check("SRT -> marker con durata -> SRT: identico", M.srt(M.cues(markers, 60)) == src)
end
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
