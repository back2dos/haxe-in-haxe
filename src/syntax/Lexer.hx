package syntax;

import core.Ast.Binop;
import core.Ast.Keyword;
import core.Ast.StringLiteralKind;
import core.Ast.Token;
import core.Ast.Unop;
import core.Globals.Pos;

// Port of the batch-tokenization portion of haxe/src/syntax/lexer.ml.
// XML lexing and display-specific parser entry points remain with the parser.
enum LexerErrorMsg {
	InvalidCharacter(code:Int);
	UnterminatedString;
	UnterminatedRegexp;
	UnclosedComment;
	InvalidEscape(value:String);
	InvalidRegexpOption;
	UnterminatedMarkup;
}

class LexerError {
	public final message:LexerErrorMsg;
	public final pos:Pos;
	public function new(message, pos) { this.message = message; this.pos = pos; }
}

typedef LexedToken = { var token:Token; var pos:Pos; }
typedef LexerFile = {var lfile:String; var lline:Int; var lmaxline:Int; var llines:Array<{offset:Int,line:Int}>; var lalines:Array<{offset:Int,line:Int}>; var llast:Int; var llastindex:Int;}
typedef LexerContext = {var file:LexerFile; var buf:StringBuf;}

class Lexer {
	public static function isWhitespace(value:String):Bool return value==" "||value=="\n"||value=="\r"||value=="\t";
	public static function stringIsWhitespace(value:String):Bool {for(i in 0...value.length) if(" \n\r\t".indexOf(value.charAt(i))<0)return false;return true;}
	static var allFiles = new haxe.ds.StringMap<LexerFile>();
	public static function createFileCtx(file:String):LexerContext {var ctx=createTempCtx(file);allFiles.set(file,ctx.file);return ctx;}
	public static function resolveFileContentPos(file:String,content:String):LexerFile {
		var f=createTempCtx(file).file;
		// Upstream consumes UTF-8 bytes, but stores character offsets.
		var bytes=haxe.io.Bytes.ofString(content),i=0,p=0;
		while(i<bytes.length) {
			var c=bytes.get(i++),inc=1;
			if(c==10 || c==13) {
				if(c==13) {i++;inc=2;}
				f.lline++;f.llines.unshift({offset:p+inc,line:f.lline});
			} else if(c>=0xC0) i+=c<0xE0?1:c<0xF0?2:3;
			p+=inc;
		}
		return f;
	}
	public static function findFile(file:String):LexerFile {
		var f=allFiles.get(file);
		if(f==null) {try f=resolveFileContentPos(file,sys.io.File.getContent(file)) catch(_:Dynamic) f=createTempCtx(file).file;allFiles.set(file,f);}
		return f;
	}
	public static function findLine(p:Int,f:LexerFile):{line:Int,column:Int} {
		if(f.lmaxline!=f.lline) {f.lmaxline=f.lline;f.lalines=f.llines.copy();f.lalines.reverse();f.llast=0x7FFFFFFF;f.llastindex=0;}
		function loop(min:Int,max:Int):{line:Int,column:Int} {
			var med=(min+max)>>>1,entry=f.lalines[med];
			if(med==min) {f.llast=p;f.llastindex=med;return {line:entry.line,column:p-entry.offset};}
			return entry.offset>p?loop(min,med):loop(med,max);
		}
		if(p>=f.llast) {var entry=f.lalines[f.llastindex],next=f.llastindex==f.lalines.length-1?0x7FFFFFFF:f.lalines[f.llastindex+1].offset;if(p>=entry.offset&&p<next)return {line:entry.line,column:p-entry.offset};}
		return loop(0,f.lalines.length);
	}
	public static function findPos(p:Pos):{line:Int,column:Int} return findLine(p.pmin,findFile(p.pfile));
	public static function getErrorLine(p:Pos):Int return findPos(p).line;
	public static function getPosCoords(p:Pos):{lineStart:Int,columnStart:Int,lineEnd:Int,columnEnd:Int} {var file=findFile(p.pfile),a=findLine(p.pmin,file),b=findLine(p.pmax,file);return {lineStart:a.line,columnStart:a.column+1,lineEnd:b.line,columnEnd:b.column+1};}
	public static function getErrorPos(printer:String->Int->String,p:Pos):String {
		if(p.pmin == -1) return "(unknown)";
		var c=getPosCoords(p),prefix=printer(p.pfile,c.lineStart);
		return c.lineStart==c.lineEnd?prefix+" character"+(c.columnStart==c.columnEnd?" "+c.columnStart:"s "+c.columnStart+"-"+c.columnEnd):prefix+" lines "+c.lineStart+"-"+c.lineEnd;
	}
	public static function isValidIdentifier(value:String):Bool {
		if(value.length==0) return false;
		for(i in 0...value.length) if(!isIdentStart(value.charAt(i)) && !(i>0 && isDigit(value.charAt(i)))) return false;
		return switch keyword(value) {case Const(Ident(_)):true;case _:false;};
	}
	public static function createTempCtx(file:String):LexerContext return {file:{lfile:file,lline:1,lmaxline:1,llines:[{offset:0,line:1}],lalines:[{offset:0,line:1}],llast:0x7FFFFFFF,llastindex:0},buf:new StringBuf()};
	public static function lexbufFromUtf8String(source:String):Lexer return new Lexer(source);
	public static function reset(ctx:LexerContext):Void ctx.buf=new StringBuf();
	public static function contents(ctx:LexerContext):String return ctx.buf.toString();
	public static function skipHeader(code:Lexer):Void {
		while (true) {
			if (code.current()==String.fromCharCode(0xFEFF)) code.index++;
			else if (code.starts("#!")) while (!code.eof() && code.current()!="\n" && code.current()!="\r") code.index++;
			else return;
		}
	}
	static function updateLines(ctx:LexerContext,code:Lexer,start:Int):Void {
		var i=start;
		while (i<code.index) {
			var c=code.source.charAt(i++);
			if (c=="\r" && code.source.charAt(i)=="\n") i++;
			if (c=="\r" || c=="\n") {ctx.file.lline++;ctx.file.llines.unshift({offset:i,line:ctx.file.lline});}
		}
	}
	public static function readToken(ctx:LexerContext,code:Lexer):LexedToken {
		code.file=ctx.file.lfile;
		var start=code.index;
		var result=code.token();
		updateLines(ctx,code,start);
		return result;
	}
	public static function sharpToken(ctx:LexerContext,code:Lexer):LexedToken {
		code.file=ctx.file.lfile;
		var start=code.index;
		code.skipWhitespace();
		while (code.starts("/*")) {code.comment(code.index);code.skipWhitespace();}
		var tokenStart=code.index;
		var result:LexedToken;
		if (isIdentStart(code.current())) {
			code.index++;
			while (isIdentPart(code.current()) || (code.current()=="." && isIdentStart(code.peek(1)))) code.index++;
			result=code.make(Const(core.Ast.Constant.Ident(code.source.substr(tokenStart,code.index-tokenStart))),tokenStart);
		} else result=code.token();
		updateLines(ctx,code,start);
		return result;
	}
	static function xmlNameStart(code:Int):Bool return code==36 || code==58 || code==95 || (code>=65&&code<=90) || (code>=97&&code<=122) || (code>=0xC0&&code<=0xD6) || (code>=0xD8&&code<=0xF6) || (code>=0xF8&&code<=0x2FF) || (code>=0x370&&code<=0x37D) || (code>=0x37F&&code<=0x1FFF) || (code>=0x200C&&code<=0x200D) || (code>=0x2070&&code<=0x218F) || (code>=0x2C00&&code<=0x2FEF) || (code>=0x3001&&code<=0xD7FF) || (code>=0xF900&&code<=0xFDCF) || (code>=0xFDF0&&code<=0xFFFD) || (code>=0x10000&&code<=0xEFFFF);
	function xmlName():String {
		var start=index;
		if (!eof() && xmlNameStart(current().charCodeAt(0))) {
			index++;
			while (!eof()) {var c=current().charCodeAt(0);if (!(xmlNameStart(c)||c==45||c==46||(c>=48&&c<=57)||c==0xB7||(c>=0x300&&c<=0x36F)||(c>=0x203F&&c<=0x2040))) break;index++;}
		}
		return source.substr(start,index-start);
	}
	public static function lexXml(ctx:LexerContext,p:Int,code:Lexer):Int {
		code.file=ctx.file.lfile;
		if (p+1!=code.index) code.fail(InvalidCharacter(code.current().charCodeAt(0)),code.index);
		var start=code.index, name=code.xmlName();
		ctx.buf.add("<"+name);
		var open="<"+name, close="</"+name+">", depth=0, inOpen=name!="";
		while (!code.eof()) {
			var offset=code.index;
			if (code.starts("</")) {
				code.index+=2;code.xmlName();
				if (code.current()==">") {
					code.index++;
					var tag=code.source.substr(offset,code.index-offset);ctx.buf.add(tag);
					if (tag==close) {if (depth==0) {updateLines(ctx,code,start);return code.index;} depth--;}
					inOpen=false;continue;
				}
				code.index=offset;
			}
			if (code.current()=="<") {
				code.index++;code.xmlName();var tag=code.source.substr(offset,code.index-offset);ctx.buf.add(tag);
				if (tag==open) {depth++;inOpen=true;} else inOpen=false;
			} else if (code.starts("/>")) {
				code.index+=2;ctx.buf.add("/>");if (inOpen) depth--;
				if (depth<0) {updateLines(ctx,code,start);return code.index;} inOpen=false;
			} else {ctx.buf.add(code.current());code.index++;}
		}
		code.fail(UnterminatedMarkup,p);return 0;
	}
	public static function errorMsg(error:LexerErrorMsg):String return switch error {
		case InvalidCharacter(c):c>32&&c<128?"Invalid character '"+String.fromCharCode(c)+"'":"Invalid character 0x"+StringTools.hex(c,2);
		case UnterminatedString:"Unterminated string";case UnterminatedRegexp:"Unterminated regular expression";case UnclosedComment:"Unclosed comment";
		case InvalidEscape(value):"Invalid escape sequence \\"+value;case InvalidRegexpOption:"Invalid regular expression option";case UnterminatedMarkup:"Unterminated markup literal";
	};
	var source:String;
	var file:String;
	var index:Int;

	public function new(source:String, ?file = "?") {
		this.source = source;
		this.file = file;
		index = source.charCodeAt(0) == 0xFEFF ? 1 : 0;
	}

	public static function lex(source:String, ?file = "?"):Array<LexedToken> {
		var lexer = new Lexer(source, file);
		var result = [];
		while (true) {
			var value = lexer.token();
			result.push(value);
			if (value.token.match(Eof)) return result;
		}
	}

	public function token():LexedToken {
		skipWhitespace();
		var start = index;
		if (eof()) return make(Eof, start);
		var c = current();
		if (isDigit(c) || (c == "." && isDigit(peek(1)))) return number(start);
		if (isIdentStart(c) || (c == "_" && isDigit(peek(1)))) return identifier(start);
		if (c == "/" && peek(1) == "/") return lineComment(start);
		if (c == "/" && peek(1) == "*") return comment(start);
		if (c == '"') return quotedString(start, false);
		if (c == "'") return quotedString(start, true);
		if (c == "~" && peek(1) == "/") return regexp(start);
		if (c == "#" && isIdentStart(peek(1))) { index += 2; while (isIdentPart(current())) index++; return make(Sharp(source.substr(start + 1, index - start - 1)), start); }
		if (c == "$") { index++; while (isIdentPart(current())) index++; return make(Dollar(source.substr(start + 1, index - start - 1)), start); }

		for (entry in operators) if (starts(entry.text)) { index += entry.text.length; return make(entry.token, start); }
		fail(InvalidCharacter(c.charCodeAt(0)), start);
		return null;
	}

	function number(start:Int):LexedToken {
		var isFloat = false;
		if (starts("0x") || starts("0X")) { index += 2; consumeDigits(isHexDigit); return suffix(start, false); }
		if (starts("0b") || starts("0B")) { index += 2; consumeDigits(function(c) return c == "0" || c == "1"); return suffix(start, false); }
		if (current() == ".") { isFloat = true; index++; consumeDigits(isDigit); }
		else {
			consumeDigits(isDigit);
			if (starts("...")) { var value = source.substr(start, index - start); index += 3; return make(IntInterval(value), start); }
			if (current() == "." && !starts("...") && !isIdentStart(peek(1))) { isFloat = true; index++; consumeDigits(isDigit); }
		}
		if (current() == "e" || current() == "E") { isFloat = true; index++; if (current() == "+" || current() == "-") index++; consumeDigits(isDigit); }
		return suffix(start, isFloat);
	}

	function suffix(start:Int, isFloat:Bool):LexedToken {
		var hasFloatSuffix = current() == "f" || (current() == "_" && peek(1) == "f");
		if ((current() == "_" && (peek(1) == "i" || peek(1) == "u" || peek(1) == "f")) || current() == "i" || current() == "u" || current() == "f") {
			if (current() == "_") index++;
			var prefix = current();
			index++;
			while (isDigit(current())) index++;
			if ((prefix != "i" && prefix != "u" && prefix != "f") || index == start) fail(InvalidCharacter(prefix.charCodeAt(0)), start);
		}
		var raw = source.substr(start, index - start);
		var pivot = -1;
		for (i in 0...raw.length) { var c = raw.charAt(i); if (c == "i" || c == "u" || ((isFloat || hasFloatSuffix) && c == "f")) { pivot = i; break; } }
		var literal = pivot < 0 ? raw : raw.substr(0, pivot > 0 && raw.charAt(pivot - 1) == "_" ? pivot - 1 : pivot);
		var ending:Null<String> = pivot < 0 ? null : raw.substr(pivot);
		return make(isFloat || hasFloatSuffix ? Const(core.Ast.Constant.Float(literal, ending)) : Const(core.Ast.Constant.Int(literal, ending)), start);
	}

	function identifier(start:Int):LexedToken {
		index++;
		while (isIdentPart(current())) index++;
		var value = source.substr(start, index - start);
		return make(keyword(value), start);
	}

	function lineComment(start:Int):LexedToken { index += 2; var content = index; while (!eof() && current() != "\n" && current() != "\r") index++; return make(CommentLine(source.substr(content, index - content)), start); }
	function comment(start:Int):LexedToken {
		index += 2; var content = index;
		while (!eof() && !(current() == "*" && peek(1) == "/")) index++;
		if (eof()) fail(UnclosedComment, start);
		var value = source.substr(content, index - content); index += 2;
		return make(Comment(value), start);
	}

	function quotedString(start:Int, single:Bool):LexedToken {
		var quote = current(); index++; var buffer = new StringBuf();
		while (!eof() && current() != quote) {
			if (current() == "\\") {
				var escapePos = index++;
				if (eof()) fail(UnterminatedString, start);
				if (current() == "x") {
					if (!isHexDigit(peek(1)) || !isHexDigit(peek(2))) fail(InvalidEscape("x"), escapePos);
					buffer.add(String.fromCharCode(Std.parseInt("0x" + peek(1) + peek(2))));
					index += 3;
				} else if (current() == "u" && peek(1) == "{") {
					index += 2;
					var digitsStart = index;
					while (isHexDigit(current()) && index - digitsStart < 6) index++;
					if (index == digitsStart || current() != "}") fail(InvalidEscape("u"), escapePos);
					var code = Std.parseInt("0x" + source.substr(digitsStart, index - digitsStart));
					if (code == null || code > 0x10FFFF) fail(InvalidEscape("u"), escapePos);
					buffer.add(String.fromCharCode(code));
					index++;
				} else if (current() == "u") {
					if (!isHexDigit(peek(1)) || !isHexDigit(peek(2)) || !isHexDigit(peek(3)) || !isHexDigit(peek(4))) fail(InvalidEscape("u"), escapePos);
					buffer.add(String.fromCharCode(Std.parseInt("0x" + peek(1) + peek(2) + peek(3) + peek(4))));
					index += 5;
				} else { buffer.add(unescape(current(), escapePos)); index++; }
			}
			else { buffer.add(current()); index++; }
		}
		if (eof()) fail(UnterminatedString, start);
		index++;
		return make(Const(core.Ast.Constant.String(buffer.toString(), single ? SSingleQuotes : SDoubleQuotes)), start);
	}

	function regexp(start:Int):LexedToken {
		index += 2; var buffer = new StringBuf();
		while (!eof() && current() != "/" && current() != "\n" && current() != "\r") {
			if (current() == "\\") { buffer.add(current()); index++; if (eof()) fail(UnterminatedRegexp, start); }
			buffer.add(current()); index++;
		}
		if (eof() || current() != "/") fail(UnterminatedRegexp, start);
		index++; var options = "";
		while (!eof() && current() >= "a" && current() <= "z") { var c = current(); if ("gimsu".indexOf(c) < 0) fail(InvalidRegexpOption, index); options += c; index++; }
		return make(Const(core.Ast.Constant.Regexp(buffer.toString(), options)), start);
	}

	function unescape(c:String, pos:Int):String return switch c { case "n": "\n"; case "r": "\r"; case "t": "\t"; case "b": String.fromCharCode(8); case "f": String.fromCharCode(12); case "v": String.fromCharCode(11); case "\\" | "\"" | "'": c; default: fail(InvalidEscape(c), pos); ""; }
	function skipWhitespace():Void while (!eof() && (current() == " " || current() == "\t" || current() == "\n" || current() == "\r")) index++;
	function consumeDigits(check:String->Bool):Void { if (!check(current())) return; index++; while (check(current()) || (current() == "_" && check(peek(1)))) index++; }
	function make(token:Token, start:Int):LexedToken return {token: token, pos: {pfile: file, pmin: start, pmax: index}};
	function fail(message:LexerErrorMsg, at:Int):Void throw new LexerError(message, {pfile: file, pmin: at, pmax: at});
	inline function eof():Bool return index >= source.length;
	inline function current():String return eof() ? "" : source.charAt(index);
	inline function peek(offset:Int):String return index + offset >= source.length ? "" : source.charAt(index + offset);
	inline function starts(value:String):Bool return source.substr(index, value.length) == value;
	static inline function isDigit(c:String):Bool return c >= "0" && c <= "9";
	static inline function isHexDigit(c:String):Bool return isDigit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F");
	static inline function isIdentStart(c:String):Bool return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
	static inline function isIdentPart(c:String):Bool return isIdentStart(c) || isDigit(c);

	static function keyword(value:String):Token return switch value {
		case "function": Kwd(Function); case "class": Kwd(Class); case "var": Kwd(Var); case "if": Kwd(If); case "else": Kwd(Else); case "while": Kwd(While); case "do": Kwd(Do); case "for": Kwd(For); case "break": Kwd(Break); case "continue": Kwd(Continue); case "return": Kwd(Return); case "extends": Kwd(Extends); case "implements": Kwd(Implements); case "import": Kwd(Import); case "switch": Kwd(Switch); case "case": Kwd(Case); case "default": Kwd(Default); case "static": Kwd(Static); case "public": Kwd(Public); case "private": Kwd(Private); case "try": Kwd(Try); case "catch": Kwd(Catch); case "new": Kwd(New); case "this": Kwd(This); case "throw": Kwd(Throw); case "extern": Kwd(Extern); case "enum": Kwd(Enum); case "in": Kwd(In); case "interface": Kwd(Interface); case "untyped": Kwd(Untyped); case "cast": Kwd(Cast); case "override": Kwd(Override); case "typedef": Kwd(Typedef); case "dynamic": Kwd(Dynamic); case "package": Kwd(Package); case "inline": Kwd(Inline); case "using": Kwd(Using); case "null": Kwd(Null); case "true": Kwd(True); case "false": Kwd(False); case "abstract": Kwd(Abstract); case "macro": Kwd(Macro); case "final": Kwd(Final); case "operator": Kwd(Operator); case "overload": Kwd(Overload); case _: Const(core.Ast.Constant.Ident(value));
	}

	static final operators:Array<{text:String, token:Token}> = [
		{text: ">>>=", token: Binop(OpAssignOp(OpUShr))}, {text: "<<=", token: Binop(OpAssignOp(OpShl))}, {text: ">>=", token: Binop(OpAssignOp(OpShr))}, {text: "||=", token: Binop(OpAssignOp(OpBoolOr))}, {text: "&&=", token: Binop(OpAssignOp(OpBoolAnd))}, {text: "??=", token: Binop(OpAssignOp(OpNullCoal))}, {text: "%=", token: Binop(OpAssignOp(OpMod))}, {text: "&=", token: Binop(OpAssignOp(OpAnd))}, {text: "|=", token: Binop(OpAssignOp(OpOr))}, {text: "^=", token: Binop(OpAssignOp(OpXor))}, {text: "+=", token: Binop(OpAssignOp(OpAdd))}, {text: "-=", token: Binop(OpAssignOp(OpSub))}, {text: "*=", token: Binop(OpAssignOp(OpMult))}, {text: "/=", token: Binop(OpAssignOp(OpDiv))},
		{text: ">>>", token: Binop(OpUShr)}, {text: "++", token: Unop(Increment)}, {text: "--", token: Unop(Decrement)}, {text: "==", token: Binop(OpEq)}, {text: "!=", token: Binop(OpNotEq)}, {text: "<=", token: Binop(OpLte)}, {text: ">=", token: Binop(OpGte)}, {text: "&&", token: Binop(OpBoolAnd)}, {text: "||", token: Binop(OpBoolOr)}, {text: "<<", token: Binop(OpShl)}, {text: ">>", token: Binop(OpShr)}, {text: "->", token: Arrow}, {text: "...", token: Spread}, {text: "=>", token: Binop(OpArrow)}, {text: "?.", token: QuestionDot}, {text: "??", token: Binop(OpNullCoal)},
		{text: "~", token: Unop(NegBits)}, {text: "!", token: Unop(Not)}, {text: "<", token: Binop(OpLt)}, {text: ">", token: Binop(OpGt)}, {text: ";", token: Semicolon}, {text: ":", token: DblDot}, {text: ",", token: Comma}, {text: ".", token: Dot}, {text: "%", token: Binop(OpMod)}, {text: "&", token: Binop(OpAnd)}, {text: "|", token: Binop(OpOr)}, {text: "^", token: Binop(OpXor)}, {text: "+", token: Binop(OpAdd)}, {text: "*", token: Binop(OpMult)}, {text: "/", token: Binop(OpDiv)}, {text: "-", token: Binop(OpSub)}, {text: "=", token: Binop(OpAssign)}, {text: "[", token: BkOpen}, {text: "]", token: BkClose}, {text: "{", token: BrOpen}, {text: "}", token: BrClose}, {text: "(", token: POpen}, {text: ")", token: PClose}, {text: "?", token: Question}, {text: "@", token: At}
	];
}
