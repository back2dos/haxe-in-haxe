package generators;

import core.Globals;
import core.Globals.*;
import core.Ast;
import core.TType;
import core.TFunctions.*;
import core.Meta;

class Genhxold {
	static function create_dir(acc:String, l:Array<String>):Void {
		var acc = acc;
		for (d in l) {
			var path = acc + "/" + d;
			// port: Unix.mkdir, errors (an existing directory) ignored.
			try if (!sys.FileSystem.exists(path)) sys.FileSystem.createDirectory(path) catch (_:Dynamic) {}
			acc = path;
		}
	}

	static function conv_path(p:GlobalTypePath):GlobalTypePath {
		var pack = p.pack;
		if (pack.length > 0 && StringTools.startsWith(pack[pack.length - 1], "_")) {
			var pack = pack.copy();
			pack[pack.length - 1] = "priv" + pack[pack.length - 1];
			return {pack: pack, name: p.name};
		}
		return p;
	}

	// port: ExtString.String.nsplit; an empty string has no parts.
	static function nsplit(s:String, sep:String):Array<String> return s == "" ? [] : s.split(sep);

	static function get_real_path(meta:Metadata, path:GlobalTypePath):GlobalTypePath {
		try {
			var real_path = switch Meta.get(Meta.RealPath, meta) {
				case {exprs: [{expr: EConst(String(s, _))}]}:
					s;
				case _:
					throw core.ds.NotFound.raise();
			}
			var l = nsplit(real_path, ".");
			if (l.length == 0) throw core.ds.NotFound.raise();
			var name = l.pop();
			return {pack: l, name: name};
		} catch (_:core.ds.NotFound) {
			return path;
		}
	}

	// port: `string_of_int (int_of_float f)` with OCaml's 63-bit int (exact for
	// the integral floats whose representation could match).
	static function int_of_float_string(f:Float):String {
		if (Math.isNaN(f) || !Math.isFinite(f)) return "0";
		var t = f < 0 ? Math.fceil(f) : Math.ffloor(f);
		if (Math.abs(t) >= 4611686018427387904.0) return "0";
		return haxe.Int64.toStr(haxe.Int64.fromFloat(t));
	}

	// port: OCaml `compare` on strings (bytes).
	static function compareString(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0);

	static function generate_type(com:context.Common.CommonContext, t:ModuleType):Void {
		var base_path = "hxclasses";
		switch t {
			case TClassDecl({clKind: KAbstractImpl(_)}):
				return;
			case _:
		}
		var info = tInfos(t);
		var rp = get_real_path(info.mtMeta, info.mtPath);
		var pack = rp.pack, name = rp.name;
		create_dir(".", [base_path].concat(pack));
		switch [pack, name] {
			case [["flash", "net"], "NetStreamPlayTransitions"] | [["flash", "filters"], "BitmapFilterQuality"] | [["flash", "display"],
				"BitmapDataChannel" | "GraphicsPathCommand"]:
				return;
			case _:
		}
		var buf = new StringBuf();
		function p(s:String) buf.add(s);
		if (pack.length != 0) p("package " + pack.join(".") + ";\n\n");
		function notnull(t:T):T {
			return switch t {
				case TMono(r):
					switch r.tmType {
						case null: t;
						case t: notnull(t);
					}
				case TLazy(f):
					notnull(lazyType(f));
				case TAbstract({aPath: {pack: [], name: "Null"}}, [t]):
					t;
				case _:
					t;
			}
		}
		var stype:T->String = null;
		var ftype:T->String = null;
		function path(meta:Metadata, p:GlobalTypePath, tl:Array<T>):String {
			var p = conv_path(get_real_path(meta, p));
			return (if (p.pack.join(".") == pack.join(".") && p.pack.length == pack.length) p.name else sTypePath(p))
				+ (switch tl {
					case []: "";
					case _: "<" + tl.map(stype).join(",") + ">";
				});
		}
		stype = function(t:T):String {
			return switch t {
				case TMono(r):
					switch r.tmType {
						case null: "Unknown";
						case t: stype(t);
					}
				case TInst(c = {clKind: KTypeParameter(_)}, tl):
					path([], {pack: [], name: c.clPath.name}, tl);
				case TInst(c, tl):
					path(c.clMeta, c.clPath, tl);
				case TEnum(e, tl):
					path(e.eMeta, e.ePath, tl);
				case TType(t, tl):
					path(t.tMeta, t.tPath, tl);
				case TAbstract(a, tl):
					path(a.aMeta, a.aPath, tl);
				case TAnon(a):
					// port: PMap.fold visits the keys in ascending order, prepending.
					var fields = core.ds.PMap.fold((f:TClassField, acc:Array<String>) -> [f.cfName + " : " + stype(f.cfType)].concat(acc), a.aFields, []);
					"{" + fields.join(", ") + "}";
				case TLazy(f):
					stype(lazyType(f));
				case TDynamic(null):
					"Dynamic";
				case TDynamic(t2):
					"Dynamic<" + stype(t2) + ">";
				case TFun({args: [], ret: ret}):
					"() -> " + ftype(ret);
				case TFun({args: args, ret: ret}):
					args.map(a -> ftype(a.type)).join(" -> ") + " -> " + ftype(ret);
			}
		};
		ftype = function(t:T):String {
			return switch t {
				case TMono(r):
					switch r.tmType {
						case null: stype(t);
						case t: ftype(t);
					}
				case TLazy(f):
					ftype(lazyType(f));
				case TFun(_):
					"(" + stype(t) + ")";
				case _:
					stype(t);
			}
		};
		function sparam(n:String, v:Null<Constant>, t:T):String {
			return switch v {
				case null:
					n + " : " + stype(t);
				case Ident("null"):
					if (isNullable(notnull(t)))
						"?" + n + " : " + stype(notnull(t))
					else
						/* we have not found a default value stored in metadata, let's generate it */
						n + " : " + stype(t) + " = " + (switch follow(t) {
							case TAbstract({aPath: {pack: [], name: "Int" | "Float" | "UInt"}}, _) | TAbstract({aPath: {pack: ["haxe"], name: "UInt32"}}, _):
								"0";
							case TAbstract({aPath: {pack: [], name: "Bool"}}, _):
								"false";
							case _:
								"null";
						});
				case v:
					n + " : " + stype(t) + " = " + (switch Ast.sConstant(v) {
						case "nan": "0./*NaN*/";
						case v: v;
					});
			}
		}
		function print_meta(ml:Metadata):Void {
			for (m in ml) {
				if (Meta.metaEq(m.meta, Meta.DefParam) || Meta.metaEq(m.meta, Meta.CoreApi) || Meta.metaEq(m.meta, Meta.Used)
					|| Meta.metaEq(m.meta, Meta.FlatEnum) || Meta.metaEq(m.meta, Meta.Value) || Meta.metaEq(m.meta, Meta.DirectlyUsed)
					|| Meta.metaEq(m.meta, Meta.Enum)) continue;
				switch m.exprs {
					case []:
						p("@" + Meta.toString(m.meta) + " ");
					case l:
						p("@" + Meta.toString(m.meta) + "(" + l.map(core.AstPrinter.sExpr).join(",") + ") ");
				}
			}
		}
		function access(is_read:Bool, a:VarAccess):String return core.TPrinting.sAccess(is_read, a);
		function print_field(stat:Bool, f:TClassField):Void {
			p("\t");
			print_meta(f.cfMeta);
			if (!hasClassFieldFlag(f, CfPublic)) p("private ");
			if (stat) p("static ");
			var name = try (switch Meta.get(Meta.RealPath, f.cfMeta) {
				case {exprs: [{expr: EConst(String(s, _))}]}:
					s;
				case _:
					throw core.ds.NotFound.raise();
			}) catch (_:core.ds.NotFound) f.cfName;
			switch f.cfKind {
				case Var(v):
					if (hasClassFieldFlag(f, CfFinal))
						p("final " + name)
					else {
						p("var " + name);
						if (v.vRead != AccNormal || v.vWrite != AccNormal) p("(" + access(true, v.vRead) + "," + access(false, v.vWrite) + ")");
					}
					p(" : " + stype(f.cfType));
				case Method(_):
					var r = (switch follow(f.cfType) {
						case TFun({args: args, ret: ret}):
							{
								params: [
									for (a in args) {
										function loop(l:Metadata, i:Int):Constant {
											if (i >= l.length) return Ident("null");
											return switch l[i] {
												case {meta: m, exprs: [{expr: EConst(String(p, _))}, {expr: EConst(v)}]} if (Meta.metaEq(m, Meta.DefParam) && p == a.name):
													switch v {
														case Float("1.#QNAN", _): Float("0./*NaN*/", null);
														case Float("4294967295.", _): Int("0xFFFFFFFF", null);
														case Int("16777215", _): Int("0xFFFFFF", null);
														case Float(x, _):
															try {
																var f = core.ds.OcamlFloat.ofString(x);
																var s = int_of_float_string(f);
																if (s + "." == x) Int(s, null) else v;
															} catch (_:Dynamic) {
																v;
															}
														case _: v;
													}
												case _:
													loop(l, i + 1);
											}
										}
										{name: a.name, v: (if (a.optional) loop(f.cfMeta, 0) else null), t: a.type};
									}
								],
								ret: ret
							};
						case _:
							die("", "generators/genhxold.ml");
					});
					var tparams = (switch f.cfParams {
						case []: "";
						case l: "<" + l.map(extractParamName).join(",") + ">";
					});
					p("function " + name + tparams + "(" + r.params.map(x -> sparam(x.name, x.v, x.t)).join(", ") + ") : " + stype(r.ret));
			}
			p(";\n");
			if (hasClassFieldFlag(f, CfOverload)) for (f in f.cfOverloads) print_field(stat, f);
		}
		switch t {
			case TClassDecl(c):
				print_meta(c.clMeta);
				var finalmod = if (hasClassFlag(c, CFinal)) "final " else "";
				p("extern " + finalmod + (if (hasClassFlag(c, CInterface)) "interface" else "class") + " "
					+ stype(TInst(c, extractParamTypes(c.clParams))));
				var ext = (switch c.clSuper {
					case null: [];
					case s: [" extends " + stype(TInst(s.cls, s.params))];
				});
				for (i in c.clImplements)
					ext.unshift((if (hasClassFlag(c, CInterface)) " extends " else " implements ") + stype(TInst(i.cls, i.params)));
				var ext = (switch c.clDynamic {
					case null: ext;
					case t:
						switch c.clPath {
							case {pack: ["flash", "errors"]}: ext;
							case _ if (t == tDynamic): [" implements Dynamic"].concat(ext);
							case _: [" implements Dynamic<" + stype(t) + ">"].concat(ext);
						}
				});
				var ext = (switch c.clPath {
					case {pack: ["flash", "utils"], name: "ByteArray"}: [" implements ArrayAccess<Int>"].concat(ext);
					case {pack: ["flash", "utils"], name: "Dictionary"}: [" implements ArrayAccess<Dynamic>"];
					case {pack: ["flash", "xml"], name: "XML"}: [" implements Dynamic<XMLList>"];
					case {pack: ["flash", "xml"], name: "XMLList"}: [" implements ArrayAccess<XML>"];
					case {pack: ["flash", "display"], name: "MovieClip"}: [" extends Sprite #if !flash_strict implements Dynamic #end"];
					case {pack: ["flash", "errors"], name: "Error"}: [" #if !flash_strict implements Dynamic #end"];
					case _: ext;
				});
				var ext = ext.copy();
				ext.reverse();
				p(ext.join(""));
				p(" {\n");
				function sort(l:Array<TClassField>):Array<TClassField> {
					var a = l.filter(f -> !hasClassFieldFlag(f, CfOverride));
					function name(n:String) return n == "new" ? "" : n;
					haxe.ds.ArraySort.sort(a, function(f1, f2) {
						return switch [f1.cfKind, f2.cfKind] {
							case [Var(_), Var(_)] | [Method(_), Method(_)]: compareString(name(f1.cfName), name(f2.cfName));
							case [Var(_), _]: -1;
							case _: 1;
						}
					});
					return a;
				}
				for (f in sort(switch c.clConstructor {
					case null: c.clOrderedFields;
					case f: [f].concat(c.clOrderedFields);
				}))
					print_field(false, f);
				for (f in sort(c.clOrderedStatics)) print_field(true, f);
				p("}\n");
			case TEnumDecl(e):
				print_meta(e.eMeta);
				p("extern enum " + stype(TEnum(e, extractParamTypes(e.eParams))) + " {\n");
				for (n in e.eNames) {
					var c = core.ds.PMap.find(n, e.eConstrs);
					p("\t" + c.efName);
					switch follow(c.efType) {
						case TFun({args: args}):
							p("(" + args.map(a -> sparam(a.name, if (a.optional) Ident("null") else null, a.type)).join(", ") + ")");
						case _:
					}
					p(";\n");
				}
				p("}\n");
			case TTypeDecl(t):
				print_meta(t.tMeta);
				p("typedef " + stype(TType(t, extractParamTypes(t.tParams))) + " = ");
				p(stype(t.tType));
				p("\n");
			case TAbstractDecl(a):
				print_meta(a.aMeta);
				switch a.aImpl {
					case null:
					case c:
						try print_meta([Meta.get(Meta.Require, c.clMeta)]) catch (_:core.ds.NotFound) {}
				}
				p("extern ");
				var is_enum = a.aEnum;
				if (is_enum) p("enum ");
				p("abstract " + stype(TAbstract(a, extractParamTypes(a.aParams))));
				if (!Meta.has(Meta.CoreType, a.aMeta)) p("(" + stype(a.aThis) + ")");
				p(" {\n");
				switch a.aImpl {
					case null:
					case c:
						var fields = c.clOrderedStatics;
						var fields = if (is_enum) {
							var a = fields.copy();
							haxe.ds.ArraySort.sort(a, (a, b) -> compareString(a.cfName, b.cfName));
							a;
						} else fields;
						for (f in fields) {
							var static_ = !hasClassFieldFlag(f, CfImpl);
							if (!static_ && is_enum && hasClassFieldFlag(f, CfEnum)) {
								p("\tvar " + f.cfName + ";\n");
							} else
								print_field(static_, f);
						}
				}
				p("}\n");
		}
		var file = base_path + "/" + (switch pack {
			case []: "";
			case l: l.join("/") + "/";
		}) + name + ".hx";
		var ch = sys.io.File.write(file, true);
		ch.writeString(buf.toString());
		ch.close();
	}

	public static function generate(com:context.Common.CommonContext):Void {
		for (t in com.types) generate_type(com, t);
	}
}
