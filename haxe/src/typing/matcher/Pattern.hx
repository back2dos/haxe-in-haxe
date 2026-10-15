package typing.matcher;

import core.TType;
import core.Globals.Pos;
import typing.matcher.Constructor;

enum PatternKind {
	PatConstructor(con:ConstructorData, patterns:Array<PatternData>);
	PatAny;
	PatBind(variable:TVar, pattern:PatternData);
	PatOr(left:PatternData, right:PatternData);
	PatTuple(patterns:Array<PatternData>);
	PatExtractor(extractor:Extractor);
}

@:structInit class PatternData {
	public var kind:PatternKind;
	public var pos:Pos;

	public inline function new(kind:PatternKind, pos:Pos) {
		this.kind = kind;
		this.pos = pos;
	}

	public inline function clone():PatternData return new PatternData(kind, pos);
}

typedef Extractor = {var exVar:TVar; // The _ local used for typing the expression
	var exExpr:TExpr; // The left side of the =>
	var exPattern:PatternData;} // The right side of the =>

class Pattern {
	public static function toString(pat:PatternData):String return switch pat.kind {
		case PatConstructor(con, patterns): Constructor.toString(con) + "(" + patterns.map(toString).join(", ") + ")";
		case PatAny: "_";
		case PatBind(v, {kind: PatAny}): v.vName + "<" + v.vId + ">";
		case PatBind(v, pat1): v.vName + " = " + toString(pat1);
		case PatOr(pat1, pat2): "(" + toString(pat1) + ") | (" + toString(pat2) + ")";
		case PatTuple(pl): "[" + pl.map(toString).join(", ") + "]";
		case PatExtractor(ex): MatcherGlobals.sExprPretty(ex.exExpr) + " => " + toString(ex.exPattern);
	};
}
