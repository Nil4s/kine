class_name TradeWords
extends RefCounted
## trade_words.gd - s222 TRADE JARGON: the shop names people really say ("two by four", "4x8 sheet", "3/4 ply", "1/4-20", "M6 x 16", "SC1", "KW1",
## "caibro") mapped to the REAL spec, with the source, and said back ("2x4 = 38 x 89 mm ..."). Pure data + regexes: no AI, no guessing. A term that
## looks like trade jargon but is not in the tables ("3x7", "SC9", "pontalete grande") is LISTED as unknown, never turned into a size.
## find_all(text) -> {"items": [{"kind", "term", "say", "mm": {...}, "span": [from, to]}], "unknown": [terms], "rest": text with the found terms cut out}
## Sizes are mm. Lumber "kind": "lumber" {t, w} (dressed size), "sheet" {w, l}, "ply" {t}, "bolt" {d, len, pitch, head_af, head_k}, "key" (a name only), "br" {t, w}.

## US/CA dressed lumber (American Softwood Lumber Standard PS 20 / NIST): nominal inches -> dressed inches (thickness, width)
const NOM_T := {1: 0.75, 2: 1.5, 3: 2.5, 4: 3.5, 6: 5.5}
const NOM_W := {2: 1.5, 3: 2.5, 4: 3.5, 6: 5.5, 8: 7.25, 10: 9.25, 12: 11.25}
const IN := 25.4
## ISO 261 coarse pitch (mm) by diameter; ISO 4017 head: width across flats s, height k
const M_PITCH := {3: 0.5, 4: 0.7, 5: 0.8, 6: 1.0, 8: 1.25, 10: 1.5, 12: 1.75, 16: 2.0, 20: 2.5}
const M_HEAD := {3: [5.5, 2.0], 4: [7.0, 2.8], 5: [8.0, 3.5], 6: [10.0, 4.0], 8: [13.0, 5.3], 10: [16.0, 6.4], 12: [18.0, 7.5], 16: [24.0, 10.0], 20: [30.0, 12.5]}
## ASME B1.1 UNC / UNF threads per inch by fractional diameter (numerator/denominator in inches)
const UNC := {"1/4": 20, "5/16": 18, "3/8": 16, "7/16": 14, "1/2": 13, "9/16": 12, "5/8": 11, "3/4": 10}
const UNF := {"1/4": 28, "5/16": 24, "3/8": 24, "7/16": 20, "1/2": 20, "9/16": 18, "5/8": 18, "3/4": 16}
## ASME B18.2.1 hex cap screw: width across flats and head height (inches)
const HEX_IN := {"1/4": [0.4375, 0.1719], "5/16": [0.5, 0.2188], "3/8": [0.5625, 0.2656], "7/16": [0.625, 0.3], "1/2": [0.75, 0.3438], "5/8": [0.9375, 0.4219], "3/4": [1.125, 0.5]}
const KEYS := {
	"sc1": "Schlage SC1: the 5-pin residential key blank with the Schlage 'C' keyway (Schlage, USA).",
	"sc4": "Schlage SC4: the 6-pin key blank with the Schlage 'C'-family keyway (Schlage, USA), the 6-pin sibling of SC1.",
	"kw1": "Kwikset KW1: the 5-pin residential key blank for Kwikset locks (Kwikset, USA).",
	"kw10": "Kwikset KW10: the 6-pin key blank for Kwikset locks (Kwikset, USA)."}
## Brazilian sawn timber (mm, thickness x width). Sources: ABNT NBR 7203 (1982) / NBR 14807 (2002) name the classes by section; the section ranges are
## the Pará SEMAS annex (https://www.semas.pa.gov.br/legislacao/files/pdf/121.pdf): ripa 10x40 .. 25x50, caibro 40x50 .. 70x50, pontalete 40x40 .. 80x80;
## viga 40..80 thick x 110..200 wide (NBR 7203). The size built is a typical one INSIDE that range; sarrafo is typical commercial (not in the sources found).
const BR := {
	"ripa": {"t": 20.0, "w": 40.0, "say": "ripa: slat, 20 x 40 mm (range 10 x 40 to 25 x 50 mm; ABNT NBR 7203 class, Pará SEMAS annex)"},
	"caibro": {"t": 50.0, "w": 60.0, "say": "caibro: rafter, 50 x 60 mm (range 40 x 50 to 70 x 50 mm; ABNT NBR 7203 class, Pará SEMAS annex)"},
	"sarrafo": {"t": 25.0, "w": 75.0, "say": "sarrafo: batten, 25 x 75 mm (typical commercial size, not in the cited sources)"},
	"viga": {"t": 60.0, "w": 150.0, "say": "viga: beam, 60 x 150 mm (NBR 7203: 40 to 80 mm thick, 110 to 200 mm wide)"},
	"pontalete": {"t": 75.0, "w": 75.0, "say": "pontalete: short post, 75 x 75 mm (range 40 x 40 to 80 x 80 mm; Pará SEMAS annex)"}}


static func _frac(s: String) -> float:
	var p := s.split("/")
	return float(p[0]) / float(p[1])


static func _g(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")


## the term (lower case, one trade word) -> its meaning, "" when it is not one
static func meaning(term: String) -> String:
	var t := term.to_lower().strip_edges()
	if KEYS.has(t):
		return String(KEYS[t])
	if BR.has(t):
		return String(BR[t]["say"])
	var r := find_all(t)
	if not (r["items"] as Array).is_empty():
		return String(r["items"][0]["say"])
	return ""


static func _cut(text: String, spans: Array) -> String:
	var s := text
	var sp := spans.duplicate()
	sp.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for x in sp:
		s = s.substr(0, int(x[0])) + " " + s.substr(int(x[1]))
	return s


static func find_all(text: String) -> Dictionary:
	var s := text.to_lower()
	var items: Array = []
	var unknown: Array = []
	var spans: Array = []
	var re := RegEx.new()
	# bolts: M6 x 16 / M6x16
	re.compile("\\bm(\\d+(?:\\.\\d+)?)\\s*(?:x|×)\\s*(\\d+(?:\\.\\d+)?)\\b")
	for mt in re.search_all(s):
		var d := int(float(mt.get_string(1)))
		var ln := float(mt.get_string(2))
		if not M_PITCH.has(d):
			unknown.append(mt.get_string(0).strip_edges())
		else:
			var h: Array = M_HEAD[d]
			items.append({"kind": "bolt", "term": "M%d x %s" % [d, _g(ln)], "say": "M%d x %s = metric bolt, thread diameter %d mm, %s mm long, coarse pitch %s mm (ISO 261); hex head %s mm across flats, %s mm high (ISO 4017)." % [d, _g(ln), d, _g(ln), _g(float(M_PITCH[d])), _g(h[0]), _g(h[1])],
				"mm": {"d": float(d), "len": ln, "pitch": float(M_PITCH[d]), "head_af": float(h[0]), "head_k": float(h[1])}, "span": [mt.get_start(), mt.get_end()]})
			spans.append([mt.get_start(), mt.get_end()])
	# inch threads: 1/4-20 (UNC) / 1/4-28 (UNF), optional length "x 1 in"
	re.compile("\\b(\\d+/\\d+)\\s*-\\s*(\\d+)\\b(?:\\s*(unc|unf))?")
	for mt in re.search_all(s):
		var fr := mt.get_string(1)
		var tpi := int(mt.get_string(2))
		var cls := ""
		if UNC.has(fr) and int(UNC[fr]) == tpi:
			cls = "UNC"
		elif UNF.has(fr) and int(UNF[fr]) == tpi:
			cls = "UNF"
		if cls == "":
			unknown.append(mt.get_string(0).strip_edges())
			spans.append([mt.get_start(), mt.get_end()])
			continue
		var dm := _frac(fr) * IN
		var hx: Array = HEX_IN.get(fr, [_frac(fr) * 1.5 + 0.125, _frac(fr) * 0.6875])
		items.append({"kind": "bolt", "term": "%s-%d" % [fr, tpi], "say": "%s-%d = %s inch thread: major diameter %s in = %s mm, %d threads per inch (pitch %s mm) (ASME B1.1); hex head %s mm across flats (ASME B18.2.1)." % [fr, tpi, cls, fr, _g(dm), tpi, _g(IN / float(tpi)), _g(float(hx[0]) * IN)],
			"mm": {"d": dm, "len": 25.4, "pitch": IN / float(tpi), "head_af": float(hx[0]) * IN, "head_k": float(hx[1]) * IN}, "span": [mt.get_start(), mt.get_end()]})
		spans.append([mt.get_start(), mt.get_end()])
	# plywood by fraction: 3/4 ply
	re.compile("\\b(\\d+/\\d+)\\s*(?:in|inch)?\\s*(?:ply|plywood)\\b")
	for mt in re.search_all(s):
		var fp := mt.get_string(1)
		var actual := {"1/4": 5.5, "3/8": 8.7, "1/2": 11.9, "5/8": 15.1, "3/4": 18.3}   # APA PS 1 / PS 2: nominal -> actual (23/32 in = 18.3 mm)
		if not actual.has(fp):
			unknown.append(mt.get_string(0).strip_edges())
		else:
			items.append({"kind": "ply", "term": fp + " ply", "say": "%s ply = nominal %s in (%s mm) plywood; the sheet is really %s mm thick (APA PS 1, 23/32 in for 3/4)." % [fp, fp, _g(_frac(fp) * IN), _g(float(actual[fp]))],
				"mm": {"t": float(actual[fp])}, "span": [mt.get_start(), mt.get_end()]})
		spans.append([mt.get_start(), mt.get_end()])
	# sheets: 4x8 sheet / 4 x 8 sheet
	re.compile("\\b(\\d+)\\s*x\\s*(\\d+)\\s*(?:sheet|sheets|panel|board of ply)\\b")
	for mt in re.search_all(s):
		if mt.get_string(1) == "4" and mt.get_string(2) == "8":
			items.append({"kind": "sheet", "term": "4x8 sheet", "say": "4x8 sheet = 4 ft x 8 ft panel = 1219.2 x 2438.4 mm (nominal 4 x 8 ft, US/CA panel size).", "mm": {"w": 1219.2, "l": 2438.4}, "span": [mt.get_start(), mt.get_end()]})
		else:
			unknown.append(mt.get_string(0).strip_edges())
		spans.append([mt.get_start(), mt.get_end()])
	# lumber: 2x4, 2 x 4 (not when a unit follows: that is a size, not a trade name), "two by four"
	var s2 := _cut(s, spans)
	var off_map := s2   # spans of lumber are found on the cut text, then mapped on it (the cut keeps lengths)
	re.compile("\\b(\\d{1,2})\\s*x\\s*(\\d{1,2})\\b(?!\\s*(?:x|mm|cm|m\\b|ft|in\\b|inch|metre|meter))")
	var lum_spans: Array = []
	for mt in re.search_all(off_map):
		var a := int(mt.get_string(1))
		var b := int(mt.get_string(2))
		var compact := not mt.get_string(0).contains(" ")
		var after := off_map.substr(mt.get_end(), 24)
		if not (compact or after.strip_edges().begins_with("long") or after.strip_edges().begins_with("stud") or after.strip_edges().begins_with("piece") or after.strip_edges().begins_with("board") or after.strip_edges().begins_with("plank")):
			continue
		if a == 4 and b == 8 and off_map.substr(mt.get_end(), 12).strip_edges().begins_with("sheet"):
			continue
		if NOM_T.has(a) and NOM_W.has(b) and (a < b or a == b):
			var tt := float(NOM_T[a]) * IN
			var ww := float(NOM_W[b]) * IN
			items.append({"kind": "lumber", "term": "%dx%d" % [a, b], "say": "%dx%d = %d x %d mm dressed lumber (nominal %d x %d in; US/CA softwood, PS 20)." % [a, b, int(roundf(tt)), int(roundf(ww)), a, b], "mm": {"t": tt, "w": ww}, "span": [mt.get_start(), mt.get_end()]})
		else:
			unknown.append(mt.get_string(0).strip_edges())
		lum_spans.append([mt.get_start(), mt.get_end()])
	var s3 := _cut(off_map, lum_spans)
	var rest := s3
	# "two by four"
	re.compile("\\b(?:a |the )?(one|two|three|four|six) by (two|three|four|six|eight|ten|twelve)\\b")
	var nw := {"one": 1, "two": 2, "three": 3, "four": 4, "six": 6, "eight": 8, "ten": 10, "twelve": 12}
	var bs: Array = []
	for mt in re.search_all(rest):
		var a2 := int(nw[mt.get_string(1)])
		var b2 := int(nw[mt.get_string(2)])
		if NOM_T.has(a2) and NOM_W.has(b2):
			var tt2 := float(NOM_T[a2]) * IN
			var ww2 := float(NOM_W[b2]) * IN
			items.append({"kind": "lumber", "term": "%dx%d" % [a2, b2], "say": "%dx%d = %d x %d mm dressed lumber (nominal %d x %d in; US/CA softwood, PS 20)." % [a2, b2, int(roundf(tt2)), int(roundf(ww2)), a2, b2], "mm": {"t": tt2, "w": ww2}, "span": [mt.get_start(), mt.get_end()]})
		else:
			unknown.append(mt.get_string(0).strip_edges())
		bs.append([mt.get_start(), mt.get_end()])
	rest = _cut(rest, bs)
	# keys
	re.compile("\\b(sc|kw)(\\d+)\\b")
	var ks: Array = []
	for mt in re.search_all(rest):
		var k := mt.get_string(0)
		if KEYS.has(k):
			items.append({"kind": "key", "term": k.to_upper(), "say": String(KEYS[k]) + " Kine names it; the blank itself is not drawn.", "mm": {}, "span": [mt.get_start(), mt.get_end()]})
		else:
			unknown.append(k.to_upper())
		ks.append([mt.get_start(), mt.get_end()])
	rest = _cut(rest, ks)
	# Brazilian sawn timber (accents folded)
	var fold := rest.replace("ç", "c").replace("ã", "a")
	var brs: Array = []
	for nm in BR.keys():
		re.compile("\\b" + nm + "s?\\b")
		for mt in re.search_all(fold):
			var b: Dictionary = BR[nm]
			items.append({"kind": "br", "term": nm, "say": String(b["say"]), "mm": {"t": float(b["t"]), "w": float(b["w"])}, "span": [mt.get_start(), mt.get_end()]})
			brs.append([mt.get_start(), mt.get_end()])
	rest = _cut(fold, brs)
	return {"items": items, "unknown": unknown, "rest": rest}
