package unit;

import core.Ast;
import core.Ast.Binop;
import core.Ast.Constant;
import core.Ast.Unop;
import core.Globals;

class AstTest {
	public static function main():Void {
		var path = Ast.mkTypePath(["example"], "Main");
		if (path.tpackage.join(".") != "example" || path.tname != "Main") throw "Type path construction failed";
		if (!Ast.isLowerIdent("_name") || Ast.isLowerIdent("Name")) throw "Identifier classification failed";
		if (Ast.sBinop(OpAssignOp(OpAdd)) != "+=" || Ast.sUnop(Increment) != "++") throw "Operator formatting failed";
		if (Ast.sConstant(String("line\n", SDoubleQuotes)) != '"line\\n"') throw "Constant formatting failed";
		var first:core.Ast.Expr = {expr: EConst(Ident("a")), pos: Globals.fakePos("first")};
		var second:core.Ast.Expr = {expr: EConst(Ident("b")), pos: {pfile: "first", pmin: 3, pmax: 5}};
		if (Ast.punionEl([first, second]).pmax != 5) throw "Position union failed";
	}
}
