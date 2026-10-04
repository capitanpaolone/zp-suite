#!/bin/bash
# Verifica anti-regressione della ZP Suite. Lancio dalla radice del repo:
#   bash gobbo_ricerca_battuta/test/run_all.sh
# Fa in locale quello che altrimenti scopri dopo il push (GitHub "check") o in REAPER.
cd "$(dirname "$0")/../.." || exit 1
fail=0
say() { printf '%s\n' "$*"; }

say "== 1. Sintassi Lua (luac -p)"
n=0
while IFS= read -r f; do
  n=$((n+1))
  luac -p -o /dev/null "$f" 2>/dev/null || { say "ERRORE sintassi: $f"; luac -p -o /dev/null "$f"; fail=1; }
done < <(git ls-files '*.lua' | grep -v '/backup/')
say "   $n file"

say "== 2. ReaPack: ogni script/effetto dei pacchetti ha @version, @noindex o sta in un @provides"
provided=$(git ls-files '*.lua' '*.jsfx' | grep -v '^gobbo_ricerca_battuta/' | xargs grep -h -A400 '@provides' 2>/dev/null \
  | sed -nE 's/^(--|\/\/)[[:space:]]+(\[[a-z]+\][[:space:]]+)?([^>]+[^[:space:]>]).*/\3/p')
while IFS= read -r f; do
  head -c 4000 "$f" | grep -qE '@(version|noindex)' && continue
  name=$(basename "$f")
  printf '%s\n' "$provided" | grep -qxF "$name" && continue
  say "MANCA @version/@noindex: $f"; fail=1
done < <(git ls-files '*.lua' '*.jsfx' | grep -vE '^(gobbo_ricerca_battuta|speech-engine|ZP Lab|docs)/')

say "== 2b. Ogni file elencato nel @provides della ZP Studio Suite esiste"
( cd "ZP Studio Suite" && awk '/@provides/{f=1;next} f&&/^-- @/{f=0} f&&/^--   /{print}' 00_Apri_Help_ZP_Studio_Suite.lua \
  | sed -E 's/^--   (\[[a-z]+\] )?//; s/ > .*//' | while IFS= read -r p; do [ -e "$p" ] || echo "MANCA nel repo: $p"; done ) > /tmp/zp_provides_$$.txt
if [ -s /tmp/zp_provides_$$.txt ]; then cat /tmp/zp_provides_$$.txt; fail=1; fi
rm -f /tmp/zp_provides_$$.txt

say "== 3. JSFX: niente notazione scientifica (EEL2 non la accetta, es. 1e-30)"
while IFS= read -r f; do
  grep -nE '^[^/]*[0-9]e[-+]?[0-9]' "$f" | grep -vE '^\s*[0-9]+:\s*//' && { say "   ^ in $f"; fail=1; }
done < <(git ls-files '*.jsfx')

say "== 4. Test della logica pura"
for t in gobbo_ricerca_battuta/test/*.lua; do
  out=$(lua "$t" 2>&1); last=$(printf '%s\n' "$out" | tail -1)
  say "   $(basename "$t"): $last"
  [ "$last" = "TUTTI OK" ] || { printf '%s\n' "$out" | grep -E 'FAIL|rror' | head -5; fail=1; }
done

if command -v reapack-index >/dev/null; then
  say "== 5. reapack-index --check"
  reapack-index --check || fail=1
fi

rm -f luac.out
[ $fail = 0 ] && say "TUTTO OK" || say "CI SONO PROBLEMI (vedi sopra)"
exit $fail
