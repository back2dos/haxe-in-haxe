package unit;

import core.Ast;
import syntax.Lexer;

class LexerTest {
	public static function main():Void {
		var tokens = Lexer.lex('class Foo { var x = 0xF_u32; // note\n x += .5f64; }', "Test.hx");
		assert(switch tokens[0].token { case Kwd(Class): true; case _: false; });
		assert(switch tokens[1].token { case Const(Ident("Foo")): true; case _: false; });
		assert(switch tokens[6].token { case Const(Int("0xF", "u32")): true; case _: false; });
		assert(switch tokens[8].token { case CommentLine(" note"): true; case _: false; });
		assert(switch tokens[10].token { case Binop(OpAssignOp(OpAdd)): true; case _: false; });
		assert(switch tokens[11].token { case Const(Float(".5", "f64")): true; case _: false; });
		assert(switch Lexer.lex("12f64 12_f64")[0].token { case Const(Float("12", "f64")): true; case _: false; });
		assert(switch Lexer.lex("12f64 12_f64")[1].token { case Const(Float("12", "f64")): true; case _: false; });
		var numericField = Lexer.lex("5.foo 1.");
		assert(numericField[0].token.match(Const(Int("5", null))) && numericField[1].token.match(Dot) && numericField[3].token.match(Const(Float("1.", null))));
		assert(tokens[0].pos.pfile == "Test.hx" && tokens[0].pos.pmin == 0 && tokens[0].pos.pmax == 5);
		assert(switch Lexer.lex('"a\\n\\\"b" ~/a\\/b/g', "T.hx")[0].token { case Const(String("a\n\"b", SDoubleQuotes)): true; case _: false; });
		assert(switch Lexer.lex('"a\\x21"')[0].token { case Const(String("a!", SDoubleQuotes)): true; case _: false; });
		assert(switch Lexer.lex('"\\u{1F604}"')[0].token { case Const(String("😄", SDoubleQuotes)): true; case _: false; });
		var shifts = Lexer.lex("a >> 1; b >>> 2; a >>= 1; b >>>= 2;");
		assert(shifts[1].token.match(Binop(OpShr)) && shifts[5].token.match(Binop(OpUShr)) && shifts[9].token.match(Binop(OpAssignOp(OpShr))) && shifts[13].token.match(Binop(OpAssignOp(OpUShr))));
		assert(Lexer.lex("\uFEFFclass Main {}")[0].token.match(Kwd(Class)));
		assertThrows(function() Lexer.lex("/*", "T.hx"));
	}

	static function assert(value:Bool):Void if (!value) throw "Lexer assertion failed";
	static function assertThrows(callback:Void->Void):Void { try callback() catch (_:Dynamic) return; throw "Expected lexer error"; }
}
