#!/bin/bash
# Collaudo a secco di tutte le finestre, in italiano e in inglese (REAPER finto: fumo_finestre.lua),
# con il mouse che passa su tutta la finestra. Non tocca il REAPER vero. Lancio dalla radice del repo:
#   bash gobbo_ricerca_battuta/test/fumo_tutte.sh
cd "$(dirname "$0")/../../ZP Studio Suite" || exit 1
export ZP_FUMO_RES="${TMPDIR:-/tmp}/zp_fumo_res"
mkdir -p "$ZP_FUMO_RES/KeyMaps"
fail=0
for s in 02_Gobbo_Verticale 03_Gobbo_Orizzontale 04_Crea_Marker_Item 07_Note_Personaggio 13_Info_Item_SRT \
  17_Crea_Regioni_Export_da_Item_Nominati 18_Project_Viewer 19_Report_Minuti_Voce 20_Importa_Cartelle_Video_Mixdown \
  22_Pulisci_Code_Silenzi_e_Separa_Item 23_ZP_Chain_Builder 24_ZP_Probe_Guard 25_ZP_SOLO_Recorder 29_ZP_Trascrizione \
  30_ZP_SRT 31_SRT_da_Marker_Audio 33_Benvenuto_Controllo_Installazione 34_ZP_Set_Comandi 35_ZP_Colori; do
  for l in it en; do
    out=$(perl -e 'alarm 30; exec @ARGV' lua ../gobbo_ricerca_battuta/test/fumo_finestre.lua "$l" "$s.lua" 120 2>/dev/null)
    rc=$?
    if [ $rc -ne 0 ]; then echo "${out:-TIMEOUT $l $s}" | head -6; fail=1; fi
  done
done
[ $fail = 0 ] && echo "FINESTRE: TUTTE OK (it + en)" || echo "FINESTRE: CI SONO ERRORI (sopra)"
exit $fail
