package unit;

import core.Ast;
import syntax.Lexer;

class LexerTest {
	public static function main():Void {
		var tokens = lex('class Foo { var x = 0xF_u32; // note\n x += .5f64; }', "Test.hx");
		assert(switch tokens[0].token { case Kwd(Class): true; case _: false; });
		assert(switch tokens[1].token { case Const(Ident("Foo")): true; case _: false; });
		assert(switch tokens[6].token { case Const(Int("0xF", "u32")): true; case _: false; });
		assert(switch tokens[8].token { case CommentLine(" note"): true; case _: false; });
		assert(switch tokens[10].token { case Binop(OpAssignOp(OpAdd)): true; case _: false; });
		assert(switch tokens[11].token { case Const(Float(".5", "f64")): true; case _: false; });
		assert(switch lex("12f64 12_f64")[0].token { case Const(Float("12", "f64")): true; case _: false; });
		assert(switch lex("12f64 12_f64")[1].token { case Const(Float("12", "f64")): true; case _: false; });
		var numericField = lex("5.foo 1.");
		assert(numericField[0].token.match(Const(Int("5", null))) && numericField[1].token.match(Dot) && numericField[3].token.match(Const(Int("1", null))) && numericField[4].token.match(Dot));
		assert(tokens[0].pos.pfile == "Test.hx" && tokens[0].pos.pmin == 0 && tokens[0].pos.pmax == 5);
		assert(switch lex('"a\\n\\\"b" ~/a\\/b/g', "T.hx")[0].token { case Const(String("a\n\"b", SDoubleQuotes)): true; case _: false; });
		assert(switch lex('"a\\x21"')[0].token { case Const(String("a!", SDoubleQuotes)): true; case _: false; });
		assert(switch lex('"\\u{1F604}"')[0].token { case Const(String("😄", SDoubleQuotes)): true; case _: false; });
		assert(switch lex('"\\u00E9\\u3042"')[0].token { case Const(String("éあ", SDoubleQuotes)): true; case _: false; });
		var shifts = lex("a >> 1; b >>> 2; a >>= 1; b >>>= 2;");
		// The lexer emits `>` and `=` separately; the parser joins adjacent ones into shift operators.
		assert(shifts[1].token.match(Binop(OpGt)) && shifts[2].token.match(Binop(OpGt)) && shifts[1].pos.pmax == shifts[2].pos.pmin);
		assert(shifts[13].token.match(Binop(OpGt)) && shifts[14].token.match(Binop(OpAssign)));
		var parsed = GrammarTest.parse("class Main { function run() { a >> 1; b >>> 2; a >>= 1; b >>>= 2; } }");
		var ops = switch parsed.declarations[0].definition {
			case EClass({data: [{cffKind: FFun({fExpr: {expr: EBlock(values)}})}]}): [for (value in values) switch value.expr { case EBinop(op, _, _): op; case _: null; }];
			case _: [];
		}
		assert(ops.length == 4 && ops[0].match(OpShr) && ops[1].match(OpUShr) && ops[2].match(OpAssignOp(OpShr)) && ops[3].match(OpAssignOp(OpUShr)));
		assert(lex("\uFEFFclass Main {}")[0].token.match(Kwd(Class)));
		assertThrows(function() lex("/*", "T.hx"));
	}

	/** Tokenizes `source` with the translated lexer (`lexer.ml`), skipping the header like the parser does. */
	static function lex(source:String, file = "?"):Array<LexedToken> {
		var ctx = Lexer.createTempCtx(file), code = Lexer.lexbufFromUtf8String(source);
		Lexer.skipHeader(code);
		var tokens = [];
		while (true) {
			var token = Lexer.readToken(ctx, code);
			if (token.token == Eof) return tokens;
			tokens.push(token);
		}
	}

	static function assert(value:Bool):Void if (!value) throw "Lexer assertion failed";
	static function assertThrows(callback:Void->Void):Void { try callback() catch (_:Dynamic) return; throw "Expected lexer error"; }
}
