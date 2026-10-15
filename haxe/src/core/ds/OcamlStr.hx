package core.ds;

import haxe.io.Bytes;

// port: OCaml's `Str` library (otherlibs/str/str.ml and strstubs.c, OCaml 5.2), used by
// ... Hlinterp's regexp natives: the parser, the compiler to Str's bytecode and the backtracking
// ... NFA interpreter, over the bytes of a string (Str works on bytes, not characters).
// ... Only what Hlinterp needs is translated: `regexp`, `regexp_case_fold`, `search_forward`,
// ... `group_beginning` and `group_end`. The last search result is a static (upstream: a
// ... domain-local key).
private enum ReSyntax {
	RChar(c:Int);
	RString(s:Bytes);
	RCharClass(cl:Bytes, compl:Bool); /* true = complemented, false = normal */
	RSeq(rl:Array<ReSyntax>);
	RAlt(r1:ReSyntax, r2:ReSyntax);
	RStar(r:ReSyntax);
	RPlus(r:ReSyntax);
	ROption(r:ReSyntax);
	RGroup(n:Int, r:ReSyntax);
	RRefgroup(n:Int);
	RBol;
	REol;
	RWordboundary;
}

/** Representation of compiled regular expressions */
class OcamlStrRegexp {
	public final prog:Array<Int>; /* bytecode instructions */
	public final cpool:Array<Bytes>; /* constant pool (string literals) */
	public final normtable:Null<Bytes>; /* case folding table (if any) */
	public final numgroups:Int; /* number of \(...\) groups */
	public final numregisters:Int; /* number of nullable Star or Plus */
	public final startchars:Int; /* index of set of starting chars, or -1 if none */

	public function new(prog, cpool, normtable, numgroups, numregisters, startchars) {
		this.prog = prog;
		this.cpool = cpool;
		this.normtable = normtable;
		this.numgroups = numgroups;
		this.numregisters = numregisters;
		this.startchars = startchars;
	}
}

class OcamlStr {
	static function lowercaseLatin1(c:Int):Int {
		return if ((c >= 'A'.code && c <= 'Z'.code) || (c >= 192 && c <= 214) || (c >= 216 && c <= 222)) c + 32 else c;
	}

	static function uppercaseLatin1(c:Int):Int {
		return if ((c >= 'a'.code && c <= 'z'.code) || (c >= 224 && c <= 246) || (c >= 248 && c <= 254)) c - 32 else c;
	}

	/** Representation of character sets **/
	static function csFull():Bytes {
		var b = Bytes.alloc(32);
		b.fill(0, 32, 0xFF);
		return b;
	}

	static function csMakeEmpty():Bytes {
		var b = Bytes.alloc(32);
		b.fill(0, 32, 0);
		return b;
	}

	static function csAdd(s:Bytes, i:Int):Void {
		s.set(i >> 3, s.get(i >> 3) | (1 << (i & 7)));
	}

	static function csAddRange(s:Bytes, c1:Int, c2:Int):Void {
		for (i in c1...c2 + 1) csAdd(s, i);
	}

	static function csSingleton(c:Int):Bytes {
		var s = csMakeEmpty();
		csAdd(s, c);
		return s;
	}

	static function csComplement(s:Bytes):Bytes {
		var r = Bytes.alloc(32);
		for (i in 0...32) r.set(i, s.get(i) ^ 0xFF);
		return r;
	}

	static function csUnion(s1:Bytes, s2:Bytes):Bytes {
		var r = Bytes.alloc(32);
		for (i in 0...32) r.set(i, s1.get(i) | s2.get(i));
		return r;
	}

	static function csDisjoint(s1:Bytes, s2:Bytes):Bool {
		for (i in 0...32) if (s1.get(i) & s2.get(i) != 0) return false;
		return true;
	}

	static function csIter(fn:Int->Void, s:Bytes):Void {
		for (i in 0...32) {
			var c = s.get(i);
			if (c != 0) for (j in 0...8) if (c & (1 << j) != 0) fn((i << 3) + j);
		}
	}

	static function csExpand(s:Bytes):Bytes {
		var r = Bytes.alloc(256);
		r.fill(0, 256, 0);
		csIter(c -> r.set(c, 1), s);
		return r;
	}

	static function csFoldCase(s:Bytes):Bytes {
		var r = csMakeEmpty();
		csIter(c -> {
			csAdd(r, lowercaseLatin1(c));
			csAdd(r, uppercaseLatin1(c));
		}, s);
		return r;
	}

	/** Opcodes for bytecode instructions; see strstubs.c for description */
	static inline var op_CHAR = 0;

	static inline var op_CHARNORM = 1;
	static inline var op_STRING = 2;
	static inline var op_STRINGNORM = 3;
	static inline var op_CHARCLASS = 4;
	static inline var op_BOL = 5;
	static inline var op_EOL = 6;
	static inline var op_WORDBOUNDARY = 7;
	static inline var op_BEGGROUP = 8;
	static inline var op_ENDGROUP = 9;
	static inline var op_REFGROUP = 10;
	static inline var op_ACCEPT = 11;
	static inline var op_SIMPLEOPT = 12;
	static inline var op_SIMPLESTAR = 13;
	static inline var op_SIMPLEPLUS = 14;
	static inline var op_GOTO = 15;
	static inline var op_PUSHBACK = 16;
	static inline var op_SETMARK = 17;
	static inline var op_CHECKPROGRESS = 18;

	// Encoding of bytecode instructions
	static inline function instr(opc:Int, arg:Int):Int return opc | (arg << 8);

	// Computing relative displacements for GOTO and PUSHBACK instructions
	static inline function displ(dest:Int, from:Int):Int return dest - from - 1;

	/** Compilation of a regular expression */
	// Determine if a regexp can match the empty string
	static function isNullable(r:ReSyntax):Bool {
		return switch r {
			case RChar(_): false;
			case RString(s): s.length == 0;
			case RCharClass(_): false;
			case RSeq(rl): Lambda.foreach(rl, isNullable);
			case RAlt(r1, r2): isNullable(r1) || isNullable(r2);
			case RStar(_): true;
			case RPlus(r): isNullable(r);
			case ROption(_): true;
			case RGroup(_, r): isNullable(r);
			case RRefgroup(_): true;
			case RBol: true;
			case REol: true;
			case RWordboundary: true;
		}
	}

	/* first r returns a set of characters C such that:
		for all string s, s matches r => the first character of s is in C.
		For convenience, return Charset.full if r is nullable. */
	static function first(r:ReSyntax):Bytes {
		return switch r {
			case RChar(c): csSingleton(c);
			case RString(s): if (s.length == 0) csFull() else csSingleton(s.get(0));
			case RCharClass(cl, cmpl): if (cmpl) csComplement(cl) else cl;
			case RSeq(rl): firstSeq(rl, 0);
			case RAlt(r1, r2): csUnion(first(r1), first(r2));
			case RStar(_): csFull();
			case RPlus(r): first(r);
			case ROption(_): csFull();
			case RGroup(_, r): first(r);
			case RRefgroup(_): csFull();
			case RBol: csFull();
			case REol: csFull();
			case RWordboundary: csFull();
		}
	}

	static function firstSeq(rl:Array<ReSyntax>, i:Int):Bytes {
		if (i >= rl.length) return csFull();
		return switch rl[i] {
			case RBol | REol | RWordboundary: firstSeq(rl, i + 1);
			case RStar(r): csUnion(first(r), firstSeq(rl, i + 1));
			case ROption(r): csUnion(first(r), firstSeq(rl, i + 1));
			case r: first(r);
		}
	}

	// Transform a Char or CharClass regexp into a character class
	static function charclassOfRegexp(foldCase:Bool, re:ReSyntax):Bytes {
		var cl1, compl;
		switch re {
			case RChar(c):
				cl1 = csSingleton(c);
				compl = false;
			case RCharClass(cl, c):
				cl1 = cl;
				compl = c;
			case _:
				throw new haxe.Exception("assert false");
		}
		var cl2 = if (foldCase) csFoldCase(cl1) else cl1;
		return if (compl) csComplement(cl2) else cl2;
	}

	// The case fold table: maps characters to their lowercase equivalent
	static final foldCaseTable:Bytes = {
		var t = Bytes.alloc(256);
		for (i in 0...256) t.set(i, lowercaseLatin1(i));
		t;
	}

	static function bytesEq(a:Bytes, b:Bytes):Bool return a.length == b.length && a.compare(b) == 0;

	// Compilation of a regular expression
	static function compile(foldCase:Bool, re:ReSyntax):OcamlStrRegexp {
		// Instruction buffering
		var prog:Array<Int> = [];
		var cpool:Array<Bytes> = [];
		var numgroups = 1;
		var numregs = 0;
		// Add a new instruction
		function emitInstr(opc:Int, arg:Int):Void {
			prog.push(instr(opc, arg));
		}
		// Reserve an instruction slot and return its position
		function emitHole():Int {
			var p = prog.length;
			emitInstr(op_CHAR, 0);
			return p;
		}
		// Fill a reserved instruction slot with a GOTO or PUSHBACK instruction
		function patchInstr(pos:Int, opc:Int, dest:Int):Void {
			prog[pos] = instr(opc, displ(dest, pos));
		}
		// Return the cpool index for the given string, adding it if not
		// already there
		function cpoolIndex(s:Bytes):Int {
			for (i in 0...cpool.length) if (bytesEq(cpool[i], s)) return i;
			cpool.push(s);
			return cpool.length - 1;
		}
		// Allocate fresh register if regexp is nullable
		function allocateRegisterIfNullable(r:ReSyntax):Int {
			if (isNullable(r)) {
				var n = numregs;
				if (n >= 64) throw new Failure("too many r* or r+ where r is nullable");
				numregs++;
				return n;
			} else return -1;
		}
		function disjointModuloCase(c1:Bytes, c2:Bytes):Bool {
			return if (foldCase) csDisjoint(csFoldCase(c1), csFoldCase(c2)) else csDisjoint(c1, c2);
		}
		// Main recursive compilation function
		var emitSeqCode:(Array<ReSyntax>, Int) -> Void = null;
		function emitCode(r:ReSyntax):Void {
			switch r {
				case RChar(c):
					if (foldCase) emitInstr(op_CHARNORM, lowercaseLatin1(c)) else emitInstr(op_CHAR, c);
				case RString(s):
					switch s.length {
						case 0:
						case 1:
							if (foldCase) emitInstr(op_CHARNORM, lowercaseLatin1(s.get(0))) else emitInstr(op_CHAR, s.get(0));
						case _:
							// null characters are not accepted by the STRING* instructions;
							// if one is found, split string at null character
							var i = -1;
							for (k in 0...s.length) if (s.get(k) == 0) {
								i = k;
								break;
							}
							if (i >= 0) {
								emitCode(RString(s.sub(0, i)));
								emitInstr(op_CHAR, 0);
								emitCode(RString(s.sub(i + 1, s.length - i - 1)));
							} else {
								if (foldCase) {
									var l = Bytes.alloc(s.length);
									for (k in 0...s.length) l.set(k, lowercaseLatin1(s.get(k)));
									emitInstr(op_STRINGNORM, cpoolIndex(l));
								} else emitInstr(op_STRING, cpoolIndex(s));
							}
					}
				case RCharClass(cl, compl):
					var cl1 = if (foldCase) csFoldCase(cl) else cl;
					var cl2 = if (compl) csComplement(cl1) else cl1;
					emitInstr(op_CHARCLASS, cpoolIndex(cl2));
				case RSeq(rl):
					emitSeqCode(rl, 0);
				case RAlt(r1, r2):
					/*      PUSHBACK lbl1
							<match r1>
							GOTO lbl2
						lbl1: <match r2>
						lbl2: ... */
					var posPushback = emitHole();
					emitCode(r1);
					var posGotoEnd = emitHole();
					var lbl1 = prog.length;
					emitCode(r2);
					var lbl2 = prog.length;
					patchInstr(posPushback, op_PUSHBACK, lbl1);
					patchInstr(posGotoEnd, op_GOTO, lbl2);
				case RStar(r):
					// Implement longest match semantics for compatibility with old Str
					var regno = allocateRegisterIfNullable(r);
					var lbl1 = emitHole();
					if (regno >= 0) emitInstr(op_SETMARK, regno);
					emitCode(r);
					if (regno >= 0) emitInstr(op_CHECKPROGRESS, regno);
					emitInstr(op_GOTO, displ(lbl1, prog.length));
					var lbl2 = prog.length;
					patchInstr(lbl1, op_PUSHBACK, lbl2);
				case RPlus(r):
					// Implement longest match semantics for compatibility with old Str
					var regno = allocateRegisterIfNullable(r);
					var lbl1 = prog.length;
					emitCode(r);
					if (regno >= 0) emitInstr(op_CHECKPROGRESS, regno);
					var posPushback = emitHole();
					if (regno >= 0) emitInstr(op_SETMARK, regno);
					emitInstr(op_GOTO, displ(lbl1, prog.length));
					var lbl2 = prog.length;
					patchInstr(posPushback, op_PUSHBACK, lbl2);
				case ROption(r):
					// Implement longest match semantics for compatibility with old Str
					var posPushback = emitHole();
					emitCode(r);
					var lbl = prog.length;
					patchInstr(posPushback, op_PUSHBACK, lbl);
				case RGroup(n, r):
					emitInstr(op_BEGGROUP, n);
					emitCode(r);
					emitInstr(op_ENDGROUP, n);
					numgroups = numgroups > n + 1 ? numgroups : n + 1;
				case RRefgroup(n):
					emitInstr(op_REFGROUP, n);
					numgroups = numgroups > n + 1 ? numgroups : n + 1;
				case RBol:
					emitInstr(op_BOL, 0);
				case REol:
					emitInstr(op_EOL, 0);
				case RWordboundary:
					emitInstr(op_WORDBOUNDARY, 0);
			}
		}
		emitSeqCode = function(rl:Array<ReSyntax>, i:Int):Void {
			while (i < rl.length) {
				var r = rl[i];
				switch r {
					case RStar(r1 = RChar(_) | RCharClass(_)) if (disjointModuloCase(first(r1), firstSeq(rl, i + 1))):
						emitInstr(op_SIMPLESTAR, cpoolIndex(charclassOfRegexp(foldCase, r1)));
					case RPlus(r1 = RChar(_) | RCharClass(_)) if (disjointModuloCase(first(r1), firstSeq(rl, i + 1))):
						emitInstr(op_SIMPLEPLUS, cpoolIndex(charclassOfRegexp(foldCase, r1)));
					case ROption(r1 = RChar(_) | RCharClass(_)) if (disjointModuloCase(first(r1), firstSeq(rl, i + 1))):
						emitInstr(op_SIMPLEOPT, cpoolIndex(charclassOfRegexp(foldCase, r1)));
					case _:
						emitCode(r);
				}
				i++;
			}
		}
		emitCode(re);
		emitInstr(op_ACCEPT, 0);
		var start = first(re);
		var start2 = if (foldCase) csFoldCase(start) else start;
		var startPos = if (bytesEq(start, csFull())) -1 else cpoolIndex(csExpand(start2));
		return new OcamlStrRegexp(prog, cpool, if (foldCase) foldCaseTable else null, numgroups, numregs, startPos);
	}

	/** Parsing of a regular expression */
	// The character class corresponding to `.'
	static function dotclass():Bytes return csComplement(csSingleton('\n'.code));

	// Parse a regular expression
	static function parse(s:Bytes):ReSyntax {
		var len = s.length;
		var groupCounter = 1;
		function at(i:Int):Int {
			if (i < 0 || i >= len) throw new InvalidArgument("index out of bounds");
			return s.get(i);
		}
		// Efficient buffering of sequences
		function seqExtract(chars:haxe.io.BytesBuffer, next:Array<ReSyntax>):ReSyntax {
			var b = chars.getBytes();
			switch b.length {
				case 0:
				case 1:
					next.push(RChar(b.get(0)));
				case _:
					next.push(RString(b));
			}
			return RSeq(next);
		}
		var regexp0:Int->{r:ReSyntax, j:Int} = null;
		function regexpclass2(c:Bytes, start:Int, i:Int):Int {
			while (true) {
				if (i >= len) throw new Failure("[ class not closed by ]");
				if (at(i) == ']'.code && i > start) return i + 1;
				var c1 = at(i);
				if (i + 2 < len && at(i + 1) == '-'.code && at(i + 2) != ']'.code) {
					var c2 = at(i + 2);
					csAddRange(c, c1, c2);
					i += 3;
				} else {
					csAdd(c, c1);
					i += 1;
				}
			}
		}
		function regexpclass1(i:Int):{c:Bytes, j:Int} {
			var c = csMakeEmpty();
			var j = regexpclass2(c, i, i);
			return {c: c, j: j};
		}
		function regexpclass0(i:Int):{c:Bytes, compl:Bool, j:Int} {
			if (i < len && at(i) == '^'.code) {
				var r = regexpclass1(i + 1);
				return {c: r.c, compl: true, j: r.j};
			} else {
				var r = regexpclass1(i);
				return {c: r.c, compl: false, j: r.j};
			}
		}
		function regexpbackslash(i:Int):{r:ReSyntax, j:Int} {
			if (i >= len) return {r: RChar('\\'.code), j: i};
			var c = at(i);
			if (c == '|'.code || c == ')'.code) throw new haxe.Exception("assert false");
			if (c == '('.code) {
				var groupNo = groupCounter;
				groupCounter++;
				var rj = regexp0(i + 1);
				var j = rj.j;
				if (j + 1 < len && at(j) == '\\'.code && at(j + 1) == ')'.code) return {r: RGroup(groupNo, rj.r), j: j + 2};
				else throw new Failure("\\( group not closed by \\)");
			}
			if (c >= '1'.code && c <= '9'.code) return {r: RRefgroup(c - 48), j: i + 1};
			if (c == 'b'.code) return {r: RWordboundary, j: i + 1};
			return {r: RChar(c), j: i + 1};
		}
		function regexp3(i:Int):{r:ReSyntax, j:Int} {
			var c = at(i);
			if (c == '\\'.code) return regexpbackslash(i + 1);
			if (c == '['.code) {
				var r = regexpclass0(i + 1);
				return {r: RCharClass(r.c, r.compl), j: r.j};
			}
			if (c == '^'.code) return {r: RBol, j: i + 1};
			if (c == '$'.code) return {r: REol, j: i + 1};
			if (c == '.'.code) return {r: RCharClass(dotclass(), false), j: i + 1};
			return {r: RChar(c), j: i + 1};
		}
		function regexp2(i:Int):{r:ReSyntax, j:Int} {
			var rj = regexp3(i);
			var r = rj.r, i = rj.j;
			while (i < len) {
				var c = at(i);
				if (c == '?'.code) r = ROption(r);
				else if (c == '*'.code) r = RStar(r);
				else if (c == '+'.code) r = RPlus(r);
				else break;
				i++;
			}
			return {r: r, j: i};
		}
		function regexp1(i:Int):{r:ReSyntax, j:Int} {
			var chars = new haxe.io.BytesBuffer();
			var next:Array<ReSyntax> = [];
			while (true) {
				if (i >= len || (i + 2 <= len && at(i) == '\\'.code && (at(i + 1) == '|'.code || at(i + 1) == ')'.code)))
					return {r: seqExtract(chars, next), j: i};
				var rj = regexp2(i);
				switch rj.r {
					case RChar(c):
						chars.addByte(c);
					case re:
						// port: SeqBuffer.flush, then the element
						var b = chars.getBytes();
						chars = new haxe.io.BytesBuffer();
						switch b.length {
							case 0:
							case 1:
								next.push(RChar(b.get(0)));
							case _:
								next.push(RString(b));
						}
						next.push(re);
				}
				i = rj.j;
			}
		}
		regexp0 = function(i:Int):{r:ReSyntax, j:Int} {
			var rj = regexp1(i);
			var r1 = rj.r, i = rj.j;
			while (i + 2 <= len && at(i) == '\\'.code && at(i + 1) == '|'.code) {
				var rj2 = regexp1(i + 2);
				r1 = RAlt(r1, rj2.r);
				i = rj2.j;
			}
			return {r: r1, j: i};
		}
		var rj = regexp0(0);
		if (rj.j == len) return rj.r else throw new Failure("spurious \\) in regular expression");
	}

	/** Parsing and compilation */
	public static function regexp(e:Bytes):OcamlStrRegexp return compile(false, parse(e));

	public static function regexpCaseFold(e:Bytes):OcamlStrRegexp return compile(true, parse(e));

	/** Matching functions **/
	static var lastSearchResult:Array<Int> = [];

	// Determine if a character is a word constituent
	// PR#4874: word constituent = letter, digit, underscore.
	static final reWordLetters = [
		0x00, 0x00, 0x00, 0x00, /* 0x00-0x1F: none */
		0x00, 0x00, 0xFF, 0x03, /* 0x20-0x3F: digits 0-9 */
		0xFE, 0xFF, 0xFF, 0x87, /* 0x40-0x5F: A to Z, _ */
		0xFE, 0xFF, 0xFF, 0x07, /* 0x60-0x7F: a to z */
		0x00, 0x00, 0x00, 0x00, /* 0x80-0x9F: none */
		0x00, 0x00, 0x00, 0x00, /* 0xA0-0xBF: none */
		0xFF, 0xFF, 0x7F, 0xFF, /* 0xC0-0xDF: Latin-1 accented uppercase */
		0xFF, 0xFF, 0x7F, 0xFF /* 0xE0-0xFF: Latin-1 accented lowercase */
	];

	static inline function isWordLetter(c:Int):Bool return (reWordLetters[c >> 3] >> (c & 7)) & 1 != 0;

	static inline function inBitset(s:Bytes, i:Int):Bool return (s.get(i >> 3) >> (i & 7)) & 1 != 0;

	/* The bytecode interpreter for the NFA.
		Return array of matched groups on success, null on failure. */
	// port: positions are byte offsets; NULL is -1. A backtrack point is a (kind, a, b)
	// ... triple: kind 0 is a program point (a = pc, b = txt); 1, 2 and 3 undo a group start,
	// ... a group end and a progress register (a = index, b = previous value).
	static function reMatch(re:OcamlStrRegexp, str:Bytes, txt:Int, endtxt:Int, acceptPartialMatch:Bool):Null<Array<Int>> {
		var numgroups = re.numgroups;
		var gstart = [for (_ in 0...numgroups) -1];
		var gend = [for (_ in 0...numgroups) -1];
		var reRegister = [for (_ in 0...64) -1];
		var prog = re.prog;
		var cpool = re.cpool;
		var normtable = re.normtable;
		var pc = 0;
		var stKind:Array<Int> = [], stA:Array<Int> = [], stB:Array<Int> = [];
		gstart[0] = txt;
		while (true) {
			var instr = prog[pc++];
			var arg = instr >>> 8;
			// port: `goto push`, `goto prefix_match`, `goto backtrack` and `goto accept`
			var fail = false;
			switch instr & 0xFF {
				case 0: // port: CHAR
					if (txt == endtxt) {
						if (acceptPartialMatch) break;
						fail = true;
					} else if (str.get(txt) != arg) fail = true;
					else txt++;
				case 1: // port: CHARNORM
					if (txt == endtxt) {
						if (acceptPartialMatch) break;
						fail = true;
					} else if (normtable.get(str.get(txt)) != arg) fail = true;
					else txt++;
				case 2 | 3: // port: STRING, STRINGNORM
					var s = cpool[arg];
					var norm = (instr & 0xFF) == 3;
					var k = 0;
					var partial = false;
					while (k < s.length) {
						var c = s.get(k++);
						if (txt == endtxt) {
							partial = true;
							break;
						}
						if (c != (norm ? normtable.get(str.get(txt)) : str.get(txt))) {
							fail = true;
							break;
						}
						txt++;
					}
					if (partial) {
						if (acceptPartialMatch) break;
						fail = true;
					}
				case 4: // port: CHARCLASS
					if (txt == endtxt) {
						if (acceptPartialMatch) break;
						fail = true;
					} else if (!inBitset(cpool[arg], str.get(txt))) fail = true;
					else txt++;
				case 5: // port: BOL
					if (txt > 0 && str.get(txt - 1) != '\n'.code) fail = true;
				case 6: // port: EOL
					if (txt < endtxt && str.get(txt) != '\n'.code) fail = true;
				case 7: // port: WORDBOUNDARY
					/* At beginning and end of text: no
						At beginning of text: OK if current char is a letter
						At end of text: OK if previous char is a letter
						Otherwise:
						OK if previous char is a letter and current char not a letter
						or previous char is not a letter and current char is a letter */
					if (txt == 0) {
						if (txt == endtxt) {
							if (acceptPartialMatch) break;
							fail = true;
						} else if (!isWordLetter(str.get(txt))) fail = true;
					} else if (txt == endtxt) {
						if (!isWordLetter(str.get(txt - 1))) fail = true;
					} else {
						if (isWordLetter(str.get(txt - 1)) == isWordLetter(str.get(txt))) fail = true;
					}
				case 8: // port: BEGGROUP
					stKind.push(1);
					stA.push(arg);
					stB.push(gstart[arg]);
					gstart[arg] = txt;
				case 9: // port: ENDGROUP
					stKind.push(2);
					stA.push(arg);
					stB.push(gend[arg]);
					gend[arg] = txt;
				case 10: // port: REFGROUP
					var s = gstart[arg], e = gend[arg];
					if (s == -1 || e == -1) fail = true;
					else {
						var partial = false;
						while (s < e) {
							if (txt == endtxt) {
								partial = true;
								break;
							}
							if (str.get(s) != str.get(txt)) {
								fail = true;
								break;
							}
							txt++;
							s++;
						}
						if (partial) {
							if (acceptPartialMatch) break;
							fail = true;
						}
					}
				case 11: // port: ACCEPT
					break;
				case 12: // port: SIMPLEOPT
					if (txt < endtxt && inBitset(cpool[arg], str.get(txt))) txt++;
				case 13: // port: SIMPLESTAR
					var set = cpool[arg];
					while (txt < endtxt && inBitset(set, str.get(txt)))
						txt++;
				case 14: // port: SIMPLEPLUS
					var set = cpool[arg];
					if (txt == endtxt) {
						if (acceptPartialMatch) break;
						fail = true;
					} else if (!inBitset(set, str.get(txt))) fail = true;
					else {
						txt++;
						while (txt < endtxt && inBitset(set, str.get(txt)))
							txt++;
					}
				case 15: // port: GOTO
					pc = pc + (instr >> 8);
				case 16: // port: PUSHBACK
					stKind.push(0);
					stA.push(pc + (instr >> 8));
					stB.push(txt);
				case 17: // port: SETMARK
					stKind.push(3);
					stA.push(arg);
					stB.push(reRegister[arg]);
					reRegister[arg] = txt;
				case 18: // port: CHECKPROGRESS
					if (reRegister[arg] == txt) fail = true;
				case _:
					throw new haxe.Exception("impossible case in re_match");
			}
			if (fail) {
				/* We get here when matching fails.  Backtrack to most recent saved
					program point, undoing variable assignments on the way. */
				while (true) {
					if (stKind.length == 0) return null;
					var k = stKind.pop(), a = stA.pop(), b = stB.pop();
					if (k == 0) {
						pc = a;
						txt = b;
						break;
					} else if (k == 1) gstart[a] = b;
					else if (k == 2) gend[a] = b;
					else reRegister[a] = b;
				}
			}
		}
		/* We get here when the regexp was successfully matched */
		gend[0] = txt;
		var res = [];
		for (i in 0...numgroups) {
			if (gstart[i] == -1 || gend[i] == -1) {
				res.push(-1);
				res.push(-1);
			} else {
				res.push(gstart[i]);
				res.push(gend[i]);
			}
		}
		return res;
	}

	static function reSearchForward(re:OcamlStrRegexp, str:Bytes, startpos:Int):Array<Int> {
		var txt = startpos;
		var endtxt = str.length;
		if (txt < 0 || txt > endtxt) throw new InvalidArgument("Str.search_forward");
		if (re.startchars == -1) {
			do {
				var res = reMatch(re, str, txt, endtxt, false);
				if (res != null) return res;
				txt++;
			} while (txt <= endtxt);
			return [];
		} else {
			var startchars = re.cpool[re.startchars];
			do {
				while (txt < endtxt && startchars.get(str.get(txt)) == 0)
					txt++;
				var res = reMatch(re, str, txt, endtxt, false);
				if (res != null) return res;
				txt++;
			} while (txt <= endtxt);
			return [];
		}
	}

	public static function searchForward(re:OcamlStrRegexp, s:Bytes, pos:Int):Int {
		var res = reSearchForward(re, s, pos);
		lastSearchResult = res;
		if (res.length == 0) throw NotFound.raise() else return res[0];
	}

	public static function groupBeginning(n:Int):Int {
		var n2 = n + n;
		if (n < 0 || n2 >= lastSearchResult.length) throw new InvalidArgument("Str.group_beginning");
		var pos = lastSearchResult[n2];
		if (pos == -1) throw NotFound.raise() else return pos;
	}

	public static function groupEnd(n:Int):Int {
		var n2 = n + n;
		if (n < 0 || n2 >= lastSearchResult.length) throw new InvalidArgument("Str.group_end");
		var pos = lastSearchResult[n2 + 1];
		if (pos == -1) throw NotFound.raise() else return pos;
	}
}
