package core;

import core.Globals.Pos;
import core.Globals.GlobalTypePath;

// Port of haxe/src/core/ast.ml.  This module intentionally keeps source AST
// nodes separate from the typed AST in typer.ml.

enum Keyword { Function; Class; Var; If; Else; While; Do; For; Break; Continue; Return; Extends; Implements; Import; Switch; Case; Default; Static; Public; Private; Try; Catch; New; This; Throw; Extern; Enum; In; Interface; Untyped; Cast; Override; Typedef; Dynamic; Package; Inline; Using; Null; True; False; Abstract; Macro; Final; Operator; Overload; }
enum Binop { OpAdd; OpMult; OpDiv; OpSub; OpAssign; OpEq; OpNotEq; OpGt; OpGte; OpLt; OpLte; OpAnd; OpOr; OpXor; OpBoolAnd; OpBoolOr; OpShl; OpShr; OpUShr; OpMod; OpAssignOp(op:Binop); OpInterval; OpArrow; OpIn; OpNullCoal; }
enum Unop { Increment; Decrement; Not; Neg; NegBits; Spread; }
enum StringLiteralKind { SDoubleQuotes; SSingleQuotes; }
enum Constant { Int(value:String, suffix:Null<String>); Float(value:String, suffix:Null<String>); String(value:String, kind:StringLiteralKind); Ident(value:String); Regexp(pattern:String, options:String); }
enum Token { Eof; Const(value:Constant); Kwd(value:Keyword); Comment(value:String); CommentLine(value:String); Binop(value:Binop); Unop(value:Unop); Semicolon; Comma; BrOpen; BrClose; BkOpen; BkClose; POpen; PClose; Dot; DblDot; QuestionDot; Arrow; IntInterval(value:String); Sharp(value:String); Question; At; Dollar(value:String); Spread; }
enum UnopFlag { Prefix; Postfix; }
enum WhileFlag { NormalWhile; DoWhile; }
enum QuoteStatus { NoQuotes; DoubleQuotes; }
enum FunctionKind { FKAnonymous; FKNamed(name:PlacedName, isInline:Bool); FKArrow; }
enum DisplayKind { DKCall; DKDot; DKStructure; DKMarked; DKPattern(isOuter:Bool); }
enum EFieldKind { EFNormal; EFSafe; }
enum Access { APublic; APrivate; AStatic; AOverride; ADynamic; AInline; AMacro; AFinal; AExtern; AAbstract; AOverload; AEnum; }
enum ClassFieldKind { FVar(type:Null<TypeHint>, expr:Null<Expr>); FFun(func:Func); FProp(get:PlacedName, set:PlacedName, type:Null<TypeHint>, expr:Null<Expr>); }
enum EnumFlag { EPrivate; EExtern; }
enum ClassFlag { HInterface; HExtern; HPrivate; HExtends(path:PlacedTypePath); HImplements(path:PlacedTypePath); HFinal; HAbstract; }
enum AbstractFlag { AbPrivate; AbFrom(type:TypeHint); AbTo(type:TypeHint); AbOver(type:TypeHint); AbExtern; AbEnum; }
enum TypedefFlag { TDPrivate; TDExtern; }
enum ImportMode { INormal; IAsName(name:PlacedName); IAll; }

typedef PlacedName = { var name:String; var pos:Pos; }
typedef TypePath = { var tpackage:Array<String>; var tname:String; var tparams:Array<TypeParamOrConst>; var tsub:Null<String>; }
typedef PlacedTypePath = { var path:TypePath; var posFull:Pos; var posPath:Pos; }
typedef TypeHint = { var type:ComplexType; var pos:Pos; }
typedef MetadataEntry = { var meta:Dynamic; var exprs:Array<Expr>; var pos:Pos; }
typedef Metadata = Array<MetadataEntry>;
typedef Documentation = Null<DocBlock>;
typedef DocBlock = { var docOwn:Null<String>; var docInherited:Array<String>; }
typedef Func = { var fParams:Array<TypeParam>; var fArgs:Array<FuncArg>; var fType:Null<TypeHint>; var fExpr:Null<Expr>; }
typedef FuncArg = { var name:PlacedName; var optional:Bool; var meta:Metadata; var type:Null<TypeHint>; var expr:Null<Expr>; }
typedef TypeParam = { var tpName:PlacedName; var tpParams:Array<TypeParam>; var tpConstraints:Null<TypeHint>; var tpDefault:Null<TypeHint>; var tpMeta:Metadata; }
typedef ClassField = { var cffName:PlacedName; var cffDoc:Documentation; var cffPos:Pos; var cffMeta:Metadata; var cffAccess:Array<PlacedAccess>; var cffKind:ClassFieldKind; }
typedef PlacedAccess = { var access:Access; var pos:Pos; }
typedef EVar = { var evName:PlacedName; var evFinal:Bool; var evStatic:Bool; var evType:Null<TypeHint>; var evExpr:Null<Expr>; var evMeta:Metadata; }
typedef EnumConstructor = { var ecName:PlacedName; var ecDoc:Documentation; var ecMeta:Metadata; var ecArgs:Array<EnumConstructorArg>; var ecPos:Pos; var ecParams:Array<TypeParam>; var ecType:Null<TypeHint>; }
typedef EnumConstructorArg = { var name:String; var optional:Bool; var type:TypeHint; }
typedef Import = { var path:Array<PlacedName>; var mode:ImportMode; }
typedef TypeDecl = { var definition:TypeDef; var pos:Pos; }
typedef Package = { var pack:Array<String>; var declarations:Array<TypeDecl>; }
typedef Expr = { var expr:ExprDef; var pos:Pos; }

enum TypeParamOrConst { TPType(type:TypeHint); TPExpr(expr:Expr); }
enum ComplexType { CTPath(path:PlacedTypePath); CTFunction(args:Array<TypeHint>, ret:TypeHint); CTAnonymous(fields:Array<ClassField>); CTParent(type:TypeHint); CTExtend(paths:Array<PlacedTypePath>, fields:Array<ClassField>); CTOptional(type:TypeHint); CTNamed(name:PlacedName, type:TypeHint); CTIntersection(types:Array<TypeHint>); }
enum ExprDef { EConst(constant:Constant); EArray(array:Expr, index:Expr); EBinop(op:Binop, left:Expr, right:Expr); EField(expr:Expr, field:String, kind:EFieldKind); EParenthesis(expr:Expr); EObjectDecl(fields:Array<ObjectField>); EArrayDecl(values:Array<Expr>); ECall(expr:Expr, args:Array<Expr>); ENew(path:PlacedTypePath, args:Array<Expr>); EUnop(op:Unop, flag:UnopFlag, expr:Expr); EVars(vars:Array<EVar>); EFunction(kind:FunctionKind, func:Func); EBlock(exprs:Array<Expr>); EFor(iterator:Expr, body:Expr); EIf(condition:Expr, thenExpr:Expr, elseExpr:Null<Expr>); EWhile(condition:Expr, body:Expr, flag:WhileFlag); ESwitch(expr:Expr, cases:Array<SwitchCase>, defaultCase:Null<SwitchDefault>); ETry(expr:Expr, catches:Array<Catch>); EReturn(expr:Null<Expr>); EBreak; EContinue; EUntyped(expr:Expr); EThrow(expr:Expr); ECast(expr:Expr, type:Null<TypeHint>); EIs(expr:Expr, type:TypeHint); EDisplay(expr:Expr, kind:DisplayKind); ETernary(condition:Expr, thenExpr:Expr, elseExpr:Expr); ECheckType(expr:Expr, type:TypeHint); EMeta(meta:MetadataEntry, expr:Expr); }
enum TypeDef { EClass(definition:ClassDefinition); EEnum(definition:EnumDefinition); ETypedef(definition:TypedefDefinition); EAbstract(definition:AbstractDefinition); EStatic(definition:StaticDefinition); EImport(value:Import); EUsing(path:Array<PlacedName>); }
typedef ObjectField = { var key:{var name:String; var pos:Pos; var quote:QuoteStatus;}; var expr:Expr; }
typedef SwitchCase = { var values:Array<Expr>; var guard:Null<Expr>; var expr:Null<Expr>; var pos:Pos; }
typedef SwitchDefault = { var expr:Null<Expr>; var pos:Pos; }
typedef Catch = { var name:PlacedName; var type:Null<TypeHint>; var expr:Expr; var pos:Pos; }
typedef ClassDefinition = { var name:PlacedName; var doc:Documentation; var params:Array<TypeParam>; var meta:Metadata; var flags:Array<ClassFlag>; var data:Array<ClassField>; }
typedef EnumDefinition = { var name:PlacedName; var doc:Documentation; var params:Array<TypeParam>; var meta:Metadata; var flags:Array<EnumFlag>; var data:Array<EnumConstructor>; }
typedef TypedefDefinition = { var name:PlacedName; var doc:Documentation; var params:Array<TypeParam>; var meta:Metadata; var flags:Array<TypedefFlag>; var data:TypeHint; }
typedef AbstractDefinition = { var name:PlacedName; var doc:Documentation; var params:Array<TypeParam>; var meta:Metadata; var flags:Array<AbstractFlag>; var data:Array<ClassField>; }
typedef StaticDefinition = { var name:PlacedName; var doc:Documentation; var params:Array<TypeParam>; var meta:Metadata; var flags:Array<PlacedAccess>; var data:ClassFieldKind; }

class Ast {
 public static function dumpWithPos(e:Expr):String {
  var buf=new StringBuf();
  function line(tabs:String,p:Pos,s:String):Void buf.add(StringTools.lpad(Std.string(p.pmin)," ",4)+"-"+StringTools.lpad(Std.string(p.pmax)," ",4)+" "+tabs+s+"\n");
  function walk(tabs:String,e:Expr):Void {
   function add(s:String):Void line(tabs,e.pos,s);
   function loop(e:Expr):Void walk(tabs+"  ",e);
   switch e.expr {
    case EConst(c):add(sConstant(c));
    case EArray(a,b):add("EArray");loop(a);loop(b);
    case EBinop(op,a,b):add("EBinop "+sBinop(op));loop(a);loop(b);
    case EField(a,name,_):add("EField "+name);loop(a);
    case EParenthesis(a):add("EParenthesis");loop(a);
    case EObjectDecl(fl):add("EObjectDecl");for(f in fl){line(tabs,f.key.pos,f.key.name);loop(f.expr);}
    case EArrayDecl(el):add("EArrayDecl");for(a in el)loop(a);
    case ECall(a,el):add("ECall");loop(a);for(a in el)loop(a);
    case ENew(tp,el):add("ENew "+Globals.sTypePath({pack:tp.path.tpackage,name:tp.path.tname}));for(a in el)loop(a);
    case EUnop(op,_,a):add("EUnop "+sUnop(op));loop(a);
    case EVars(vl):add("EVars");for(v in vl){add(tabs+"  "+v.evName.name+(v.evType==null?"":":"+AstPrinter.sComplexType("",v.evType.type)));if(v.evExpr!=null)walk(tabs+"      ",v.evExpr);}
    case EFunction(_,f):add("EFunction");if(f.fExpr!=null)loop(f.fExpr);
    case EBlock(el):add("EBlock");for(a in el)loop(a);
    case EFor(a,b):add("EFor");loop(a);loop(b);
    case EIf(a,b,c):add("EIf");loop(a);loop(b);if(c!=null)loop(c);
    case EWhile(a,b,_):add("EWhile");loop(a);loop(b);
    case ESwitch(a,cases,def):add("ESwitch");loop(a);for(c in cases){for(a in c.values)walk(tabs+"    ",a);if(c.expr!=null)walk(tabs+"      ",c.expr);}if(def!=null&&def.expr!=null)walk(tabs+"      ",def.expr);
    case ETry(a,catches):add("ETry");loop(a);for(c in catches)walk(tabs+"    ",c.expr);
    case EReturn(a):add("EReturn");if(a!=null)loop(a);
    case EBreak:add("EBreak");case EContinue:add("EContinue");
    case EUntyped(a):add("EUntyped");loop(a);case EThrow(a):add("EThrow");loop(a);
    case ECast(a,_):add("ECast");loop(a);case EIs(a,_):add("EIs");loop(a);
    case EDisplay(a,k):add("EDisplay "+switch k {case DKCall:"DKCall";case DKDot:"DKDot";case DKStructure:"DKStructure";case DKMarked:"DKMarked";case DKPattern(_):"DKPattern";});loop(a);
    case ETernary(a,b,c):add("ETernary");loop(a);loop(b);loop(c);
    case ECheckType(a,_):add("ECheckType");loop(a);case EMeta(m,a):add("EMeta "+core.Meta.toString(m.meta));loop(a);
   }
  }
  walk("",e);return buf.toString();
 }
 public static function mkEvar(name:PlacedName,?type:TypeHint,?expr:Expr,?meta:Metadata,isFinal:Bool=false,isStatic:Bool=false):EVar return {evName:name,evFinal:isFinal,evStatic:isStatic,evType:type,evExpr:expr,evMeta:meta==null?[]:meta};
 public static function stringPosListOfExprPathRaise(e:Expr):Array<PlacedName> return switch e.expr {case EConst(Ident(name)):[{name:name,pos:e.pos}];case EField(inner,name,_):[{name:name,pos:e.pos}].concat(stringPosListOfExprPathRaise(inner));case _:throw new core.ds.Exit();};
 public static function fullDotPath2(mpath:GlobalTypePath,tpath:GlobalTypePath):Array<String> return core.ds.Key.compare(mpath,tpath)==0?tpath.pack.concat([tpath.name]):mpath.pack.concat([mpath.name,tpath.name]);
 public static function iterExpr(loop:Expr->Void,e:Expr):Void {
  function opt(e:Null<Expr>):Void if(e!=null) loop(e);
  switch e.expr {
   case EConst(_) | EContinue | EBreak | EReturn(null):
   case EParenthesis(e) | EField(e,_,_) | EUnop(_,_,e) | EReturn(e) | EThrow(e) | EMeta(_,e) | ECheckType(e,_) | EDisplay(e,_) | ECast(e,_) | EIs(e,_) | EUntyped(e):loop(e);
   case EArray(a,b) | EBinop(_,a,b) | EFor(a,b) | EWhile(a,b,_) | EIf(a,b,null):loop(a);loop(b);
   case ETernary(a,b,c) | EIf(a,b,c):loop(a);loop(b);loop(c);
   case EArrayDecl(el) | ENew(_,el) | EBlock(el):for(e in el)loop(e);
   case ECall(e,el):loop(e);for(e in el)loop(e);
   case EObjectDecl(fields):for(f in fields)loop(f.expr);
   case ETry(e,catches):loop(e);for(c in catches)loop(c.expr);
   case ESwitch(e,cases,def):loop(e);for(c in cases){for(e in c.values)loop(e);opt(c.guard);opt(c.expr);}if(def!=null)opt(def.expr);
   case EFunction(_,f):for(a in f.fArgs)opt(a.expr);opt(f.fExpr);
   case EVars(vars):for(v in vars)opt(v.evExpr);
  }
 }
 public static function exists(check:ExprDef->Bool,e:Expr):Bool {
  function loop(e:Expr):Void {if(check(e.expr))throw new core.ds.Exit();iterExpr(loop,e);}
  try {loop(e);return false;}catch(_:core.ds.Exit){return true;}
 }
 public static function removeDuplicates<T>(keep:T->T->Bool,items:Array<T>):Array<T> {
  if(items.length==0)return [];
  var first=items[0];return [first].concat(removeDuplicates(keep,items.slice(1).filter(item->keep(first,item))));
 }
 public static function getValueMeta(meta:Metadata):haxe.ds.StringMap<Expr> {
  var result=new haxe.ds.StringMap<Expr>();
  try {var entry=core.Meta.get(core.Meta.Value,meta);if(entry.exprs.length==1)switch entry.exprs[0].expr {case EObjectDecl(values):for(value in values)result.set(value.key.name,value.expr);case _:}}catch(_:core.ds.NotFound){}
  return result;
 }

	// haxe/src/core/ast.ml: match_path.
	public static function matchPath(recursive:Bool,path:Array<String>,pattern:Array<String>):Bool {
		function loop(top:Bool,pi:Int,mi:Int):Bool {
			if (mi<pattern.length && pattern[mi]=="**") {
				if (mi+1==pattern.length) return true;
				return loop(false,pi,mi+1) || (pi<path.length && loop(false,pi+1,mi));
			}
			if (pi==path.length && mi==pattern.length) return true;
			if (pi+1<path.length && mi+1==pattern.length && isLowerIdent(pattern[mi]) && !isLowerIdent(path[pi+1]))
				return path[pi]==pattern[mi];
			if (pi+1==path.length && mi==pattern.length && top) return true;
			if (mi==pattern.length) return recursive;
			if (pi==path.length) return false;
			return (pattern[mi]=="*" || path[pi]==pattern[mi]) && loop(false,pi+1,mi+1);
		}
		return loop(true,0,0);
	}

 public static function getMetaString(meta:Metadata,key:core.MetaList.StrictMeta):Null<String> {
  for(entry in meta)if(core.Meta.has(key,[entry])&&entry.exprs.length==1)switch entry.exprs[0].expr {case EConst(String(name,_)):return name;case _:}
  return null;
 }

 public static function mapExpr(loop:Expr->Expr,e:Expr):Expr return new AstExprMapper(loop).map(e);
	public static function mkTypePath(pack:Array<String>, name:String, ?params:Array<TypeParamOrConst>, ?sub:String):TypePath {
		if (name == "") throw "Empty module name is not allowed";
		return {tpackage: pack, tname: name, tparams: params == null ? [] : params, tsub: sub};
	}
	public static function mkEVar(name:PlacedName, ?finalValue = false, ?staticValue = false, ?type:TypeHint, ?expr:Expr, ?meta:Metadata):EVar
		return {evName: name, evFinal: finalValue, evStatic: staticValue, evType: type, evExpr: expr, evMeta: meta == null ? [] : meta};
	public static function makePtp(path:TypePath, posFull:Pos, ?posPath:Pos):PlacedTypePath return {path: path, posFull: posFull, posPath: posPath == null ? posFull : posPath};
	public static function makePtpCt(path:TypePath, posFull:Pos, ?posPath:Pos):ComplexType return CTPath(makePtp(path, posFull, posPath));
	public static function makePtpTh(path:TypePath, posFull:Pos, ?posPath:Pos):TypeHint return {type: makePtpCt(path, posFull, posPath), pos: posFull};
	public static function ctMono():ComplexType return makePtpCt(mkTypePath(["$"], "_hx_mono"), Globals.nullPos);
	public static inline function pos(expr:Expr):Pos return expr.pos;
	public static function docFromString(value:String):Documentation return {docOwn: value, docInherited: []};
	public static function docFromStringOpt(value:Null<String>):Documentation return value == null ? null : docFromString(value);
	public static function genDocText(doc:DocBlock):String return (doc.docOwn == null ? [] : [doc.docOwn]).concat(doc.docInherited).join("\n");
	public static function genDocTextOpt(doc:Documentation):Null<String> return doc == null ? null : genDocText(doc);
	public static function getOwnDocOpt(doc:Documentation):Null<String> return doc == null ? null : doc.docOwn;
	public static function isLowerIdent(value:String):Bool { if (value.length == 0) throw new core.ds.InvalidArgument("Identifier name must not be empty"); var i = 0; while (true) { var c = value.charAt(i); if (c >= "a" && c <= "z") return true; if (c != "_") return false; i++; if (i >= value.length) return true; } }
	public static function isPostfix(op:Unop):Bool return switch op { case Increment | Decrement | Not: true; case Neg | NegBits | Spread: false; };
	public static function punion(a:Pos, b:Pos):Pos return {pfile: a.pfile, pmin: a.pmin < b.pmin ? a.pmin : b.pmin, pmax: a.pmax > b.pmax ? a.pmax : b.pmax};
	public static function punionEl(exprs:Array<Expr>):Pos { if (exprs.length == 0) return Globals.nullPos; var result = exprs[0].pos; for (i in 1...exprs.length) result = punion(result, exprs[i].pos); return result; }
	public static function parsePath(value:String):TypePathParts { var parts = value.split("."); var name = parts.pop(); return {pack: parts, name: name}; }
	public static function sConstant(value:Constant):String return switch value { case Int(v, suffix) | Float(v, suffix): v + (suffix == null ? "" : suffix); case String(v, kind): '"' + StringHelper.sEscape(v) + '"'; case Ident(v): v; case Regexp(pattern, _): "~/" + pattern + "/"; };
	public static function sAccess(value:Access):String return switch value { case APublic: "public"; case APrivate: "private"; case AStatic: "static"; case AOverride: "override"; case ADynamic: "dynamic"; case AInline: "inline"; case AMacro: "macro"; case AFinal: "final"; case AExtern: "extern"; case AAbstract: "abstract"; case AOverload: "overload"; case AEnum: "enum"; };
	public static function sKeyword(value:Keyword):String return switch value { case Function: "function"; case Class: "class"; case Var: "var"; case If: "if"; case Else: "else"; case While: "while"; case Do: "do"; case For: "for"; case Break: "break"; case Continue: "continue"; case Return: "return"; case Extends: "extends"; case Implements: "implements"; case Import: "import"; case Switch: "switch"; case Case: "case"; case Default: "default"; case Static: "static"; case Public: "public"; case Private: "private"; case Try: "try"; case Catch: "catch"; case New: "new"; case This: "this"; case Throw: "throw"; case Extern: "extern"; case Enum: "enum"; case In: "in"; case Interface: "interface"; case Untyped: "untyped"; case Cast: "cast"; case Override: "override"; case Typedef: "typedef"; case Dynamic: "dynamic"; case Package: "package"; case Inline: "inline"; case Using: "using"; case Null: "null"; case True: "true"; case False: "false"; case Abstract: "abstract"; case Macro: "macro"; case Final: "final"; case Operator: "operator"; case Overload: "overload"; };
	public static function sBinop(value:Binop):String return switch value { case OpAdd: "+"; case OpMult: "*"; case OpDiv: "/"; case OpSub: "-"; case OpAssign: "="; case OpEq: "=="; case OpNotEq: "!="; case OpGt: ">"; case OpGte: ">="; case OpLt: "<"; case OpLte: "<="; case OpAnd: "&"; case OpOr: "|"; case OpXor: "^"; case OpBoolAnd: "&&"; case OpBoolOr: "||"; case OpShl: "<<"; case OpShr: ">>"; case OpUShr: ">>>"; case OpMod: "%"; case OpAssignOp(op): sBinop(op) + "="; case OpInterval: "..."; case OpArrow: "=>"; case OpIn: " in "; case OpNullCoal: "??"; };
	public static function sUnop(value:Unop):String return switch value { case Increment: "++"; case Decrement: "--"; case Not: "!"; case Neg: "-"; case NegBits: "~"; case Spread: "..."; };
 public static function sPlacedAccess(value:PlacedAccess):String return sAccess(value.access);
 public static function sToken(t:Token):String return switch t {
  case Eof:"<end of file>";case Const(c):sConstant(c);case Kwd(k):sKeyword(k);
  case Comment(s):"/*"+s+"*/";case CommentLine(s):"//"+s;case Binop(o):sBinop(o);case Unop(o):sUnop(o);
  case Semicolon:";";case Comma:",";case BkOpen:"[";case BkClose:"]";case BrOpen:"{";case BrClose:"}";case POpen:"(";case PClose:")";
  case Dot:".";case DblDot:":";case QuestionDot:"?.";case Arrow:"->";case IntInterval(s):s+"...";case Sharp(s):"#"+s;case Question:"?";case At:"@";case Dollar(v):"$"+v;case Spread:"...";
 };
 public static function stringListOfExprPathRaise(e:Expr,?rootCb:String->Array<String>):Array<String> return switch e.expr {
  case EConst(Ident(i)):rootCb==null?[i]:rootCb(i);
  case EField(e,f,_):[f].concat(stringListOfExprPathRaise(e,rootCb));
  case _:throw new core.ds.Exit();
 };

 public static function exprOfTypePath(path:GlobalTypePath,p:Pos):Expr {
  if(path.pack.length==0)return {expr:EConst(Ident(path.name)),pos:p};
  var e:Expr={expr:EConst(Ident(path.pack[0])),pos:p};
  for(s in path.pack.slice(1))e={expr:EField(e,s,EFNormal),pos:p};
  return {expr:EField(e,path.name,EFNormal),pos:p};
 }
 public static function hasMetaOption(metas:Metadata,meta:core.MetaList.StrictMeta,s:String):Bool {
  for(entry in metas)if(core.Meta.has(meta,[entry]))for(e in entry.exprs)switch e.expr {
   case EConst(Ident(s2)) if(s==s2):return true;
   case _:
  }
  return false;
 }

}

typedef TypePathParts = {var pack:Array<String>; var name:String;}
