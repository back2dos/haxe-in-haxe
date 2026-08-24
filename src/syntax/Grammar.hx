package syntax;

import core.Ast;
import core.Ast.*;
import core.Globals.Pos;
import syntax.Lexer.LexedToken;

// Batch-only recursive descent port of the declaration/expression path in
// haxe/src/syntax/grammar.ml.  Display recovery and XML remain parser-entry
// responsibilities and are intentionally not represented here.
class Grammar {
	var pendingDeclarationDoc:Documentation = null;
	public static function parse(source:String, ?defines:core.Define.DefineContext, ?file = "?"):Package {
		var tokens = defines == null ? Lexer.lex(source, file) : Preprocessor.process(source, defines, file);
		return new Grammar(tokens).parseFile();
	}
	static function parseEmbeddedExpression(source:String, file:String, offset:Int):Expr {
		var tokens = Lexer.lex(source, file);
		for (token in tokens) { token.pos.pmin += offset; token.pos.pmax += offset; }
		return new Grammar(tokens).expression();
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
		if (doc == null && pendingDeclarationDoc != null) doc = pendingDeclarationDoc;
		var start = current().pos;
		if (acceptKwd(Import) != null) {
			if (doc != null) pendingDeclarationDoc = doc;
			var names = [placedIdent()]; var mode:ImportMode = INormal;
			while (accept(Dot) != null) {
				if (is(Binop(OpMult))) { next(); mode = IAll; break; }
				names.push(placedIdent());
			}
			if (identText() == "as") { next(); mode = IAsName(placedIdent()); }
			expect(Semicolon); return decl(EImport({path:names, mode:mode}), start);
		}
		if (acceptKwd(Using) != null) { if (doc != null) pendingDeclarationDoc = doc; var p = placedPath(); expect(Semicolon); return decl(EUsing(p), start); }
		var accesses = access();
		if (acceptKwd(Class) != null || acceptKwd(Interface) != null) {
			start = previous().pos; pendingDeclarationDoc = null;
			var interfaceValue = previousKwd == Interface;
			var name = placedIdent(); var params = typeParams(); var flags:Array<ClassFlag> = interfaceValue ? [HInterface] : [];
			if (hasAccess(accesses, AExtern)) flags.push(HExtern); if (hasAccess(accesses, APrivate)) flags.push(HPrivate); if (hasAccess(accesses, AFinal)) flags.push(HFinal);
			while (true) { if (acceptKwd(Extends) != null) flags.push(HExtends(typePath())); else if (acceptKwd(Implements) != null) flags.push(HImplements(typePath())); else break; }
			expect(BrOpen); var fields = classFields(); var end = expect(BrClose).pos;
			return decl(EClass({name:name, doc:doc, params:params, meta:meta, flags:flags, data:fields}), union(start,end));
		}
		if (acceptKwd(Enum) != null) {
			start = previous().pos; pendingDeclarationDoc = null;
			var name = placedIdent(), params = typeParams(), flags:Array<EnumFlag> = [];
			if (hasAccess(accesses, AExtern)) flags.push(EExtern); if (hasAccess(accesses, APrivate)) flags.push(EPrivate);
			expect(BrOpen); var data = []; while (!is(BrClose)) data.push(enumConstructor()); var end = expect(BrClose).pos;
			return decl(EEnum({name:name, doc:doc, params:params, meta:meta, flags:flags, data:data}), union(start,end));
		}
		if (acceptKwd(Typedef) != null) {
			start = previous().pos; pendingDeclarationDoc = null;
			var name=placedIdent(), params=typeParams(); expect(Binop(OpAssign)); var data=typeHint(); var end=accept(Semicolon);
			var flags:Array<TypedefFlag>=[]; if(hasAccess(accesses,AExtern)) flags.push(TDExtern); if(hasAccess(accesses,APrivate)) flags.push(TDPrivate);
			// grammar.ml consumes an optional semicolon but excludes it from the
			// declaration range.
			var declarationEnd = end == null ? data.pos : {pfile:end.pos.pfile, pmin:end.pos.pmin, pmax:end.pos.pmin};
			return decl(ETypedef({name:name,doc:doc,params:params,meta:meta,flags:flags,data:data}),union(start,declarationEnd));
		}
		if (acceptKwd(Abstract) != null) {
			start = previous().pos; pendingDeclarationDoc = null;
			var name=placedIdent(), params=typeParams(); var flags:Array<AbstractFlag>=[];
			if(hasAccess(accesses,AExtern))flags.push(AbExtern); if(hasAccess(accesses,APrivate))flags.push(AbPrivate);
			if(accept(POpen)!=null) { flags.push(AbOver(typeHint())); expect(PClose); }
			while(true) { if(identText()=="from") {next();flags.push(AbFrom(typeHint()));} else if(identText()=="to") {next();flags.push(AbTo(typeHint()));} else break; }
			expect(BrOpen); var fields=classFields(); var end=expect(BrClose).pos;
			return decl(EAbstract({name:name,doc:doc,params:params,meta:meta,flags:flags,data:fields}),union(start,end));
		}
		if (acceptKwd(Var) != null || hasAccess(accesses, AFinal)) {
			pendingDeclarationDoc = null;
			var name = placedIdent(), type = typeHintOpt();
			var value = accept(Binop(OpAssign)) == null ? null : expression();
			var end = expect(Semicolon).pos;
			return decl(EStatic({name:name, doc:doc, params:[], meta:meta, flags:accesses, data:FVar(type, value)}), union(start, end));
		}
		if (acceptKwd(Function) != null) {
			start = previous().pos; pendingDeclarationDoc = null;
			var name = placedIdent(); var func = functionRest(); var end = func.fExpr == null ? name.pos : func.fExpr.pos;
			return decl(EStatic({name:name, doc:doc, params:func.fParams, meta:meta, flags:accesses, data:FFun(func)}), union(start,end));
		}
		fail("Expected a type declaration"); return null;
	}

	var previousKwd:Null<Keyword>;
	function access():Array<PlacedAccess> { var result=[]; while (true) { var t=current(); var a:Null<Access> = switch t.token { case Kwd(Public): APublic; case Kwd(Private): APrivate; case Kwd(Static): AStatic; case Kwd(Override): AOverride; case Kwd(Dynamic): ADynamic; case Kwd(Inline): AInline; case Kwd(Macro): AMacro; case Kwd(Final): AFinal; case Kwd(Extern): AExtern; case _: null; }; if (a == null) return result; next(); result.push({access:a,pos:t.pos}); } }
	function classFields():Array<ClassField> {
		var fields:Array<ClassField> = [];
		while (!is(BrClose)) {
			var field = classField();
			if (field != null) fields.push(field);
		}
		return fields;
	}
	function classField():Null<ClassField> {
		var doc=documentation(), meta=metadata(); var start=current().pos; var accesses=access();
		// Conditional compilation can leave a documentation comment immediately
		// before the closing brace after its documented field is removed.
		if (is(BrClose)) return null;
		if (hasAccess(accesses, AFinal) && !is(Kwd(Var)) && !is(Kwd(Function))) {
			var name = placedIdent(); var type = typeHintOpt(); var value = accept(Binop(OpAssign)) == null ? null : expression(); var end = expect(Semicolon).pos;
			return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FVar(type,value)};
		}
		if (acceptKwd(Var) != null) {
			var name = placedIdent();
			if (accept(POpen) != null) {
				var get = placedIdent(); expect(Comma); var set = placedIdent(); expect(PClose);
				var type = typeHintOpt(); var value = accept(Binop(OpAssign)) == null ? null : expression(); var end = expect(Semicolon).pos;
				return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FProp(get,set,type,value)};
			}
			var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); var end=expect(Semicolon).pos; return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FVar(type,value)};
		}
		if (acceptKwd(Function) != null) { var name=placedIdent(); var f=functionRest(); var end = f.fExpr == null ? previous().pos : f.fExpr.pos; accept(Semicolon); return {cffName:name,cffDoc:doc,cffPos:union(start,end),cffMeta:meta,cffAccess:accesses,cffKind:FFun(f)}; }
		fail("Expected class field"); return null;
	}
	function functionRest():Func {
		var params=typeParams(); expect(POpen); var args=[]; if (!is(PClose)) do args.push(functionArg()) while (accept(Comma) != null); expect(PClose); var ret=typeHintOpt();
		var body:Null<Expr>;
		if (accept(Semicolon) != null) body = null;
		else if (is(BrOpen)) body = block();
		else { body = expression(); accept(Semicolon); }
		return {fParams:params,fArgs:args,fType:ret,fExpr:body};
	}
	function functionArg():FuncArg { var meta=metadata(); var optional=accept(Question) != null; var name=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return {name:name,optional:optional,meta:meta,type:type,expr:value}; }

	function expression(?min=0):Expr {
		var left=unary();
		while (true) { var op=binop(current().token); if (op == null || precedence(op) < min) break; next(); var right=expression(precedence(op)+1); left=expr(EBinop(op,left,right),union(left.pos,right.pos)); }
		if (min == 0 && accept(Question) != null) { var thenExpr=expression(); expect(DblDot); var elseExpr=expression(); left=expr(ETernary(left,thenExpr,elseExpr),union(left.pos,elseExpr.pos)); }
		if (min == 0 && is(Arrow)) {
			var argument = switch left.expr {
				case EConst(Ident(name)): {name:{name:name, pos:left.pos}, optional:false, meta:[], type:null, expr:null};
				case EParenthesis({expr:EConst(Ident(name)), pos:argumentPos}): {name:{name:name, pos:argumentPos}, optional:false, meta:[], type:null, expr:null};
				case _: fail("Invalid arrow function argument", left.pos); null;
			};
			left = arrowFunction(left.pos, [argument]);
		}
		return left;
	}
	function unary():Expr { var t=current(); return switch t.token {
		case At:
			// Expression metadata (for example @:privateAccess value) is parsed
			// in grammar.ml's unary-expression path, rather than only before
			// declarations and fields.
			var metas = metadata();
			var value = unary();
			for (i in 0...metas.length) {
				var meta = metas[metas.length - 1 - i];
				value = expr(EMeta(meta, value), union(meta.pos, value.pos));
			}
			value;
		case Unop(op): next(); var e=unary(); expr(EUnop(op,Prefix,e),union(t.pos,e.pos));
		case Binop(OpSub): next(); var e=unary(); expr(EUnop(Neg,Prefix,e),union(t.pos,e.pos));
		case Kwd(Return): next(); var e = is(Semicolon)||is(BrClose) ? null : expression(); expr(EReturn(e), e == null ? t.pos : union(t.pos,e.pos));
		case Kwd(Throw): next(); var e=expression(); expr(EThrow(e),union(t.pos,e.pos));
		case Kwd(Var) | Kwd(Final): var finalValue=acceptKwd(Final)!=null; if(!finalValue)next(); var vars=[variable(finalValue)]; while(accept(Comma)!=null) vars.push(variable(finalValue)); expr(EVars(vars),union(t.pos,vars[vars.length-1].evExpr == null ? vars[vars.length-1].evName.pos : vars[vars.length-1].evExpr.pos));
		case Kwd(If): next(); expect(POpen); var c=expression(); expect(PClose); var th=statementBody(); var el=acceptKwd(Else)==null ? null : statementBody(); expr(EIf(c,th,el),union(t.pos,el == null ? th.pos : el.pos));
		case Kwd(While): next(); expect(POpen); var c=expression(); expect(PClose); var b=statementBody(); expr(EWhile(c,b,NormalWhile),union(t.pos,b.pos));
		case Kwd(For): next(); expect(POpen); var it=expression(); if(acceptKwd(In)!=null) { var right=expression(); it=expr(EBinop(OpIn,it,right),union(it.pos,right.pos)); } expect(PClose); var b=statementBody(); expr(EFor(it,b),union(t.pos,b.pos));
		case Kwd(Do): next(); var b=statementBody(); expectKwd(While); expect(POpen); var c=expression(); var end=expect(PClose).pos; expr(EWhile(c,b,DoWhile),union(t.pos,end));
		case Kwd(Try): next(); var body=statementBody(); var catches=[]; while(acceptKwd(Catch)!=null) { var cp=previous().pos; expect(POpen); var n=placedIdent(); var ty=typeHintOpt(); expect(PClose); var cb=statementBody(); catches.push({name:n,type:ty,expr:cb,pos:union(cp,cb.pos)}); } if(catches.length==0) fail("Expected catch"); expr(ETry(body,catches),union(t.pos,catches[catches.length-1].pos));
		case Kwd(Switch): next(); parseSwitch(t.pos);
		case Kwd(Break): next(); expr(EBreak,t.pos); case Kwd(Continue): next(); expr(EContinue,t.pos);
		case Kwd(Untyped): next(); var e=expression(); expr(EUntyped(e),union(t.pos,e.pos));
		case Kwd(Cast): next(); expect(POpen); var e=expression(); var type=accept(Comma)==null ? null : typeHint(); var end=expect(PClose).pos; expr(ECast(e,type),union(t.pos,end));
		case _: postfix(primary()); }; }
	function primary():Expr {
		var t=next(); var e:Expr = switch t.token {
			case Const(String(value, SSingleQuotes)) if (value.indexOf("$") != -1): interpolatedString(value, t.pos);
			case Const(c): expr(EConst(c),t.pos);
			case IntInterval(value):
				var left = expr(EConst(Int(value, null)), t.pos);
				var right = expression(precedence(OpInterval) + 1);
				expr(EBinop(OpInterval, left, right), union(left.pos, right.pos));
			case Kwd(True): expr(EConst(Ident("true")),t.pos); case Kwd(False): expr(EConst(Ident("false")),t.pos); case Kwd(Null): expr(EConst(Ident("null")),t.pos); case Kwd(This): expr(EConst(Ident("this")),t.pos);
			case POpen:
				if (parenthesizedArrowAhead()) {
					var args:Array<FuncArg> = [];
					if (!is(PClose)) do args.push(functionArg()) while (accept(Comma) != null);
					expect(PClose);
					arrowFunction(t.pos, args);
				} else {
					var x=expression(); var end=expect(PClose).pos; expr(EParenthesis(x),union(t.pos,end));
				}
			case BrOpen: index--; objectOrIdentifier();
			case Kwd(New): var p=typePath(); expect(POpen); var args=[]; if(!is(PClose)) do args.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; expr(ENew(p,args),union(t.pos,end));
			case BkOpen:
				var values=[];
				while (!is(BkClose)) { values.push(expression()); if (accept(Comma) == null) break; }
				var end=expect(BkClose).pos; expr(EArrayDecl(values),union(t.pos,end));
			case Kwd(Function): var name:Null<PlacedName> = is(POpen) ? null : placedIdent(); var f=functionRest(); expr(EFunction(name == null ? FKAnonymous : FKNamed(name,false),f), union(t.pos,f.fExpr == null ? t.pos : f.fExpr.pos));
			case _: index--; objectOrIdentifier();
		}; return e;
	}
	function parenthesizedArrowAhead():Bool {
		var depth = 0;
		var cursor = index;
		while (cursor < tokens.length) switch tokens[cursor++].token {
			case POpen: depth++;
			case PClose if (depth == 0): return cursor < tokens.length && tokens[cursor].token.match(Arrow);
			case PClose: depth--;
			case Eof: return false;
			case _:
		}
		return false;
	}
	function arrowFunction(start:Pos, args:Array<FuncArg>):Expr {
		expect(Arrow);
		var body = expression();
		var returned = expr(EReturn(body), body.pos);
		var implicit = expr(EMeta({meta:"implicitReturn", exprs:[], pos:body.pos}, returned), body.pos);
		return expr(EFunction(FKArrow, {fParams:[], fArgs:args, fType:null, fExpr:implicit}), union(start, body.pos));
	}
	function interpolatedString(value:String, pos:Pos):Expr {
		var parts:Array<Expr> = [];
		var literalStart = 0;
		var index = 0;
		function addLiteral(end:Int):Void if (end > literalStart) parts.push(expr(EConst(String(value.substring(literalStart, end), SDoubleQuotes)), {pfile:pos.pfile, pmin:pos.pmin + 1 + literalStart, pmax:pos.pmin + 1 + end}));
		while (index < value.length) {
			if (value.charAt(index) != "$") { index++; continue; }
			var next = index + 1 < value.length ? value.charAt(index + 1) : "";
			var interpolationStart = next == "{" || (next >= "a" && next <= "z") || (next >= "A" && next <= "Z") || next == "_";
			if (!interpolationStart) { index++; continue; }
			addLiteral(index);
			if (index + 1 < value.length && value.charAt(index + 1) == "{") {
				var depth = 1;
				var end = index + 2;
				while (end < value.length && depth > 0) { if (value.charAt(end) == "{") depth++; else if (value.charAt(end) == "}") depth--; end++; }
				if (depth != 0) fail("Unclosed string interpolation", pos);
				var contentStart = index + 2;
				parts.push(parseEmbeddedExpression(value.substring(contentStart, end - 1), pos.pfile, pos.pmin + 1 + contentStart));
				index = end;
			} else {
				var end = index + 1;
				while (end < value.length) { var c = value.charAt(end); if (!((c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_")) break; end++; }
				parts.push(parseEmbeddedExpression(value.substring(index + 1, end), pos.pfile, pos.pmin + 2 + index));
				index = end;
			}
			literalStart = index;
		}
		addLiteral(value.length);
		if (parts.length == 0) return expr(EConst(String("", SDoubleQuotes)), pos);
		var result = parts[0];
		for (partIndex in 1...parts.length) result = expr(EBinop(OpAdd, result, parts[partIndex]), union(result.pos, parts[partIndex].pos));
		result.pos = pos;
		return result;
	}
	function parseSwitch(start:Pos):Expr {
		expect(POpen); var subject = expression(); expect(PClose); expect(BrOpen);
		var cases:Array<SwitchCase> = [];
		var defaultCase:Null<SwitchDefault> = null;
		while (!is(BrClose)) {
			if (acceptKwd(Case) != null) {
				var caseStart = previous().pos, values = [expression()];
				while (accept(Comma) != null) values.push(expression());
				var guard = acceptKwd(If) == null ? null : expression();
				expect(DblDot);
				var value = switchBody();
				cases.push({values:values, guard:guard, expr:value, pos:union(caseStart, value == null ? values[values.length - 1].pos : value.pos)});
			} else if (acceptKwd(Default) != null) {
				var defaultStart = previous().pos; expect(DblDot);
				var value = switchBody();
				defaultCase = {expr:value, pos:value == null ? defaultStart : union(defaultStart, value.pos)};
			} else fail("Expected switch case");
		}
		var end = expect(BrClose).pos;
		return expr(ESwitch(subject, cases, defaultCase), union(start, end));
	}
	function switchBody():Null<Expr> {
		var values:Array<Expr> = [];
		while (!is(Kwd(Case)) && !is(Kwd(Default)) && !is(BrClose)) {
			var value = expression();
			values.push(value);
			if (accept(Semicolon) == null && !is(Kwd(Case)) && !is(Kwd(Default)) && !is(BrClose) && requiresSemicolon(value)) fail("Expected semicolon");
		}
		if (values.length == 0) return null;
		if (values.length == 1) return values[0];
		return expr(EBlock(values), union(values[0].pos, values[values.length - 1].pos));
	}
	function objectOrIdentifier():Expr { var t=current(); if(accept(BrOpen)!=null) { var fields=[]; if(!is(BrClose)) do { var n=placedIdent(); expect(DblDot); var value=expression(); fields.push({key:{name:n.name,pos:n.pos,quote:NoQuotes},expr:value}); } while(accept(Comma)!=null); var end=expect(BrClose).pos; return expr(EObjectDecl(fields),union(t.pos,end)); } var n=placedIdent(); return expr(EConst(Ident(n.name)),n.pos); }
	function postfix(e:Expr):Expr { while (true) { if (accept(Dot) != null || accept(QuestionDot) != null) { var safe=previous().token.match(QuestionDot); var n=placedIdent(); e=expr(EField(e,n.name,safe ? EFSafe : EFNormal),union(e.pos,n.pos)); } else if (accept(POpen) != null) { var args=[]; if (!is(PClose)) do args.push(expression()) while(accept(Comma)!=null); var end=expect(PClose).pos; e=expr(ECall(e,args),union(e.pos,end)); } else if (accept(BkOpen) != null) { var key=expression(); var end=expect(BkClose).pos; e=expr(EArray(e,key),union(e.pos,end)); } else if (switch current().token {case Unop(Increment)|Unop(Decrement):true;case _:false;}) { var op=switch next().token {case Unop(v):v;case _:null;}; e=expr(EUnop(op,Postfix,e),union(e.pos,previous().pos)); } else return e; } return e; }
	function block():Expr { var begin=expect(BrOpen).pos; var es=[]; while (!is(BrClose)) { var value = expression(); es.push(value); if (accept(Semicolon)==null && !is(BrClose) && requiresSemicolon(value)) fail("Expected semicolon"); } return expr(EBlock(es),union(begin,expect(BrClose).pos)); }
	function statementBody():Expr return is(BrOpen) ? block() : expression();
	static function requiresSemicolon(value:Expr):Bool return switch value.expr {
		case EIf(_, _, _) | EWhile(_, _, _) | EFor(_, _) | ETry(_, _): false;
		case EVars(vars) if (vars.length > 0 && switch vars[vars.length - 1].evExpr { case {expr:EFunction(_, _)}: true; case _: false; }): false;
		case _: true;
	}
	function variable(finalValue=false):EVar { var n=placedIdent(); var type=typeHintOpt(); var value=accept(Binop(OpAssign)) == null ? null : expression(); return Ast.mkEVar(n,finalValue,false,type,value); }
	function typeHintOpt():Null<TypeHint> return accept(DblDot) == null ? null : typeHint();
	function typeHint():TypeHint {
		var start = current().pos;
		var optional = accept(Question) != null;
		var complex:ComplexType;
		if (accept(POpen) != null) {
			var args:Array<TypeHint> = [];
			if (!is(PClose)) do args.push(typeHint()) while (accept(Comma) != null);
			var close = expect(PClose).pos;
			if (accept(Arrow) != null) {
				var result = typeHint();
				complex = CTFunction(args, result);
				return {type:optional ? CTOptional({type:complex, pos:union(start, result.pos)}) : complex, pos:union(start, result.pos)};
			}
			if (args.length != 1) fail("Expected function type arrow", close);
			complex = CTParent(args[0]);
			return {type:optional ? CTOptional({type:complex, pos:union(start, close)}) : complex, pos:union(start, close)};
		}
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
			complex = switch result.type {
				case CTFunction(args, ret): CTFunction([{type:complex, pos:start}].concat(args), ret);
				case _: CTFunction([{type:complex, pos:start}], result);
			};
			return {type: optional ? CTOptional({type:complex,pos:union(start,result.pos)}) : complex,pos:union(start,result.pos)};
		}
		return {type: optional ? CTOptional({type:complex,pos:start}) : complex,pos:start};
	}
	function anonymousField():ClassField {
		var doc = documentation(), meta = metadata(), start = current().pos, accesses = access();
		if (is(Kwd(Var))) next();
		if (acceptKwd(Function) != null) {
			var name = placedIdent(), func = functionRest();
			var end = func.fExpr == null ? previous().pos : func.fExpr.pos;
			return {cffName:name, cffDoc:doc, cffPos:union(start, end), cffMeta:meta, cffAccess:accesses, cffKind:FFun(func)};
		}
		var optional = accept(Question) != null;
		var name = placedIdent();
		expect(DblDot);
		var type = typeHint();
		if (optional) type = {type:CTOptional(type), pos:type.pos};
		var end = accept(Semicolon);
		return {cffName:name, cffDoc:doc, cffPos:end == null ? union(start, type.pos) : union(start, end.pos), cffMeta:meta, cffAccess:accesses, cffKind:FVar(type, null)};
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
		while(true) switch(current().token) {
			case Comment(v):
				next();
				if(StringTools.startsWith(v,"*")) {
					value=v.substr(1);
					// Haxe accepts the common `**/` closing style and excludes its
					// extra star from the documentation text.
					if(StringTools.endsWith(value,"*")) value=value.substr(0,value.length-1);
				}
			case CommentLine(_): next();
			case _: return Ast.docFromStringOpt(value);
		}
	}
	function metadata():Metadata {
		var result=[];
		while(accept(At)!=null) { var start=previous().pos; expect(DblDot); var name=placedPath(); var values=[]; if(accept(POpen)!=null) { if(!is(PClose)) do values.push(expression()) while(accept(Comma)!=null); expect(PClose); } result.push({meta:[for(n in name)n.name].join("."),exprs:values,pos:union(start,name[name.length-1].pos)}); }
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
