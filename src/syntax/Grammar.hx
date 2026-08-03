package syntax;

import core.Ast;
import core.Ast.*;
import core.Globals.Pos;
import syntax.Lexer.LexedToken;

// Batch-only recursive descent port of the declaration/expression path in
// haxe/src/syntax/grammar.ml.  Display recovery and XML remain parser-entry
// responsibilities and are intentionally not represented here.
class Grammar {
	public static function parse(source:String, ?defines:core.Define.DefineContext, ?file = "?"):Package {
		var tokens = defines == null ? Lexer.lex(source, file) : Preprocessor.process(source, defines, file);
		return new Grammar(tokens).parseFile();
	}

	final tokens:Array<LexedToken>;
	var index = 0;
	public function new(tokens) this.tokens = tokens;

	public function parseFile():Package {
		var pack:Array<String> = [];
		if (acceptKwd(Package) != null) { pack = path(); expect(Semicolon); }
		var declarations:Array<TypeDecl> = [];
		while (!is(Eof)) declarations.push(declaration());
		return {pack: pack, declarations: declarations};
	}

	function declaration():TypeDecl {
		var start = current().pos;
		if (acceptKwd(Import) != null) {
			var names = [placedIdent()]; var mode:ImportMode = INormal;
			while (accept(Dot) != null) {
				if (is(Binop(OpMult))) { next(); mode = IAll; break; }
				names.push(placedIdent());
			}
			if (identText() == "as") { next(); mode = IAsName(placedIdent()); }
			expect(Semicolon); return decl(EImport({path:names, mode:mode}), start);
		}
		if (acceptKwd(Using) != null) { var p = placedPath(); expect(Semicolon); return decl(EUsing(p), start); }
		var accesses = access();
		if (acceptKwd(Class) != null || acceptKwd(Interface) != null) {
			var interfaceValue = previousKwd == Interface;
			var name = placedIdent(); var flags:Array<ClassFlag> = interfaceValue ? [HInterface] : [];
			if (hasAccess(accesses, AExtern)) flags.push(HExtern); if (hasAccess(accesses, APrivate)) flags.push(HPrivate); if (hasAccess(accesses, AFinal)) flags.push(HFinal);
			while (true) { if (acceptKwd(Extends) != null) flags.push(HExtends(typePath())); else if (acceptKwd(Implements) != null) flags.push(HImplements(typePath())); else break; }
			expect(BrOpen); var fields = []; while (!is(BrClose)) fields.push(classField()); var end = expect(BrClose).pos;
			return decl(EClass({name:name, doc:null, params:[], meta:[], flags:flags, data:fields}), union(start,end));
		}
		if (acceptKwd(Function) != null) {
			var name = placedIdent(); var func = functionRest(); var end = func.fExpr == null ? name.pos : func.fExpr.pos;
			return decl(EStatic({name:name, doc:null, params:[], meta:[], flags:accesses, data:FFun(func)}), union(start,end));
		}
		fail("Expected a type declaration"); return null;
	}

	var previousKwd:Null<Keyword>;
	function access():Array<PlacedAccess> { var result=[]; while (true) { var t=current(); var a:Null<Access> = switch t.token { case Kwd(Public): APublic; case Kwd(Private): APrivate; case Kwd(Static): AStatic; case Kwd(Override): AOverride; case Kwd(Dynamic): ADynamic; case Kwd(Inline): AInline; case Kwd(Macro): AMacro; case Kwd(Final): AFinal; case Kwd(Extern): AExtern; case _: null; }; if (a == null) return result; next(); result.push({access:a,pos:t.pos}); } }
	function classField():ClassField {
		var start=current().pos; var accesses=access();
		if (acceptKwd(Var) != null) { var name=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); var end=expect(Semicolon).pos; return {cffName:name,cffDoc:null,cffPos:union(start,end),cffMeta:[],cffAccess:accesses,cffKind:FVar(type,value)}; }
		if (acceptKwd(Function) != null) { var name=placedIdent(); var f=functionRest(); return {cffName:name,cffDoc:null,cffPos:union(start,f.fExpr == null ? name.pos : f.fExpr.pos),cffMeta:[],cffAccess:accesses,cffKind:FFun(f)}; }
		fail("Expected class field"); return null;
	}
	function functionRest():Func { expect(POpen); var args=[]; if (!is(PClose)) do args.push(functionArg()) while (accept(Comma) != null); expect(PClose); var ret=typeHintOpt(); var body:Null<Expr>; if (accept(Semicolon) != null) body=null; else body=block(); return {fParams:[],fArgs:args,fType:ret,fExpr:body}; }
	function functionArg():FuncArg { var optional=accept(Question) != null; var name=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return {name:name,optional:optional,meta:[],type:type,expr:value}; }

	function expression(?min=0):Expr {
		var left=unary();
		while (true) { var op=binop(current().token); if (op == null || precedence(op) < min) break; next(); var right=expression(precedence(op)+1); left=expr(EBinop(op,left,right),union(left.pos,right.pos)); }
		return left;
	}
	function unary():Expr { var t=current(); return switch t.token { case Unop(op): next(); var e=unary(); expr(EUnop(op,Prefix,e),union(t.pos,e.pos)); case Kwd(Return): next(); var e = is(Semicolon)||is(BrClose) ? null : expression(); expr(EReturn(e), e == null ? t.pos : union(t.pos,e.pos)); case Kwd(Throw): next(); var e=expression(); expr(EThrow(e),union(t.pos,e.pos)); case Kwd(Var): next(); var v=variable(); expr(EVars([v]),union(t.pos,v.evExpr == null ? v.evName.pos : v.evExpr.pos)); case _: postfix(primary()); }; }
	function primary():Expr {
		var t=next(); var e:Expr = switch t.token {
			case Const(c): expr(EConst(c),t.pos);
			case Kwd(True): expr(EConst(Ident("true")),t.pos); case Kwd(False): expr(EConst(Ident("false")),t.pos); case Kwd(Null): expr(EConst(Ident("null")),t.pos); case Kwd(This): expr(EConst(Ident("this")),t.pos);
			case POpen: var x=expression(); var end=expect(PClose).pos; expr(EParenthesis(x),union(t.pos,end));
			case BrOpen: index--; block();
			case BkOpen: var values=[]; if (!is(BkClose)) do values.push(expression()) while (accept(Comma)!=null); var end=expect(BkClose).pos; expr(EArrayDecl(values),union(t.pos,end));
			case Kwd(Function): var name:Null<PlacedName> = is(POpen) ? null : placedIdent(); var f=functionRest(); expr(EFunction(name == null ? FKAnonymous : FKNamed(name,false),f), union(t.pos,f.fExpr == null ? t.pos : f.fExpr.pos));
			case _: fail("Expected expression",t.pos); null;
		}; return e;
	}
	function postfix(e:Expr):Expr { while (true) { if (accept(Dot) != null) { var n=placedIdent(); e=expr(EField(e,n.name,EFNormal),union(e.pos,n.pos)); } else if (accept(POpen) != null) { var args=[]; if (!is(PClose)) do args.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; e=expr(ECall(e,args),union(e.pos,end)); } else if (accept(BkOpen) != null) { var key=expression(); var end=expect(BkClose).pos; e=expr(EArray(e,key),union(e.pos,end)); } else return e; } return e; }
	function block():Expr { var begin=expect(BrOpen).pos; var es=[]; while (!is(BrClose)) { es.push(expression()); if (accept(Semicolon)==null && !is(BrClose)) fail("Expected semicolon"); } return expr(EBlock(es),union(begin,expect(BrClose).pos)); }
	function variable():EVar { var n=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return Ast.mkEVar(n,false,false,type,value); }
	function typeHintOpt():Null<TypeHint> return accept(DblDot) == null ? null : {type:CTPath(typePath()),pos:previous().pos};
	function typePath():PlacedTypePath { var names=placedPath(); var last=names.pop(); return Ast.makePtp(Ast.mkTypePath([for(n in names)n.name],last.name), names.length == 0 ? last.pos : union(names[0].pos,last.pos)); }
	function path():Array<String> return [for(n in placedPath())n.name];
	function placedPath():Array<PlacedName> { var result=[placedIdent()]; while(accept(Dot)!=null) result.push(placedIdent()); return result; }
	function placedIdent():PlacedName { var t=next(); return switch t.token { case Const(Ident(v)): {name:v,pos:t.pos}; case Kwd(k): {name:Ast.sKeyword(k),pos:t.pos}; case _: fail("Expected identifier",t.pos); null; }; }
	function identText():Null<String> return switch current().token { case Const(Ident(v)): v; case _: null; }
	function decl(d:TypeDef,p:Pos):TypeDecl return {definition:d,pos:p};
	function expr(d:ExprDef,p:Pos):Expr return {expr:d,pos:p};
	function accept(t:Token):Null<LexedToken> { if(is(t)) return next(); return null; }
	function acceptKwd(k:Keyword):Null<LexedToken> { if (switch current().token {case Kwd(v): v==k; case _:false;}) { previousKwd=k; return next(); } return null; }
	function expect(t:Token):LexedToken { var r=accept(t); if(r==null) fail("Expected token " + Std.string(t)); return r; }
	inline function is(t:Token):Bool return Type.enumEq(current().token,t);
	inline function current():LexedToken return tokens[index]; inline function previous():LexedToken return tokens[index-1]; inline function next():LexedToken return tokens[index++];
	static function binop(t:Token):Null<Binop> return switch t {case Binop(o):o;case _:null;};
	static function precedence(o:Binop):Int return switch o {case OpAssign|OpAssignOp(_):1;case OpBoolOr:2;case OpBoolAnd:3;case OpOr:4;case OpXor:5;case OpAnd:6;case OpEq|OpNotEq:7;case OpGt|OpGte|OpLt|OpLte:8;case OpShl|OpShr|OpUShr:9;case OpAdd|OpSub:10;case OpMult|OpDiv|OpMod:11;case _: -1;};
	static function hasAccess(a:Array<PlacedAccess>, v:Access):Bool { for(x in a) if(x.access==v)return true; return false; }
	static function union(a:Pos,b:Pos):Pos return Ast.punion(a,b);
	function fail(message:String, ?pos:Pos):Void throw new GrammarError(message,pos == null ? current().pos : pos);
}
class GrammarError { public final message:String; public final pos:Pos; public function new(message,pos) {this.message=message;this.pos=pos;} }
