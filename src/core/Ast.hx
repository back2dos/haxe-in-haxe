package core;

import core.Globals.Pos;

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
	public static function isLowerIdent(value:String):Bool { if (value.length == 0) throw "Identifier name must not be empty"; var i = 0; while (true) { var c = value.charAt(i); if (c >= "a" && c <= "z") return true; if (c != "_") return false; i++; if (i >= value.length) return true; } }
	public static function isPostfix(op:Unop):Bool return switch op { case Increment | Decrement | Not: true; case Neg | NegBits | Spread: false; };
	public static function punion(a:Pos, b:Pos):Pos return {pfile: a.pfile, pmin: a.pmin < b.pmin ? a.pmin : b.pmin, pmax: a.pmax > b.pmax ? a.pmax : b.pmax};
	public static function punionEl(exprs:Array<Expr>):Pos { if (exprs.length == 0) return Globals.nullPos; var result = exprs[0].pos; for (i in 1...exprs.length) result = punion(result, exprs[i].pos); return result; }
	public static function parsePath(value:String):TypePathParts { var parts = value.split("."); var name = parts.pop(); return {pack: parts, name: name}; }
	public static function sConstant(value:Constant):String return switch value { case Int(v, suffix) | Float(v, suffix): v + (suffix == null ? "" : suffix); case String(v, kind): '"' + StringHelper.sEscape(v) + '"'; case Ident(v): v; case Regexp(pattern, _): "~/" + pattern + "/"; };
	public static function sAccess(value:Access):String return switch value { case APublic: "public"; case APrivate: "private"; case AStatic: "static"; case AOverride: "override"; case ADynamic: "dynamic"; case AInline: "inline"; case AMacro: "macro"; case AFinal: "final"; case AExtern: "extern"; case AAbstract: "abstract"; case AOverload: "overload"; case AEnum: "enum"; };
	public static function sKeyword(value:Keyword):String return switch value { case Function: "function"; case Class: "class"; case Var: "var"; case If: "if"; case Else: "else"; case While: "while"; case Do: "do"; case For: "for"; case Break: "break"; case Continue: "continue"; case Return: "return"; case Extends: "extends"; case Implements: "implements"; case Import: "import"; case Switch: "switch"; case Case: "case"; case Default: "default"; case Static: "static"; case Public: "public"; case Private: "private"; case Try: "try"; case Catch: "catch"; case New: "new"; case This: "this"; case Throw: "throw"; case Extern: "extern"; case Enum: "enum"; case In: "in"; case Interface: "interface"; case Untyped: "untyped"; case Cast: "cast"; case Override: "override"; case Typedef: "typedef"; case Dynamic: "dynamic"; case Package: "package"; case Inline: "inline"; case Using: "using"; case Null: "null"; case True: "true"; case False: "false"; case Abstract: "abstract"; case Macro: "macro"; case Final: "final"; case Operator: "operator"; case Overload: "overload"; };
	public static function sBinop(value:Binop):String return switch value { case OpAdd: "+"; case OpMult: "*"; case OpDiv: "/"; case OpSub: "-"; case OpAssign: "="; case OpEq: "=="; case OpNotEq: "!="; case OpGt: ">"; case OpGte: ">="; case OpLt: "<"; case OpLte: "<="; case OpAnd: "&"; case OpOr: "|"; case OpXor: "^"; case OpBoolAnd: "&&"; case OpBoolOr: "||"; case OpShl: "<<"; case OpShr: ">>"; case OpUShr: ">>>"; case OpMod: "%"; case OpAssignOp(op): sBinop(op) + "="; case OpInterval: "..."; case OpArrow: "=>"; case OpIn: " in "; case OpNullCoal: "??"; };
	public static function sUnop(value:Unop):String return switch value { case Increment: "++"; case Decrement: "--"; case Not: "!"; case Neg: "-"; case NegBits: "~"; case Spread: "..."; };
}

typedef TypePathParts = {var pack:Array<String>; var name:String;}
