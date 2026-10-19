package typing.matcher;

import core.MetaList.StrictMeta as MetaTag;
import core.TType;
import core.Globals.Pos;
import core.Globals.*;
import core.Texpr.Builder;
import core.TFunctions.*;
import core.TOther.*;
import context.Typecore;
import typing.matcher.Bind;
import typing.matcher.Constructor;
import typing.TyperBase.ArrayAccessData;

// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream: type_finiteness moved here from decisionTree.ml.
enum TypeFiniteness {
	Infinite; // type has inifite constructors (e.g. Int, String)
	CompileTimeFinite; // type is considered finite only at compile-time but has inifite possible run-time values (enum abstracts)
	RunTimeFinite; // type is truly finite (Bool, enums)
}

// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream (its comments follow).
// How array patterns read the elements and the length of a subject.
// port: index_access, renamed: its constructor IndexAccess has the type's name.
enum IndexAccessKind {
	IndexArray; // like those of an array
	IndexAccess(aa:ArrayAccessData); // the way for loops read them (#8012)
}

// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream: match_kind moved here from texprConverter.ml (its
// ... comments follow).
// How a switch tests its subject.
enum MatchKind {
	SKValue; // against constants, statics and types
	SKEnum; // by the index of its enum constructor
	SKLength(access:IndexAccessKind); // by its length
}

// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream (its comments follow).
// A switch's subject: its expression and what the switch makes of it, which [make] decides from the subject's type
// and the switch's constructors.
// port: Subject.t, beside the subject class (as DecisionTreeData is DecisionTree.t).
@:structInit class SubjectData {
	public final sExpr:TExpr;
	public final sKind:MatchKind;
	public final sFiniteness:TypeFiniteness;
	public final sConstructors:Array<ConstructorData>; // the constructors of the subject's type
	public final sNullable:Bool;

	public inline function new(sExpr:TExpr, sKind:MatchKind, sFiniteness:TypeFiniteness, sConstructors:Array<ConstructorData>,
			sNullable:Bool) {
		this.sExpr = sExpr;
		this.sKind = sKind;
		this.sFiniteness = sFiniteness;
		this.sConstructors = sConstructors;
		this.sNullable = sNullable;
	}
}

class Subject {
	final e:TExpr;
	final bind:Null<Bind>;
	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream.
	var indexAccess:Null<IndexAccessKind> = null;

	public function new(e:TExpr, bind:Null<Bind>) {
		this.e = e;
		this.bind = bind;
	}

	public function getExpr():TExpr {
		if (bind != null) bind.bStatus = BindUsed;
		return e;
	}

	public function getScopedExpr():{expr:TExpr, reset:Void->Void} {
		if (bind != null && bind.bStatus == BindDeferred) {
			// For deferred bindings, we generate `subject = expr` and mark the binding as used so that
			// subsequent calls to this function do not generate the assignment again. The returned function
			// can be used to reset the status back to BindDeferred, for cases where we need to initalize
			// again in an unrelated scope.
			var assigned = Builder.binop(OpAssign, e, bind.bExpr, e.etype, e.epos);
			bind.bStatus = BindUsed;
			return {
				expr: assigned,
				reset: function() {
					bind.bStatus = BindDeferred;
				}
			};
		}
		if (bind != null && bind.bStatus == BindUnused) bind.bStatus = BindUsed;
		return {expr: e, reset: function() {}};
	}

	public function getAssignedExpr():TExpr {
		var scoped = getScopedExpr();
		scoped.reset();
		return scoped.expr;
	}

	public function getPos():Pos return e.epos;

	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream.
	public function isNullable():Bool return MatcherGlobals.isExplicitNullOrAbstractOverThat(e.etype);

	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream (its comment follows).
	// How array patterns read this subject, looked up when they first do.
	public function getIndexAccess(ctx:Typer):IndexAccessKind {
		if (indexAccess != null) return indexAccess;
		var aa = ExprToPattern.getArrayAccess(ctx, e.etype, e.epos);
		var access = aa != null ? IndexAccess(aa) : IndexArray;
		indexAccess = access;
		return access;
	}

	public function toString():String return MatcherGlobals.sExprPretty(e);

	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream: s_match_kind moved here from texprConverter.ml.
	public static function sMatchKind(k:MatchKind):String return switch k {
		case SKValue: "value";
		case SKEnum: "enum";
		case SKLength(_): "length";
	};

	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream: extract_ctor moved here from texprConverter.ml.
	public static function extractCtor(e:TExpr):Null<ConstructorKind> return switch e.eexpr {
		case TConst(ct): ConConst(ct);
		case TField(_, FEnum(en, ef)): ConEnum(en, ef);
		case TCast(e1, null): extractCtor(e1);
		case _: null;
	};

	// port: HaxeFoundation/haxe#13071, ahead of the pinned upstream: all_ctors's type analysis, moved here from
	// ... texprConverter.ml (its comments follow).
	// The subject of a switch on [subject] which uses it as [e] and has the constructors [cons], in the order of its
	// cases.
	public static function make(ctx:Typer, subject:Subject, e:TExpr, cons:Array<ConstructorData>):SubjectData {
		var t = switch follow(e.etype) {
			case TDynamic(_) | TMono(_) if (cons.length > 0):
				function fail():T {
					// error "Could not determine switch kind, make sure the type is known" e.epos;
					return tDynamic;
				}
				switch cons[0].kind {
					case ConEnum(en, _): TEnum(en, extractParamTypes(en.eParams));
					case ConArray(_): ctx.t.tarray(tDynamic);
					case ConConst(ct): switch ct {
							case TString(_): ctx.t.tstring;
							case TInt(_): ctx.t.tint;
							case TFloat(_): ctx.t.tfloat;
							case TBool(_): ctx.t.tbool;
							case _: fail();
						}
					case ConStatic({clKind: KAbstractImpl(a)}, _): TAbstract(a, extractParamTypes(a.aParams));
					case ConTypeExpr(mt): ExprToPattern.getGeneralModuleType(ctx, mt, e.epos);
					case ConFields(_) | ConStatic(_, _): fail();
				}
			case _:
				e.etype;
		};
		// port: the constructors are kept distinct as they are added (a replaced one keeps its place), as the
		// ... ConTable of unmatched_ctors makes them.
		var constructors:Array<ConstructorData> = [];
		function add(kind:ConstructorKind):Void {
			var con = ({kind: kind, pos: nullPos} : ConstructorData);
			for (i in 0...constructors.length) if (Constructor.equal(constructors[i], con)) {
				constructors[i] = con;
				return;
			}
			constructors.push(con);
		}
		function loop(deep:Bool, t:T):{kind:MatchKind, finiteness:TypeFiniteness}
			return switch follow(t) {
				case TAbstract({aPath: {pack: [], name: "Bool"}}, _):
					if (!deep) {
						add(ConConst(TBool(true)));
						add(ConConst(TBool(false)));
					}
					{kind: SKValue, finiteness: RunTimeFinite};
				case TAbstract(a = {aImpl: c}, pl) if (c != null && a.aEnum):
					if (!deep) for (cf in c.clOrderedStatics) {
						follow(cf.cfType);
						if (hasClassFieldFlag(cf, CfImpl) && hasClassFieldFlag(cf, CfEnum)) {
							var ctor = cf.cfExpr == null ? null : extractCtor(cf.cfExpr);
							switch ctor {
								case ConConst(TNull):
								case null: add(ConStatic(c, cf));
								case ctor: add(ctor);
							}
						}
					}
					var real = loop(true, core.Abstract.getUnderlyingType(a, pl));
					{kind: real.kind, finiteness: CompileTimeFinite};
				case TAbstract(a, pl) if (!core.Meta.has(MetaTag.CoreType, a.aMeta)): loop(deep, core.Abstract.getUnderlyingType(a, pl));
				case TInst({clPath: {pack: [], name: "String"}},
					_) | TInst({clKind: KTypeParameter(_)}, _): {kind: SKValue, finiteness: Infinite};
				case TInst({clPath: {pack: [], name: "Array"}}, _): {kind: SKLength(IndexArray), finiteness: Infinite};
				// port: `constructors` is still empty here and the constructors are distinct, so they are pushed without add's
				// ... linear search.
				case TEnum(en, _):
					if (!deep) {
						var names = [for (n in en.eConstrs.keys()) n];
						names.sort(Reflect.compare);
						for (n in names) constructors.push(({
							kind: ConEnum(en, en.eConstrs.get(n)),
							pos: nullPos
						} : ConstructorData));
					}
					{kind: SKEnum, finiteness: RunTimeFinite};
				case _: {kind: SKValue, finiteness: Infinite};
			};
		var classified = loop(false, t);
		// Array patterns on values which can be accessed by index (#8012).
		if (cons.length > 0 && cons[0].kind.match(ConArray(_))) switch subject.getIndexAccess(ctx) {
			case access = IndexAccess(_):
				constructors = [];
				classified = {kind: SKLength(access), finiteness: Infinite};
			case IndexArray:
		}
		return {
			sExpr: e,
			sKind: classified.kind,
			sFiniteness: classified.finiteness,
			sConstructors: constructors,
			sNullable: subject.isNullable()
		};
	}
}
