local M=dofile('ZP Studio Suite/ZP_Testo_Copione.lua')
local n=0
local function eq(a,b,label) n=n+1; assert(a==b, 'FAIL '..(label or tostring(n))..': '..tostring(a)..' ~= '..tostring(b)) end
eq(M.normalize('  È\194\160già\t  qui\r\n\226\128\139 “ciao”—sì  '),'È già qui\n"ciao"-sì','normalizza UTF-8')
eq(M.normalize('A\n\n\n\nB'),'A\n\n\n\nB','conserva pause')
eq(M.normalize('A\n\n\n\nB',true),'A\n\nB','pulizia esplicita pause')
eq(M.join_lines('Riga spezzata\na metà.\nAltra frase\n\nParagrafo\n• elenco'),'Riga spezzata a metà.\nAltra frase\n\nParagrafo\n• elenco')
eq(M.breathe('È vero. Sì! Bene? Fine'),'È vero.\nSì!\nBene?\nFine')
eq(M.lower('È GIÀ PERCHÉ'),'è già perché'); eq(M.upper('è già perché'),'È GIÀ PERCHÉ')
eq(M.sentence_case('È GIÀ. PERCHÉ? SÌ!'),'È già. Perché? Sì!')
local w,p=M.stats('uno due\n\nÈ qui'); eq(w,4);eq(p,1)
local w0,p0=M.stats('');eq(w0,0);eq(p0,0)
local _,p2=M.stats('a\n\n\nb');eq(p2,2)
local expected='È già pronto.\n\nSeconda\nriga & voce.'
for _,ext in ipairs({'docx','odt'}) do
 local t,hi=M.read_file('gobbo_ricerca_battuta/test/fixtures/copione/copione.'..ext,'OSX64')
 eq(t,expected,'ZIP reale '..ext);eq(hi[1],'pronto','grassetto '..ext)
end
local t,h=M.docx('<w:body><w:p><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>No</w:t></w:r><w:del><w:r><w:t>cancellato</w:t></w:r></w:del><w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t> sì &#xC8;</w:t></w:r></w:p></w:body>')
eq(t,'No sì È');eq(h[1],'sì È');eq(#h,1)
t,h=M.odt('<text:p text:style-name="P">È<text:s text:c="3"/>sì<text:tab/>qui</text:p>','<style:style style:name="B"><style:text-properties fo:font-weight="bold"/></style:style><style:style style:name="P" style:parent-style-name="B"></style:style>')
eq(t,'È sì qui');eq(h[1],'È')
eq(M.rtf([[{\rtf1\ansi{\fonttbl{\f0 Arial;}}\uc1 \u200? gi\'e0\par\par {\b pronto} \{s\}\tab s\u236?}]]),'È già\n\npronto {s} sì','RTF ANSI input')
eq(M.rtf([[{\rtf1\uc1\u200? gi\u224?\par{\*\unknown privato}testo}]]),'È già\ntesto')
eq(M.rtf([[{\rtf1\uc1\u-10179?\u-8704?}]]),'😀','surrogate pair')
local called=false
local clip=M.clipboard({CF_GetClipboard=function() return ' È\194\160qui ' end},'OSX64',function() error('non chiamare OS con SWS') end)
eq(clip,'È qui')
eq(M.clipboard({},'OSX64',function(cmd) called=cmd=='pbpaste';return 'ciao\r\nvoce' end),'ciao\nvoce');eq(called,true)
local cmd
M.clipboard({},'Win64',function(s) cmd=s; return 'è' end);eq(cmd:find('EncodedCommand',1,true)~=nil,true)
local text,err=M.read_file('/tmp/nonexistent.doc','OSX64');eq(text,nil);eq(type(err),'string')
eq(M.clipboard({},'OSX64',function() return nil,'errore' end),nil)
eq(M.clipboard({CF_GetClipboard=function() return '' end},'OSX64',function() error('empty is valid') end),'')

local _,edge=M.stats('\nÈ qui.\n\n');eq(edge,3,'conta pause iniziali/finali')
eq(M.same_words('È già.\n\nQui.','È già. Qui.'),true,'pause senza cambio parole')
local function measure(t) return assert(utf8.len(t))*10 end
local words='È   già qui'
eq(M.cursor_in_words(words,1,#words,20,measure),6,'spazi compressi: byte della parola')
eq(M.cursor_in_words('È qui',1,6,4,measure),1,'clic prima metà accento')
eq(M.cursor_in_words('È qui',1,6,7,measure),3,'clic dopo metà accento')
print(n..' verifiche copione OK')
print('TUTTI OK')
