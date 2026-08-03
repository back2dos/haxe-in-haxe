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
		var doc = documentation(); var meta = metadata();
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
			var name = placedIdent(); var params = typeParams(); var flags:Array<ClassFlag> = interfaceValue ? [HInterface] : [];
			if (hasAccess(accesses, AExtern)) flags.push(HExtern); if (hasAccess(accesses, APrivate)) flags.push(HPrivate); if (hasAccess(accesses, AFinal)) flags.push(HFinal);
			while (true) { if (acceptKwd(Extends) != null) flags.push(HExtends(typePath())); else if (acceptKwd(Implements) != null) flags.push(HImplements(typePath())); else break; }
			expect(BrOpen); var fields = []; while (!is(BrClose)) fields.push(classField()); var end = expect(BrClose).pos;
			return decl(EClass({name:name, doc:doc, params:params, meta:meta, flags:flags, data:fields}), union(start,end));
		}
		if (acceptKwd(Enum) != null) {
			var name = placedIdent(), params = typeParams(), flags:Array<EnumFlag> = [];
			if (hasAccess(accesses, AExtern)) flags.push(EExtern); if (hasAccess(accesses, APrivate)) flags.push(EPrivate);
			expect(BrOpen); var data = []; while (!is(BrClose)) data.push(enumConstructor()); var end = expect(BrClose).pos;
			return decl(EEnum({name:name, doc:doc, params:params, meta:meta, flags:flags, data:data}), union(start,end));
		}
		if (acceptKwd(Typedef) != null) {
			var name=placedIdent(), params=typeParams(); expect(Binop(OpAssign)); var data=typeHint(); var end=accept(Semicolon);
			var flags:Array<TypedefFlag>=[]; if(hasAccess(accesses,AExtern)) flags.push(TDExtern); if(hasAccess(accesses,APrivate)) flags.push(TDPrivate);
			return decl(ETypedef({name:name,doc:doc,params:params,meta:meta,flags:flags,data:data}),union(start,end == null ? data.pos : end.pos));
		}
		if (acceptKwd(Abstract) != null) {
			var name=placedIdent(), params=typeParams(); var flags:Array<AbstractFlag>=[];
			if(hasAccess(accesses,AExtern))flags.push(AbExtern); if(hasAccess(accesses,APrivate))flags.push(AbPrivate);
			if(accept(POpen)!=null) { flags.push(AbOver(typeHint())); expect(PClose); }
			while(true) { if(identText()=="from") {next();flags.push(AbFrom(typeHint()));} else if(identText()=="to") {next();flags.push(AbTo(typeHint()));} else break; }
			expect(BrOpen); var fields=[]; while(!is(BrClose)) fields.push(classField()); var end=expect(BrClose).pos;
			return decl(EAbstract({name:name,doc:doc,params:params,meta:meta,flags:flags,data:fields}),union(start,end));
		}
		if (acceptKwd(Function) != null) {
			var name = placedIdent(); var func = functionRest(); var end = func.fExpr == null ? name.pos : func.fExpr.pos;
			return decl(EStatic({name:name, doc:doc, params:func.fParams, meta:meta, flags:accesses, data:FFun(func)}), union(start,end));
		}
		fail("Expected a type declaration"); return null;
	}

	var previousKwd:Null<Keyword>;
	function access():Array<PlacedAccess> { var result=[]; while (true) { var t=current(); var a:Null<Access> = switch t.token { case Kwd(Public): APublic; case Kwd(Private): APrivate; case Kwd(Static): AStatic; case Kwd(Override): AOverride; case Kwd(Dynamic): ADynamic; case Kwd(Inline): AInline; case Kwd(Macro): AMacro; case Kwd(Final): AFinal; case Kwd(Extern): AExtern; case _: null; }; if (a == null) return result; next(); result.push({access:a,pos:t.pos}); } }
	function classField():ClassField {
		var doc=documentation(), meta=metadata(); var start=current().pos; var accesses=access();
		if (acceptKwd(Var) != null) {
			var name = placedIdent();
			if (accept(POpen) != null) {
				var get = placedIdent(); expect(Comma); var set = placedIdent(); expect(PClose);
				var type = typeHintOpt(); var value = accept(Binop(OpAssign)) == null ? null : expression(); var end = expect(Semicolon).pos;
				return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FProp(get,set,type,value)};
			}
			var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); var end=expect(Semicolon).pos; return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FVar(type,value)};
		}
		if (acceptKwd(Function) != null) { var name=placedIdent(); var f=functionRest(); return {cffName:name,cffDoc:doc,cffPos:union(start,f.fExpr == null ? name.pos : f.fExpr.pos),cffMeta:meta,cffAccess:accesses,cffKind:FFun(f)}; }
		fail("Expected class field"); return null;
	}
	function functionRest():Func { var params=typeParams(); expect(POpen); var args=[]; if (!is(PClose)) do args.push(functionArg()) while (accept(Comma) != null); expect(PClose); var ret=typeHintOpt(); var body:Null<Expr>; if (accept(Semicolon) != null) body=null; else body=block(); return {fParams:params,fArgs:args,fType:ret,fExpr:body}; }
	function functionArg():FuncArg { var meta=metadata(); var optional=accept(Question) != null; var name=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return {name:name,optional:optional,meta:meta,type:type,expr:value}; }

	function expression(?min=0):Expr {
		var left=unary();
		while (true) { var op=binop(current().token); if (op == null || precedence(op) < min) break; next(); var right=expression(precedence(op)+1); left=expr(EBinop(op,left,right),union(left.pos,right.pos)); }
		if (min == 0 && accept(Question) != null) { var thenExpr=expression(); expect(DblDot); var elseExpr=expression(); left=expr(ETernary(left,thenExpr,elseExpr),union(left.pos,elseExpr.pos)); }
		return left;
	}
	function unary():Expr { var t=current(); return switch t.token {
		case Unop(op): next(); var e=unary(); expr(EUnop(op,Prefix,e),union(t.pos,e.pos));
		case Kwd(Return): next(); var e = is(Semicolon)||is(BrClose) ? null : expression(); expr(EReturn(e), e == null ? t.pos : union(t.pos,e.pos));
		case Kwd(Throw): next(); var e=expression(); expr(EThrow(e),union(t.pos,e.pos));
		case Kwd(Var) | Kwd(Final): var finalValue=acceptKwd(Final)!=null; if(!finalValue)next(); var vars=[variable(finalValue)]; while(accept(Comma)!=null) vars.push(variable(finalValue)); expr(EVars(vars),union(t.pos,vars[vars.length-1].evExpr == null ? vars[vars.length-1].evName.pos : vars[vars.length-1].evExpr.pos));
		case Kwd(If): next(); expect(POpen); var c=expression(); expect(PClose); var th=expression(); var el=acceptKwd(Else)==null ? null : expression(); expr(EIf(c,th,el),union(t.pos,el == null ? th.pos : el.pos));
		case Kwd(While): next(); expect(POpen); var c=expression(); expect(PClose); var b=expression(); expr(EWhile(c,b,NormalWhile),union(t.pos,b.pos));
		case Kwd(For): next(); expect(POpen); var it=expression(); if(acceptKwd(In)!=null) { var right=expression(); it=expr(EBinop(OpIn,it,right),union(it.pos,right.pos)); } expect(PClose); var b=expression(); expr(EFor(it,b),union(t.pos,b.pos));
		case Kwd(Do): next(); var b=expression(); expectKwd(While); expect(POpen); var c=expression(); var end=expect(PClose).pos; expr(EWhile(c,b,DoWhile),union(t.pos,end));
		case Kwd(Try): next(); var body=expression(); var catches=[]; while(acceptKwd(Catch)!=null) { var cp=previous().pos; expect(POpen); var n=placedIdent(); var ty=typeHintOpt(); expect(PClose); var cb=expression(); catches.push({name:n,type:ty,expr:cb,pos:union(cp,cb.pos)}); } if(catches.length==0) fail("Expected catch"); expr(ETry(body,catches),union(t.pos,catches[catches.length-1].pos));
		case Kwd(Break): next(); expr(EBreak,t.pos); case Kwd(Continue): next(); expr(EContinue,t.pos);
		case Kwd(Untyped): next(); var e=expression(); expr(EUntyped(e),union(t.pos,e.pos));
		case Kwd(Cast): next(); expect(POpen); var e=expression(); var type=accept(Comma)==null ? null : typeHint(); var end=expect(PClose).pos; expr(ECast(e,type),union(t.pos,end));
		case _: postfix(primary()); }; }
	function primary():Expr {
		var t=next(); var e:Expr = switch t.token {
			case Const(c): expr(EConst(c),t.pos);
			case Kwd(True): expr(EConst(Ident("true")),t.pos); case Kwd(False): expr(EConst(Ident("false")),t.pos); case Kwd(Null): expr(EConst(Ident("null")),t.pos); case Kwd(This): expr(EConst(Ident("this")),t.pos);
			case POpen: var x=expression(); var end=expect(PClose).pos; expr(EParenthesis(x),union(t.pos,end));
			case BrOpen: index--; objectOrIdentifier();
			case Kwd(New): var p=typePath(); expect(POpen); var args=[]; if(!is(PClose)) do args.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; expr(ENew(p,args),union(t.pos,end));
			case BkOpen: var values=[]; if (!is(BkClose)) do values.push(expression()) while (accept(Comma)!=null); var end=expect(BkClose).pos; expr(EArrayDecl(values),union(t.pos,end));
			case Kwd(Function): var name:Null<PlacedName> = is(POpen) ? null : placedIdent(); var f=functionRest(); expr(EFunction(name == null ? FKAnonymous : FKNamed(name,false),f), union(t.pos,f.fExpr == null ? t.pos : f.fExpr.pos));
			case _: index--; objectOrIdentifier();
		}; return e;
	}
	function objectOrIdentifier():Expr { var t=current(); if(accept(BrOpen)!=null) { var fields=[]; if(!is(BrClose)) do { var n=placedIdent(); expect(DblDot); var value=expression(); fields.push({key:{name:n.name,pos:n.pos,quote:NoQuotes},expr:value}); } while(accept(Comma)!=null); var end=expect(BrClose).pos; return expr(EObjectDecl(fields),union(t.pos,end)); } var n=placedIdent(); return expr(EConst(Ident(n.name)),n.pos); }
	function postfix(e:Expr):Expr { while (true) { if (accept(Dot) != null || accept(QuestionDot) != null) { var safe=previous().token.match(QuestionDot); var n=placedIdent(); e=expr(EField(e,n.name,safe ? EFSafe : EFNormal),union(e.pos,n.pos)); } else if (accept(POpen) != null) { var args=[]; if (!is(PClose)) do args.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; e=expr(ECall(e,args),union(e.pos,end)); } else if (accept(BkOpen) != null) { var key=expression(); var end=expect(BkClose).pos; e=expr(EArray(e,key),union(e.pos,end)); } else if (switch current().token {case Unop(Increment)|Unop(Decrement):true;case _:false;}) { var op=switch next().token {case Unop(v):v;case _:null;}; e=expr(EUnop(op,Postfix,e),union(e.pos,previous().pos)); } else return e; } return e; }
	function block():Expr { var begin=expect(BrOpen).pos; var es=[]; while (!is(BrClose)) { es.push(expression()); if (accept(Semicolon)==null && !is(BrClose)) fail("Expected semicolon"); } return expr(EBlock(es),union(begin,expect(BrClose).pos)); }
	function variable(finalValue=false):EVar { var n=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return Ast.mkEVar(n,finalValue,false,type,value); }
	function typeHintOpt():Null<TypeHint> return accept(DblDot) == null ? null : typeHint();
	function typeHint():TypeHint {
		var start = current().pos;
		var optional = accept(Question) != null;
		var complex:ComplexType;
		if (accept(BrOpen) != null) {
			// parse_type_anonymous in grammar.ml uses the ordinary class-field
			// grammar. This is needed by StdTypes' Iterator/Iterable typedefs.
			var fields = [];
			while (!is(BrClose)) {
				fields.push(anonymousField());
				accept(Comma);
			}
			var end = expect(BrClose).pos;
			complex = CTAnonymous(fields);
			return {type: optional ? CTOptional({type:complex, pos:union(start, end)}) : complex, pos:union(start, end)};
		}
		complex = CTPath(typePath());
		if (accept(Arrow) != null) {
			var result = typeHint();
			complex = CTFunction([ {type:complex, pos:start} ], result);
			return {type: optional ? CTOptional({type:complex,pos:union(start,result.pos)}) : complex,pos:union(start,result.pos)};
		}
		return {type: optional ? CTOptional({type:complex,pos:start}) : complex,pos:start};
	}
	function anonymousField():ClassField {
		var doc = documentation(), meta = metadata(), start = current().pos, accesses = access();
		if (acceptKwd(Function) != null) {
			var name = placedIdent(), func = functionRest();
			return {cffName:name, cffDoc:doc, cffPos:union(start, func.fExpr == null ? name.pos : func.fExpr.pos), cffMeta:meta, cffAccess:accesses, cffKind:FFun(func)};
		}
		var name = placedIdent();
		expect(DblDot);
		var type = typeHint();
		return {cffName:name, cffDoc:doc, cffPos:union(start, type.pos), cffMeta:meta, cffAccess:accesses, cffKind:FVar(type, null)};
	}
	function typePath():PlacedTypePath { var names=placedPath(); var last=names.pop(); var params=[]; if(accept(Binop(OpLt))!=null) { if(!is(Binop(OpGt))) do params.push(TPType(typeHint())) while(accept(Comma)!=null); expect(Binop(OpGt)); } return Ast.makePtp(Ast.mkTypePath([for(n in names)n.name],last.name,params), names.length == 0 ? last.pos : union(names[0].pos,previous().pos)); }
	function path():Array<String> return [for(n in placedPath())n.name];
	function placedPath():Array<PlacedName> { var result=[placedIdent()]; while(accept(Dot)!=null) result.push(placedIdent()); return result; }
	function typeParams():Array<TypeParam> {
		if (accept(Binop(OpLt)) == null) return [];
		var result=[]; if(!is(Binop(OpGt))) do { var meta=metadata(); var name=placedIdent(); var constraints=typeHintOpt(); var defaultValue=accept(Binop(OpAssign)) == null ? null : typeHint(); result.push({tpName:name,tpParams:[],tpConstraints:constraints,tpDefault:defaultValue,tpMeta:meta}); } while(accept(Comma)!=null);
		expect(Binop(OpGt)); return result;
	}
	function enumConstructor():EnumConstructor {
		var doc=documentation(), meta=metadata(), name=placedIdent(), params=typeParams(), args=[];
		if(accept(POpen)!=null) { if(!is(PClose)) do { var optional=accept(Question)!=null; var n=placedIdent(); var t=typeHintOpt(); if(t==null) fail("Expected enum parameter type",n.pos); args.push({name:n.name,optional:optional,type:t}); } while(accept(Comma)!=null); expect(PClose); }
		var type=typeHintOpt(); var end=expect(Semicolon).pos;
		return {ecName:name,ecDoc:doc,ecMeta:meta,ecArgs:args,ecPos:union(name.pos,end),ecParams:params,ecType:type};
	}
	function documentation():Documentation {
		var value:Null<String>=null;
		while(true) switch(current().token) { case Comment(v): next(); if(StringTools.startsWith(v,"*")) value=v.substr(1); case CommentLine(_): next(); case _: return Ast.docFromStringOpt(value); }
	}
	function metadata():Metadata {
		var result=[];
		while(accept(At)!=null) { var start=previous().pos; expect(DblDot); var name=placedPath(); var values=[]; if(accept(POpen)!=null) { if(!is(PClose)) do values.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; result.push({meta:[for(n in name)n.name].join("."),exprs:values,pos:union(start,end)}); } else result.push({meta:[for(n in name)n.name].join("."),exprs:values,pos:union(start,name[name.length-1].pos)}); }
		return result;
	}
	function placedIdent():PlacedName { var t=next(); return switch t.token { case Const(Ident(v)): {name:v,pos:t.pos}; case Kwd(k): {name:Ast.sKeyword(k),pos:t.pos}; case _: fail("Expected identifier",t.pos); null; }; }
	function identText():Null<String> return switch current().token { case Const(Ident(v)): v; case _: null; }
	function decl(d:TypeDef,p:Pos):TypeDecl return {definition:d,pos:p};
	function expr(d:ExprDef,p:Pos):Expr return {expr:d,pos:p};
	function accept(t:Token):Null<LexedToken> { if(is(t)) return next(); return null; }
	function acceptKwd(k:Keyword):Null<LexedToken> { if (switch current().token {case Kwd(v): v==k; case _:false;}) { previousKwd=k; return next(); } return null; }
	function expect(t:Token):LexedToken { var r=accept(t); if(r==null) fail("Expected token " + Std.string(t)); return r; }
	function expectKwd(k:Keyword):LexedToken { var r=acceptKwd(k); if(r==null) fail("Expected keyword " + Ast.sKeyword(k)); return r; }
	inline function is(t:Token):Bool return Type.enumEq(current().token,t);
	inline function current():LexedToken return tokens[index]; inline function previous():LexedToken return tokens[index-1]; inline function next():LexedToken return tokens[index++];
	static function binop(t:Token):Null<Binop> return switch t {case Binop(o):o;case _:null;};
	static function precedence(o:Binop):Int return switch o {case OpAssign|OpAssignOp(_):1;case OpBoolOr:2;case OpBoolAnd:3;case OpOr:4;case OpXor:5;case OpAnd:6;case OpEq|OpNotEq:7;case OpGt|OpGte|OpLt|OpLte:8;case OpShl|OpShr|OpUShr:9;case OpAdd|OpSub:10;case OpMult|OpDiv|OpMod:11;case _: -1;};
	static function hasAccess(a:Array<PlacedAccess>, v:Access):Bool { for(x in a) if(x.access==v)return true; return false; }
	static function union(a:Pos,b:Pos):Pos return Ast.punion(a,b);
	function fail(message:String, ?pos:Pos):Void throw new GrammarError(message,pos == null ? current().pos : pos);
}
class GrammarError { public final message:String; public final pos:Pos; public function new(message,pos) {this.message=message;this.pos=pos;} }
