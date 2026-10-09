package context;
import core.Globals;
import core.Globals.Pos;
import core.Ast;
import syntax.Parser;
import syntax.ParserEntry;
import syntax.Lexer;
import core.Error as CompilerError;
// Draft mechanical translation of haxe/src/context/formatString.ml; unvalidated.
class FormatString {
	public static function formatString(config:Dynamic, s:String, p:Pos, processExpr:ExprDef->Pos->Expr):Expr {
		var result:Null<Expr> = null;
		var pmin = p.pmin;
		var min = p.pmin + 1;
		inline function positioned(a:Int, b:Int):Pos return {pfile:p.pfile, pmin:a, pmax:b};
		inline function addExpr(next:Expr, len:Int):Void {
			min += len;
			var processed = processExpr(next.expr, next.pos);
			if (result == null) result = processed;
			else result = {expr:EBinop(OpAdd,result,processed), pos:Ast.punion(result.pos,next.pos)};
		}
		inline function add(next:ExprDef, len:Int):Void addExpr({expr:next, pos:positioned(min,min+len)},len);
		inline function addSub(start:Int, pos:Int):Void {
			var len = pos-start;
			if (len > 0 || result == null) add(EConst(String(s.substr(start,len),SDoubleQuotes)),len);
		}
		var len = s.length;
		inline function identStart(c:String):Bool return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
		var parse:Int->Int->Void = null;
		inline function parseGroup(start:Int, pos:Int, gopen:String, gclose:String, gname:String):Void {
			addSub(start,pos-1);
			var groups = [pos];
			var send = pos+1;
			while (true) {
				if (send == len) {
					if (groups.length == 0) throw "formatString: impossible empty group stack";
					var g = groups[0];
					CompilerError.raiseTypingError("Unclosed " + gname, positioned(pmin+g+1,pmin+g+2));
				}
				var c = s.charAt(send);
				if (c == gopen) groups.unshift(send);
				else if (c == gclose) {
					groups.shift();
					if (groups.length == 0) break;
				}
				send++;
			}
			var slen = send-pos-1;
			var scode = s.substr(pos+1,slen);
			min += 2;
			var ep = positioned(pmin+pos+2,pmin+send+1);
			function error(msg:String, pos:Pos):Dynamic {
				return Lexer.stringIsWhitespace(scode)
					? CompilerError.raiseTypingError("Expression cannot be empty",ep)
					: CompilerError.raiseTypingError(msg,pos);
			}
			var expr = switch ParserEntry.parseExprString(config,scode,ep,error,true) {
				case ParseSuccess(data,_): data;
				case ParseError(_,err,_): error(Parser.errorMsg(err.message),err.pos);
			};
			addExpr(expr,slen);
			min++;
			parse(send+1,send+1);
		}
		parse = function(start:Int, pos:Int):Void {
			if (pos == len) { addSub(start,pos); return; }
			var c = s.charAt(pos++);
			if (c == "'") { pmin++; min++; }
			if (c != "$" || pos == len) { parse(start,pos); return; }
			var next = s.charAt(pos);
			if (next == "$") {
				addSub(start,pos);
				parse(pos+1,pos+1);
			} else if (next == "{") {
				parseGroup(start,pos,"{","}","brace");
			} else if (identStart(next)) {
				addSub(start,pos-1);
				min++;
				var end = pos+1;
				while (end < len) {
					var c = s.charAt(end);
					if (!identStart(c) && !(c >= "0" && c <= "9")) break;
					end++;
				}
				var length = end-pos;
				add(EConst(Ident(s.substr(pos,length))),length);
				parse(pos+length,pos+length);
			} else parse(start,pos);
		};
		parse(0,0);
		if (result == null) throw "formatString: missing expression";
		return result;
	}
}
