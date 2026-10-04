-- Test della logica pura di 29_ZP_Trascrizione.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/29_ZP_Trascrizione.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
local rows = {
  { path = "/a/nuovo.wav", wav = true, srt = false, markers = 0, texts = 0 },
  { path = "/a/glued-01.wav", wav = true, srt = false, markers = 12, texts = 12 },   -- glue: marker, niente SRT
  { path = "/a/glued-01.wav", wav = true, srt = false, markers = 3, texts = 3 },    -- stesso file, altro item
  { path = "/a/fatto.wav", wav = true, srt = true, markers = 0, texts = 0 },
  { path = "/a/clip.mp3", wav = false, srt = false, markers = 0, texts = 0 },
}
local q = M.to_transcribe(rows)
check("Trascrivi: solo il WAV senza SRT e senza marker", #q == 1 and q[1] == "/a/nuovo.wav")
local r, nm, ns = M.to_retranscribe(rows)
check("Ritrascrivi: tutti i WAV, ogni file una volta", #r == 3 and r[2] == "/a/glued-01.wav")
check("Ritrascrivi: conta gli item con marker (2) e i file con SRT (1)", nm == 2 and ns == 1)
local steps = M.road({ rows[2] }, false)
check("file glued con marker: tappa 1 risulta fatta (il pulsante diventa Ritrascrivi)", steps[1].done)
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
