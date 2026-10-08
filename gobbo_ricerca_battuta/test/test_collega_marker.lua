-- Test della scelta per item di 28_Collega_Marker.lua (Abbina da > SRT accanto). Lancio dalla radice del repo.
local C = dofile("ZP Studio Suite/28_Collega_Marker.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end

-- decide(existing, has_srt, skip_existing, quiet)
check("item nuovo con SRT accanto: abbina", C.decide(0, true, false, true) == "link")
check("dalla strada, file glued (marker, niente SRT): niente Finder, resta com'e'",
  C.decide(12, false, false, true) == "skip_linked")
check("dalla strada, niente marker e niente SRT: elencato, niente Finder", C.decide(0, false, false, true) == "missing")
check("Percorri la strada: item gia' collegato saltato senza cercare l'SRT", C.decide(5, false, true, true) == "skip_linked")
check("marker + SRT accanto: chiede se sostituire", C.decide(5, true, false, true) == "ask_replace")
check("28 lanciato da solo: senza SRT chiede il file come prima", C.decide(0, false, false, false) == "ask_file")

check("elenco nomi: ogni file una volta",
  C.name_list({ "a.wav", "a.wav", "b.wav" }) == "a.wav, b.wav")
check("elenco nomi: oltre 3 dice quanti altri",
  C.name_list({ "a", "b", "c", "d", "e" }) == "a, b, c e altri 2")

print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
