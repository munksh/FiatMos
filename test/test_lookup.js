// Fiat Mos 1.2: the lookup services -- which are asked, in what order, and how
// each answer is read and put together.
//
// The Open Library and Libris fixtures in test_v9.js follow real answers. The
// DNB, BnF and Google fixtures here were WRITTEN from the documented formats
// and never captured from the live services, so they prove the reader does
// what it says on records shaped like that -- not that the services answer
// this way today.
const { L } = require('./harness')
let fails = 0
function ok(name, cond, extra) {
  if (!cond) { fails++; console.log('FAIL ' + name + (extra !== undefined ? '  -> ' + JSON.stringify(extra) : '')) }
  else console.log('ok   ' + name)
}
const ids = steps => steps.map(s => s.service).join(',')

// --- ISBN helpers --------------------------------------------------------------
ok('ISBN-10 form of a 978 ISBN', L.toIsbn10('9780306406157') === '0306406152', L.toIsbn10('9780306406157'))
ok('the ISBN-10 form normalises back', L.normaliseIsbn(L.toIsbn10('9780306406157')) === '9780306406157')
ok('an X in the ISBN-10 form', L.toIsbn10('9780804429573') === '080442957X', L.toIsbn10('9780804429573'))
ok('a 979 ISBN has no ISBN-10 form', L.toIsbn10(L.withCheckDigit('979101234567')) === '')

ok('91 is Swedish', L.registrationGroup('9789100123456') === 'se')
ok('3 is German', L.registrationGroup('9783596905874') === 'de')
ok('2 is French', L.registrationGroup('9782070360024') === 'fr')
ok('979-10 is French', L.registrationGroup('9791012345678') === 'fr')
ok('5 is Russian', L.registrationGroup('9785001144373') === 'ru')
ok('0 and 1 are English, and get no library first', L.registrationGroup('9780140449334') === '' && L.registrationGroup('9781234567897') === '')
ok('a Swedish ISBN asks Libris first', L.libraryOrder('9789100123456').join() === 'libris,dnb,bnf')
ok('a German ISBN asks DNB first', L.libraryOrder('9783596905874').join() === 'dnb,libris,bnf')
ok('a French ISBN asks BnF first', L.libraryOrder('9782070360024').join() === 'bnf,libris,dnb')
ok('an English ISBN keeps the usual order', L.libraryOrder('9780140449334').join() === 'libris,dnb,bnf')

// --- what gets asked -------------------------------------------------------------
const all = ['openlibrary', 'libris', 'dnb', 'bnf', 'google']
ok('everything on: Open Library, the ISBN\'s library, the rest, Google last (German)', ids(L.plan('9783596905874', all)) === 'openlibrary,dnb,libris,bnf,google', ids(L.plan('9783596905874', all)))
ok('everything on (Swedish)', ids(L.plan('9789100123456', all)) === 'openlibrary,libris,dnb,bnf,google')
ok('a service that is off is never in the plan', ids(L.plan('9783596905874', ['openlibrary', 'libris'])) === 'openlibrary,libris')
ok('Google alone', ids(L.plan('9783596905874', ['google'])) === 'google')
ok('nothing on, nothing asked', L.plan('9783596905874', []).length === 0)
ok('the choice is not reordered by the order it was stored in', ids(L.plan('9780140449334', ['google', 'bnf', 'openlibrary'])) === 'openlibrary,bnf,google')
ok('Open Library has two addresses, .json second', (() => { const u = L.plan('9780140449334', all)[0].urls; return u.length === 2 && u[0].indexOf('/api/books?') > 0 && u[1].indexOf('/api/books.json?') > 0 })())
ok('BnF asks the ten-digit form too for a 978 ISBN', L.plan('9782070360024', ['bnf'])[0].urls.length === 2 && L.plan('9782070360024', ['bnf'])[0].urls[1].indexOf('2070360024') > 0)
ok('BnF asks only once for a 979 ISBN', L.plan('9791012345678', ['bnf'])[0].urls.length === 1)
ok('every address is https', all.every(s => L.urlsFor(s, '9783596905874').every(u => u.indexOf('https://') === 0)))
ok('only the ISBN is in an address', all.every(s => L.urlsFor(s, '9783596905874').every(u => !/isbn.*title|author|habit/i.test(u))))

// --- pages ---------------------------------------------------------------------------
ok('160 Seiten', L.pagesFrom('160 Seiten') === 160)
ok('front matter in Roman numerals is ignored', L.pagesFrom('XII, 384 Seiten : Illustrationen') === 384)
ok('an online resource', L.pagesFrom('1 Online-Ressource (250 Seiten)') === 250)
ok('French: 1 vol. (159 p.)', L.pagesFrom('1 vol. (159 p.)') === 159)
ok('French: XII-345 p.', L.pagesFrom('XII-345 p.') === 345)
ok('unpaginated is 0', L.pagesFrom('1 Band (unpaginiert)') === 0 && L.pagesFrom('1 vol. (non paginé)') === 0 && L.pagesFrom('') === 0)
ok('the biggest number wins', L.pagesFrom('[8] Bl., 200 S.') === 200)

// --- DNB (MARC21) ---------------------------------------------------------------------
const deIsbn = L.withCheckDigit('978359690587')
const marcRec = (isbn, title, author, extent) =>
  '<recordData><record xmlns="http://www.loc.gov/MARC21/slim" type="Bibliographic"><leader>00000nam a2200000 c 4500</leader>' +
  '<controlfield tag="001">1234</controlfield>' +
  '<datafield tag="020" ind1=" " ind2=" "><subfield code="a">' + isbn + '</subfield><subfield code="9">' + isbn.substr(0, 3) + '-3-596-90587-' + isbn.substr(12) + '</subfield></datafield>' +
  '<datafield tag="020" ind1=" " ind2=" "><subfield code="z">9999999999999</subfield></datafield>' +
  (author ? '<datafield tag="100" ind1="1" ind2=" "><subfield code="a">' + author + '</subfield></datafield>' : '') +
  '<datafield tag="245" ind1="1" ind2="3"><subfield code="a">' + title + '</subfield><subfield code="b">Erz&#228;hlungen &amp; mehr</subfield></datafield>' +
  (extent ? '<datafield tag="300" ind1=" " ind2=" "><subfield code="a">' + extent + '</subfield></datafield>' : '') +
  '</record></recordData>'
const envelope = recs => '<?xml version="1.0"?><searchRetrieveResponse xmlns="http://www.loc.gov/zing/srw/"><version>1.1</version><numberOfRecords>' + recs.length + '</numberOfRecords><records>' +
  recs.map((r, i) => '<record><recordSchema>MARC21-xml</recordSchema><recordPacking>xml</recordPacking>' + r + '<recordPosition>' + (i + 1) + '</recordPosition></record>').join('') + '</records></searchRetrieveResponse>'

const dnb = L.parseDnb(envelope([marcRec(deIsbn, '¬Die¬ Gelegenheiten :', 'Köhler, Michael T.', '160 Seiten')]), deIsbn)
ok('DNB: the title without non-sorting marks and trailing punctuation', dnb && dnb.title === 'Die Gelegenheiten', dnb)
ok('DNB: the author turned round', dnb && dnb.creator === 'Michael T. Köhler', dnb)
ok('DNB: pages from the extent', dnb && dnb.extent === 160, dnb)
ok('DNB: no cover, and named', dnb && dnb.cover === '' && dnb.service === 'dnb' && dnb.source === 'DNB')
ok('DNB: no extent field is 0 pages', L.parseDnb(envelope([marcRec(deIsbn, 'T', 'A, B', '')]), deIsbn).extent === 0)
ok('DNB: no author field is an empty creator', L.parseDnb(envelope([marcRec(deIsbn, 'T', '', '10 S.')]), deIsbn).creator === '')
const other = L.withCheckDigit('978386602288')
ok('DNB: an answer about some other book is not this book', L.parseDnb(envelope([marcRec(other, 'Other', 'X, Y', '50 S.')]), deIsbn) === null)
const two = L.parseDnb(envelope([marcRec(other, 'Other', 'X, Y', '50 S.'), marcRec(deIsbn, 'Right one', 'K, L', '77 S.')]), deIsbn)
ok('DNB: the matching record is picked out of unrelated ones', two && two.title === 'Right one' && two.extent === 77, two)
ok('DNB: a cancelled ISBN (subfield z) does not count', L.parseDnb(envelope([marcRec(deIsbn, 'T', 'A, B', '')]), '9999999999999') === null)
ok('DNB: no records', L.parseDnb(envelope([]), deIsbn) === null)
ok('DNB: rubbish', L.parseDnb('<html>', deIsbn) === null && L.parseDnb(undefined, deIsbn) === null && L.parseDnb('', deIsbn) === null)
const prefixed = envelope([marcRec(deIsbn, 'Prefixed', 'A, B', '9 S.')]).replace(/<(\/?)(record|datafield|subfield|controlfield|leader)/g, (m, s, t) => '<' + s + 'marc:' + t).replace(/<(\/?)recordData/g, '<$1srw:recordData')
ok('DNB: namespace prefixes are fine', (L.parseDnb(prefixed, deIsbn) || {}).title === 'Prefixed', prefixed.substr(0, 400))
ok('DNB: hyphenated ISBN in $9 alone is enough', (() => {
  const rec = '<recordData><record><datafield tag="020"><subfield code="9">978-3-596-90587-' + deIsbn.substr(12) + '</subfield></datafield><datafield tag="245"><subfield code="a">Only nine</subfield></datafield></record></recordData>'
  return (L.parseDnb(envelope([rec]), deIsbn) || {}).title === 'Only nine'
})())

// --- BnF (UNIMARC) ----------------------------------------------------------------------
const frIsbn = L.normaliseIsbn('2-07-036002-2')
const unimarc = (isbn010, title, sur, fore, extent) =>
  '<mxc:record xmlns:mxc="info:lc/xmlns/marcxchange-v2" format="UNIMARC" type="Bibliographic"><mxc:leader>x</mxc:leader>' +
  '<mxc:controlfield tag="003">http://catalogue.bnf.fr/ark:/12148/cb12345</mxc:controlfield>' +
  '<mxc:datafield tag="010" ind1=" " ind2=" "><mxc:subfield code="a">' + isbn010 + '</mxc:subfield><mxc:subfield code="d">EUR 8.00</mxc:subfield></mxc:datafield>' +
  '<mxc:datafield tag="200" ind1="1" ind2=" "><mxc:subfield code="a">' + title + '</mxc:subfield><mxc:subfield code="f">Albert Camus</mxc:subfield></mxc:datafield>' +
  (sur ? '<mxc:datafield tag="700" ind1=" " ind2="1"><mxc:subfield code="a">' + sur + '</mxc:subfield><mxc:subfield code="b">' + fore + '</mxc:subfield></mxc:datafield>' : '') +
  (extent ? '<mxc:datafield tag="215" ind1=" " ind2=" "><mxc:subfield code="a">' + extent + '</mxc:subfield></mxc:datafield>' : '') +
  '</mxc:record>'
const bnfEnvelope = recs => '<srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/"><srw:numberOfRecords>' + recs.length + '</srw:numberOfRecords><srw:records>' +
  recs.map(r => '<srw:record><srw:recordData>' + r + '</srw:recordData></srw:record>').join('') + '</srw:records></srw:searchRetrieveResponse>'
const bnf = L.parseBnf(bnfEnvelope([unimarc('2-07-036002-2', 'L\'étranger', 'Camus', 'Albert', '1 vol. (159 p.)')]), frIsbn)
ok('BnF: a record with only the old ISBN-10 is found by the ISBN-13', bnf !== null, bnf)
ok('BnF: title, and the author as forename surname', bnf && bnf.title === 'L\'étranger' && bnf.creator === 'Albert Camus', bnf)
ok('BnF: pages', bnf && bnf.extent === 159, bnf)
ok('BnF: named, no cover', bnf && bnf.service === 'bnf' && bnf.source === 'BnF' && bnf.cover === '')
ok('BnF: a surname alone is kept', L.parseBnf(bnfEnvelope([unimarc('2-07-036002-2', 'T', 'Homere', '', '')]), frIsbn).creator === 'Homere')
ok('BnF: another book is not this book', L.parseBnf(bnfEnvelope([unimarc('0-306-40615-2', 'T', 'A', 'B', '10 p.')]), frIsbn) === null)
ok('BnF: no records / rubbish', L.parseBnf(bnfEnvelope([]), frIsbn) === null && L.parseBnf('nonsense', frIsbn) === null && L.parseBnf(null, frIsbn) === null)

// --- Google Books -------------------------------------------------------------------------
const gIsbn = '9780306406157'
const gText = JSON.stringify({ totalItems: 1, items: [{ volumeInfo: {
  title: 'A Book', authors: ['Ann One', 'Bo Two'], pageCount: 412,
  industryIdentifiers: [{ type: 'ISBN_10', identifier: '0306406152' }, { type: 'ISBN_13', identifier: gIsbn }],
  imageLinks: { smallThumbnail: 'http://books.google.com/small', thumbnail: 'http://books.google.com/books/content?id=abc&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api' } } }] })
const g = L.parseGoogle(gText, gIsbn)
ok('Google: title, both authors, pages', g && g.title === 'A Book' && g.creator === 'Ann One, Bo Two' && g.extent === 412, g)
ok('Google: the cover is https and not curled', g && g.cover.indexOf('https://books.google.com/books/content?id=abc') === 0 && g.cover.indexOf('edge=curl') < 0, g)
ok('Google: named', g && g.service === 'google' && g.source === 'Google Books')
ok('Google: a volume for another ISBN is refused', L.parseGoogle(gText, '9783596905874') === null)
ok('Google: a volume with no identifiers is not trusted', L.parseGoogle(JSON.stringify({ items: [{ volumeInfo: { title: 'X', pageCount: 5 } }] }), gIsbn) === null)
ok('Google: the matching volume is picked out of several', (() => {
  const t = JSON.stringify({ items: [
    { volumeInfo: { title: 'Wrong', industryIdentifiers: [{ identifier: '9783596905874' }] } },
    { volumeInfo: { title: 'Right', industryIdentifiers: [{ identifier: '0306406152' }] } }] })
  return (L.parseGoogle(t, gIsbn) || {}).title === 'Right'
})())
ok('Google: a refusal body is not a book', L.parseGoogle('{"error":{"code":429,"message":"quota"}}', gIsbn) === null)
ok('Google: no pages and no cover', (() => { const r = L.parseGoogle(JSON.stringify({ items: [{ volumeInfo: { title: 'T', industryIdentifiers: [{ identifier: gIsbn }] } }] }), gIsbn); return r && r.extent === 0 && r.cover === '' && r.creator === '' })())

// --- parseFor -------------------------------------------------------------------------------
ok('parseFor routes to the right reader', L.parseFor('google', gText, gIsbn).service === 'google' && L.parseFor('dnb', envelope([marcRec(deIsbn, 'T', 'A, B', '')]), deIsbn).service === 'dnb')
ok('parseFor knows no other services', L.parseFor('amazon', gText, gIsbn) === null)
ok('parseFor never throws', all.every(s => L.parseFor(s, undefined, gIsbn) === null && L.parseFor(s, '\u0000{[', gIsbn) === null))

// --- putting it together ---------------------------------------------------------------------
{
  const r = L.emptyResult()
  L.merge(r, null, 'openlibrary')
  ok('nothing found merges to nothing', r.title === '' && !L.complete(r))
  L.merge(r, { title: 'Doktor Glas', creator: 'Hjalmar Söderberg', extent: 0, cover: '' }, 'libris')
  ok('Libris gives title and author', r.title === 'Doktor Glas' && r.from.title === 'libris' && r.from.creator === 'libris' && r.from.extent === '')
  ok('not complete without pages', !L.complete(r))
  L.merge(r, { title: 'Doctor Glas', creator: 'H. S.', extent: 168, cover: 'https://x/y.jpg' }, 'dnb')
  ok('DNB fills the pages and only the pages', r.title === 'Doktor Glas' && r.creator === 'Hjalmar Söderberg' && r.extent === 168 && r.from.extent === 'dnb', r)
  ok('now complete', L.complete(r))
  ok('a cover address is kept with who gave it', r.covers.length === 1 && r.covers[0].service === 'dnb' && r.covers[0].url === 'https://x/y.jpg')
  const p = L.provenance(r, 'openlibrary')
  ok('provenance groups what one service gave', p.groups.length === 3 && p.groups[0].service === 'libris' && p.groups[0].what.join() === 'title,creator' && p.groups[1].service === 'dnb' && p.groups[1].what.join() === 'extent' && p.groups[2].service === 'openlibrary' && p.groups[2].what.join() === 'cover', p)
  ok('nothing is missing here', p.missing.length === 0)
  const q = L.provenance(r, '')
  ok('a missing cover is reported missing', q.missing.join() === 'cover', q)
  const bare = L.emptyResult()
  L.merge(bare, { title: 'T', creator: '', extent: 0, cover: '' }, 'libris')
  ok('missing author, pages and cover are all reported', L.provenance(bare, '').missing.join() === 'creator,extent,cover', L.provenance(bare, ''))
}

// --- covers -------------------------------------------------------------------------------------
{
  const isbn = '9780140449334'
  const r = L.emptyResult()
  const cc = (en, res, asked) => L.coverCandidates(isbn, en, res, asked).map(c => c.service + (c.url ? '' : '?')).join(',')
  ok('Open Library on: its cover by ISBN', cc(['openlibrary'], null, []) === 'openlibrary')
  ok('Open Library off: it is never asked for a cover', cc(['libris', 'dnb'], null, []) === '')
  ok('Google on and not yet asked: it will be asked', cc(['google'], null, []) === 'google?')
  ok('Google already asked and had no cover: not asked again', cc(['google'], r, ['google']) === '')
  ok('both on, Open Library first', cc(['openlibrary', 'google'], null, []) === 'openlibrary,google?')
  L.merge(r, { title: 'T', creator: 'C', extent: 1, cover: 'https://covers.openlibrary.org/b/id/1-M.jpg' }, 'openlibrary')
  ok('a cover address from an answer comes before the guess', cc(['openlibrary'], r, ['openlibrary']) === 'openlibrary,openlibrary' && L.coverCandidates(isbn, ['openlibrary'], r, ['openlibrary'])[0].url.indexOf('/b/id/1-M.jpg') > 0)
  const g2 = L.emptyResult()
  L.merge(g2, { title: 'T', creator: 'C', extent: 1, cover: 'https://books.google.com/x' }, 'google')
  ok('a Google cover address is dropped if Google was switched off since', cc(['openlibrary'], g2, ['google']) === 'openlibrary')
  ok('every candidate address is https', L.coverCandidates(isbn, all, g2, ['google']).every(c => !c.url || c.url.indexOf('https://') === 0))
}

// --- outcomes ---------------------------------------------------------------------------------------
ok('found', L.outcomeOf(true, true, false) === 'found')
ok('answered, did not know', L.outcomeOf(false, true, false) === 'nothing')
ok('refused', L.outcomeOf(false, false, true) === 'declined')
ok('no usable answer', L.outcomeOf(false, false, false) === 'failed')
ok('an answer beats an earlier refusal', L.outcomeOf(false, true, true) === 'nothing')

ok('the services are listed with Google last and off', L.SERVICES.length === 5 && L.SERVICES[4].id === 'google' && L.SERVICES[4].on === false && L.SERVICES.slice(0, 4).every(s => s.on))
ok('service names', L.serviceName('dnb') === 'DNB' && L.serviceName('google') === 'Google Books' && L.serviceName('zzz') === 'zzz')

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails === 0 ? 0 : 1)
