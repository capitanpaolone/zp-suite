-- Copione Excel (.xlsx) -> battute SRT, e testo delle battute SRT/VTT.
local M = dofile('ZP Studio Suite/ZP_Xlsx_Copione.lua')
local function eq(a, b, msg) if a ~= b then error((msg or 'diverso') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- Un xlsx finto: il primo foglio e' il riepilogo, il secondo ha il copione.
local files = {
  ['xl/workbook.xml'] = '<workbook><sheets><sheet name="Cast" sheetId="1" r:id="rId1"/><sheet state="visible" name="Copione &amp; tempi" sheetId="2" r:id="rId2"/></sheets></workbook>',
  ['xl/_rels/workbook.xml.rels'] = '<Relationships><Relationship Id="rId2" Type="x" Target="worksheets/sheet2.xml"/><Relationship Id="rId1" Type="x" Target="/xl/worksheets/sheet1.xml"/></Relationships>',
  ['xl/sharedStrings.xml'] = '<sst><si><t>Episode</t></si><si><t>Timecode</t></si><si><t>Role</t></si><si><t>Reaction Sound</t></si><si><t>Translation</t></si>'
    .. '<si><t>ANNA</t></si><si><r><t>Ciao </t></r><r><t>a tutti &amp; grazie.</t></r><rPh><t>no</t></rPh></si><si><t>&lt;sospira&gt;</t></si><si/><si><t>Character</t></si></sst>',
  ['xl/worksheets/sheet1.xml'] = '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>9</v></c></row><row r="2"><c r="A2" t="s"><v>5</v></c></row></sheetData></worksheet>',
  ['xl/worksheets/sheet2.xml'] = '<worksheet><sheetData>'
    .. '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c><c r="E1" t="s"><v>4</v></c></row>'
    .. '<row r="2"><c r="B2" t="inlineStr"><is><t>00:00:10,500</t></is></c><c r="C2" t="s"><v>5</v></c><c r="D2" s="3"/><c r="E2" t="s"><v>6</v></c></row>'
    .. '<row r="3"><c r="B3"><v>0.0001388888888888889</v></c><c r="C3" t="s"><v>5</v></c><c r="D3" t="s"><v>7</v></c></row>'
    .. '<row r="4"><c r="A4" t="s"><v>0</v></c></row>'
    .. '<row r="5"><c r="B5" t="str"><v>00:20,000</v></c><c r="E5" t="str"><v>Ultima   battuta_x000D_</v></c></row>'
    .. '</sheetData></worksheet>',
}
local function member(name) return files[name] end

local cues, sheet = M.read(member)
assert(cues, sheet)
eq(sheet, 'Copione & tempi', 'foglio scelto')
eq(#cues, 3, 'numero battute')
eq(cues[1].text, 'ANNA: Ciao a tutti & grazie.')
eq(cues[1].start, 10500); eq(cues[1].finish, 12000 - M.GAP_MS, 'fine stimata dal successivo inizio')
eq(cues[2].text, 'ANNA: <sospira>', 'reazione senza testo')
eq(cues[2].start, 12000, 'tempo come frazione di giorno')
eq(cues[3].text, 'Ultima battuta'); eq(cues[3].finish, 20000 + M.LAST_MS, 'ultima battuta')
local head = '1\n00:00:10,500 --> 00:00:11,920\nANNA: Ciao a tutti & grazie.\n\n2\n00:00:12,000'
eq(M.to_srt(cues):sub(1, #head), head)

-- Opzioni: senza personaggi e senza reazioni
local plain = M.read(member, { roles = false, reactions = false })
eq(#plain, 2); eq(plain[1].text, 'Ciao a tutti & grazie.')

-- Una riga piena con il tempo sbagliato ferma l'importazione e dice quale.
local bad = files['xl/worksheets/sheet2.xml']
files['xl/worksheets/sheet2.xml'] = bad:gsub('00:20,000', 'boh')
local none, err = M.read(member)
eq(none, nil); assert(err:find('righe: 5', 1, true), err)
files['xl/worksheets/sheet2.xml'] = bad

-- Nessun foglio adatto, file non xlsx
files['xl/worksheets/sheet2.xml'] = files['xl/worksheets/sheet1.xml']
none, err = M.read(member); eq(none, nil); assert(err:find('Timecode', 1, true))
none, err = M.read(function() return nil end); eq(none, nil); assert(err:find('xlsx', 1, true))
files['xl/worksheets/sheet2.xml'] = bad

-- Tempi
eq(M.time_ms('01:02:03.456'), 3723456); eq(M.time_ms('1:02:03'), 3723000); eq(M.time_ms('12'), nil); eq(M.time_ms(''), nil)
eq(M.format_time(3723456), '01:02:03,456')

-- Testo delle battute SRT/VTT
eq(M.clean_cue_text('<v Anna>Ciao</v>'), 'Anna: Ciao', 'voce VTT')
eq(M.clean_cue_text('<v.loud Mario Rossi>Ehi <i>tu</i></v>'), 'Mario Rossi: Ehi tu', 'voce VTT con classe')
eq(M.clean_cue_text('<i>Corsivo</i> <b>e</b> <c.yellow>colore</c> <font color="#fff">x</font>'), 'Corsivo e colore x')
eq(M.clean_cue_text('Prima <00:00:01.500>dopo'), 'Prima dopo', 'tempo interno VTT')
eq(M.clean_cue_text('HENRI: <sospira>'), 'HENRI: <sospira>', 'la reazione resta')
eq(M.clean_cue_text('<verso forte> <ridacchia> Meno male.\r\n&amp; via'), '<verso forte> <ridacchia> Meno male.\n& via')

-- Conversione su file: scrive l'SRT accanto, non sostituisce senza conferma
local base = os.tmpname()
local xlsx = base .. '.xlsx'
local out, n = M.convert_file(xlsx, member)
eq(out, base .. '.srt'); eq(n, 3)
local f = io.open(out, 'rb'); local written = f:read('a'); f:close(); eq(written, M.to_srt(cues))
out = M.convert_file(xlsx, member, function() error('uguale: non deve chiedere') end); eq(out, base .. '.srt')
f = io.open(base .. '.srt', 'wb'); f:write('altro'); f:close()
local asked = 0
out, n = M.convert_file(xlsx, member, function() asked = asked + 1; return false end)
eq(out, nil); eq(n, nil); eq(asked, 1)
f = io.open(base .. '.srt', 'rb'); eq(f:read('a'), 'altro', 'senza conferma resta il vecchio'); f:close()
out = M.convert_file(xlsx, member, function() return true end); eq(out, base .. '.srt')
os.remove(base .. '.srt'); os.remove(base)

-- Scelta del file: un SRT passa invariato, un .xls viene rifiutato con una spiegazione
eq(M.resolve_choice('/x/a.srt', {}, ''), '/x/a.srt')
none, err = M.resolve_choice('/x/a.XLS', {}, ''); eq(none, nil); assert(err:find('.xlsx', 1, true))

-- Piu' fogli adatti e piu' lingue: chiede quale foglio e quale colonna
local multi = {
  ['xl/workbook.xml'] = '<workbook><sheets><sheet name="EP01" sheetId="1" r:id="rId1"/><sheet name="EP02" sheetId="2" r:id="rId2"/></sheets></workbook>',
  ['xl/_rels/workbook.xml.rels'] = '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>',
}
local function lang_sheet(it, en)
  local function c(ref, v) return '<c r="' .. ref .. '" t="inlineStr"><is><t>' .. v .. '</t></is></c>' end
  return '<worksheet><sheetData><row r="1">' .. c('A1', 'Timecode') .. c('B1', 'Gender') .. c('C1', 'English') .. c('D1', 'Translation') .. c('E1', 'Episode') .. '</row>'
    .. '<row r="2">' .. c('A2', '00:00:01,000') .. c('B2', 'F') .. c('C2', en) .. c('D2', it) .. c('E2', '0002') .. '</row></sheetData></worksheet>'
end
multi['xl/worksheets/sheet1.xml'] = lang_sheet('Ciao a te', 'Hello to you')
multi['xl/worksheets/sheet2.xml'] = lang_sheet('Buona sera', 'Good evening')
local function mm(name) return multi[name] end
local asked = {}
local function chooser(answers)
  asked = {}
  return function(title, labels) asked[#asked + 1] = title .. ' ' .. table.concat(labels, ' / '); return answers[#asked] end
end
local c2, s2, col2 = M.read(mm, { choose = chooser({ 2, 2 }) })
eq(#asked, 2); eq(asked[1], 'Quale foglio importo? EP01 / EP02')
eq(asked[2], 'Quale colonna di testo importo? D — Translation / C — English', 'colonna nota per prima, le altre lingue dopo; Gender ed Episode fuori')
eq(s2, 'EP02'); eq(col2, 'English'); eq(c2[1].text, 'Good evening')
c2, s2, col2 = M.read(mm)                                   -- senza domande: primo foglio, prima colonna
eq(s2, 'EP01'); eq(c2[1].text, 'Ciao a te')
local cancelled, why = M.read(mm, { choose = chooser({}) })     -- annullato
eq(cancelled, nil); eq(why, nil)
local out_c, n_c = M.convert_file(os.tmpname() .. '.xlsx', mm, nil, { choose = chooser({ 1 }) })
eq(out_c, nil); eq(n_c, nil, 'annullare la scelta della colonna non scrive nulla')
M.read(member, { choose = function() error('un solo foglio e una sola colonna: non deve chiedere') end })

-- Testo libero del Gobbo: una battuta per riga, senza tempi
eq(M.to_text(cues), 'ANNA: Ciao a tutti & grazie.\nANNA: <sospira>\nUltima battuta')

-- 01: basename deve essere definita prima di register_srt, che la usa (era nil: errore all'importazione)
local f01 = io.open('ZP Studio Suite/01_Importa_Video_SRT.lua', 'rb'); local src01 = f01:read('a'); f01:close()
local def, use = src01:find('local function basename(path)', 1, true), src01:find('basename(srt_path)', 1, true)
assert(def and use and def < use, '01: basename definita dopo il primo uso')

print('TUTTI OK')
