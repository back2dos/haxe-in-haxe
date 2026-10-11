package generators;

import haxe.io.Bytes;
import core.Globals;
import core.Globals.*;
import core.Ast;
import core.TType;
import core.TFunctions.*;
import core.Error;
import core.Meta;
import core.Define;
import core.ds.NotFound;
import libs.extlib.IO;
import libs.swflib.Swf;
import libs.swflib.As3hl;

private enum DependencyKind {
	DKInherit;
	DKExpr;
	DKType;
}

private enum FileFormat {
	BJPG;
	BPNG;
	BGIF;
	SWAV;
	SMP3;
}

// port: xml-light's Xml.t, for the SWC catalog.
private enum XmlNode {
	Element(tag:String, attrs:Array<{n:String, v:String}>, children:Array<XmlNode>);
}

// port: IO.No_more_input of the IO.input_string readers below.
private class NoMoreInput extends haxe.Exception {}

// port: IO.input_string with the extlib little-endian readers genswf uses.
private class InputString {
	final data:Bytes;
	var pos:Int;

	public function new(data:Bytes) {
		this.data = data;
		pos = 0;
	}

	public function read_byte():Int {
		if (pos >= data.length) throw new NoMoreInput("No_more_input");
		return data.get(pos++);
	}

	// port: IO.nread raises No_more_input only when nothing is left; it returns
	// a shorter string at the end of the input.
	public function nread(n:Int):Bytes {
		if (n < 0) throw new core.ds.InvalidArgument("IO.nread");
		if (n == 0) return Bytes.alloc(0);
		if (pos >= data.length) throw new NoMoreInput("No_more_input");
		var l = n > data.length - pos ? data.length - pos : n;
		var b = data.sub(pos, l);
		pos += l;
		return b;
	}

	// port: compares as raw bytes (the strings read are only compared with ASCII).
	public function nread_ascii(n:Int):String {
		var b = nread(n);
		var s = new StringBuf();
		for (i in 0...b.length) s.addChar(b.get(i));
		return s.toString();
	}

	public function read_ui16():Int {
		var ch1 = read_byte();
		var ch2 = read_byte();
		return ch1 | (ch2 << 8);
	}

	public function read_i16():Int {
		var ch1 = read_byte();
		var ch2 = read_byte();
		var n = ch1 | (ch2 << 8);
		if (ch2 & 128 != 0) return n - 65536 else return n;
	}

	public function read_i32():Int {
		var ch1 = read_byte();
		var ch2 = read_byte();
		var ch3 = read_byte();
		var ch4 = read_byte();
		// port: the 63-bit read_i32 never overflows; the port's Int is 32-bit.
		return ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
	}
}

class Genswf {
	static function tag(?ext:Bool = false, d:TagData):Tag {
		return {
			tid: 0,
			textended: ext,
			tdata: d,
		};
	}

	static function flash_version_tag(v:Float):Int {
		return switch v {
			case 6.: 6;
			case 7.: 7;
			case 8.: 8;
			case 9.: 9;
			case 10. | 10.1: 10;
			case 10.2: 11;
			case 10.3: 12;
			case 11.: 13;
			case 11.1: 14;
			case 11.2: 15;
			case 11.3: 16;
			case 11.4: 17;
			case 11.5: 18;
			case 11.6: 19;
			case 11.7: 20;
			case 11.8: 21;
			case 11.9: 22;
			case v if (v >= 12.0 && Std.int(v) == v): Std.int(v) + 11;
			case v: throw new core.ds.Failure("Invalid SWF version " + core.Numeric.stringOfFloat(v));
		}
	}

	static function convert_header(com:Gctx, flash_version:Float, h:{width:Int, height:Int, fps:Float, color:Int}):{header:Header, bg:Int} {
		var w = h.width, hh = h.height, fps = h.fps, bg = h.color;
		var high = (if (w > hh) w else hh) * 20;
		function loop(b:Int):Int {
			return if (1 << b > high) b else loop(b + 1);
		}
		var bits = loop(0);
		return {
			header: {
				h_version: flash_version_tag(flash_version),
				h_size: {
					rect_nbits: bits + 1,
					left: 0,
					top: 0,
					right: w * 20,
					bottom: hh * 20,
				},
				h_frame_count: 1,
				h_fps: Swf.to_float16(if (fps > 127.0) 127.0 else fps),
				h_compressed: !Gctx.defined(com, Define.NoSwfCompress),
			},
			bg: bg
		};
	}

	static function default_header(com:Gctx, flash_version:Float):{header:Header, bg:Int} {
		return convert_header(com, flash_version, {width: 400, height: 300, fps: 30., color: 0xFFFFFF});
	}

	static function pathEq(a:GlobalTypePath, b:GlobalTypePath):Bool {
		if (a.name != b.name || a.pack.length != b.pack.length) return false;
		for (i in 0...a.pack.length) if (a.pack[i] != b.pack[i]) return false;
		return true;
	}

	// port: OCaml `compare` on (path * dependency_kind), the PMap key order.
	static function compareDep(a:{p:GlobalTypePath, k:DependencyKind}, b:{p:GlobalTypePath, k:DependencyKind}):Int {
		var cmp = 0;
		var i = 0;
		while (cmp == 0) {
			if (i >= a.p.pack.length || i >= b.p.pack.length) {
				cmp = a.p.pack.length - b.p.pack.length;
				break;
			}
			cmp = compiler.hxb.HxbWriter.compareOcamlString(a.p.pack[i], b.p.pack[i]);
			i++;
		}
		if (cmp != 0) return cmp;
		cmp = compiler.hxb.HxbWriter.compareOcamlString(a.p.name, b.p.name);
		if (cmp != 0) return cmp;
		return Type.enumIndex(a.k) - Type.enumIndex(b.k);
	}

	static function build_dependencies(t:ModuleType):Array<{p:GlobalTypePath, k:DependencyKind}> {
		var h:Array<{p:GlobalTypePath, k:DependencyKind}> = [];
		function add_path(p:GlobalTypePath, k:DependencyKind) {
			for (x in h) if (compareDep(x, {p: p, k: k}) == 0) return;
			h.push({p: p, k: k});
		}
		function add_type_rec(l:Array<T>, t:T) {
			for (x in l) if (x == t) return;
			var tl = [t].concat(l);
			switch t {
				case TEnum(e, pl):
					add_path(e.ePath, DKType);
					for (t in pl) add_type_rec(tl, t);
				case TInst(c, pl):
					switch c.clKind {
						case KTypeParameter(_):
						case _: add_path(c.clPath, DKType);
					}
					for (t in pl) add_type_rec(tl, t);
				case TAbstract(a, pl):
					if (!pathEq(a.aPath, {pack: [], name: "Null"}) && Meta.has(Meta.CoreType, a.aMeta)) add_path(a.aPath, DKType);
					for (t in pl) add_type_rec(tl, t);
				case TFun(s):
					for (a in s.args) add_type_rec(tl, a.type);
					add_type_rec(tl, s.ret);
				case TAnon(a):
					for (k in compiler.hxb.HxbWriter.sortedKeys(a.aFields)) add_type_rec(tl, a.aFields.get(k).cfType);
				case TDynamic(t2):
					add_type_rec(tl, (switch t2 {
						case null: tDynamic;
						case t2: t2;
					}));
				case TLazy(f):
					add_type_rec(l, lazyType(f));
				case TMono(r):
					switch r.tmType {
						case null:
						case t: add_type_rec(l, t);
					}
				case TType(tt, pl):
					add_type_rec(tl, tt.tType);
					for (t in pl) add_type_rec(tl, t);
			}
		}
		function add_type(t:T) add_type_rec([], t);
		function add_expr(e:TExpr) {
			switch e.eexpr {
				case TTypeExpr(t): add_path(tPath(t), DKExpr);
				case TNew(c, pl, el):
					add_path(c.clPath, DKExpr);
					for (t in pl) add_type(t);
					for (e in el) add_expr(e);
				case TFunction(f):
					for (a in f.tfArgs) add_type(a.variable.vType);
					add_type(f.tfType);
					add_expr(f.tfExpr);
				case TVar(v, eo):
					add_type(v.vType);
					switch eo {
						case null:
						case e: add_expr(e);
					}
				case TArray({eexpr: TIdent("__global__")}, {eexpr: TConst(TString(s))}):
					var path = Ast.parsePath(s);
					add_path({pack: path.pack, name: path.name}, DKExpr);
				case _:
					core.Texpr.iter(add_expr, e);
			}
		}
		function add_field(f:TClassField) {
			add_type(f.cfType);
			switch f.cfExpr {
				case null:
				case e: add_expr(e);
			}
		}
		function add_inherit(c:TClass, pl:TParams) {
			add_path(c.clPath, DKInherit);
			for (t in pl) add_type(t);
		}
		switch t {
			case TClassDecl(c) if (!hasClassFlag(c, CExtern)):
				for (f in c.clOrderedFields) add_field(f);
				for (f in c.clOrderedStatics) add_field(f);
				switch c.clConstructor {
					case null:
					case f:
						add_field(f);
						if (!pathEq(c.clPath, {pack: ["flash"], name: "Boot"})) add_path({pack: ["flash"], name: "Boot"}, DKExpr);
				}
				switch core.TOther.TClassTools.getClInit(c) {
					case null:
					case e: add_expr(e);
				}
				switch c.clSuper {
					case null: add_path({pack: [], name: "Object"}, DKInherit);
					case x: add_inherit(x.cls, x.params);
				}
				for (tp in c.clParams) {
					/* add type-parameters constraints dependencies */
					for (i in tp.ttpClass.clImplements) add_inherit(i.cls, i.params);
				}
				for (i in c.clImplements) add_inherit(i.cls, i.params);
			case TEnumDecl(e) if (!hasEnumFlag(e, EnExtern)):
				for (k in compiler.hxb.HxbWriter.sortedKeys(e.eConstrs)) add_type(e.eConstrs.get(k).efType);
			case _:
		}
		h = h.filter(x -> !(pathEq(x.p, {pack: [], name: "Int"}) && x.k.match(DKType)));
		h = h.filter(x -> !(pathEq(x.p, {pack: [], name: "Int"}) && x.k.match(DKExpr)));
		h = h.filter(x -> !(pathEq(x.p, {pack: [], name: "Void"}) && x.k.match(DKType)));
		// port: PMap.foldi prepends in ascending key order: the result is descending.
		haxe.ds.ArraySort.sort(h, (a, b) -> compareDep(b, a));
		return h;
	}

	static function build_swc_catalog(com:Gctx, types:Array<ModuleType>):String {
		function node(x:String, att:Array<{n:String, v:String}>, l:Array<XmlNode>) {
			return Element(x, att, l);
		}
		function make_path(t:ModuleType, sep:String) {
			var p = tPath(t);
			return p.pack.concat([p.name]).join(sep);
		}
		function make_id(path:GlobalTypePath) {
			return switch Genswf9.real_path(path) {
				case {pack: [], name: n}: n;
				case {pack: l, name: n}: l.join(".") + ":" + n;
			}
		}
		function build_script(t:ModuleType) {
			var deps = build_dependencies(t);
			return node("script", [{n: "name", v: make_path(t, "/")}, {n: "mod", v: "0"}], [
				node("def", [{n: "id", v: make_id(tPath(t))}], []),
				node("dep", [{n: "id", v: "AS3"}, {n: "type", v: "n"}], []),
			].concat([
				for (d in deps) {
					var p = d.p, k = d.k;
					var t = (switch k {
						case DKInherit: "i";
						case DKExpr: (switch p {
								case {pack: pack} if (pack.length >= 2 && pack[0] == "flash"): "i";
								case _: "e";
							});
						case DKType: "s";
					});
					node("dep", [{n: "id", v: make_id(p)}, {n: "type", v: t}], []);
				}
			]));
		}
		var x = node("swc", [{n: "xmlns", v: "http://www.adobe.com/flash/swccatalog/9"}], [
			node("versions", [], [
				node("swc", [{n: "version", v: "1.2"}], []),
				node("haxe", [{n: "version", v: Std.int(com.version.version / 10000) + "." + StringTools.lpad(Std.string(com.version.version % 10000), "0", 2)}], []),
			]),
			node("features", [], [node("feature-script-deps", [], []), node("feature-files", [], []),]),
			node("libraries", [], [node("library", [{n: "path", v: "library.swf"}], [for (t in types) build_script(t)])]),
			node("files", [], []),
		]);
		return "<?xml version=\"1.0\" encoding =\"utf-8\"?>\n" + xml_to_string_fmt(x);
	}

	// port: xml-light's Xml.to_string_fmt (only elements occur in the catalog).
	static function xml_to_string_fmt(x:XmlNode):String {
		var tmp = new StringBuf();
		function buffer_attr(a:{n:String, v:String}) {
			tmp.add(" ");
			tmp.add(a.n);
			tmp.add("=\"");
			for (i in 0...a.v.length) {
				switch a.v.charAt(i) {
					case "\\": tmp.add("\\\\");
					case "\"": tmp.add("\\\"");
					case c: tmp.add(c);
				}
			}
			tmp.add("\"");
		}
		function loop(newl:Bool, tab:String, x:XmlNode) {
			switch x {
				case Element(tag, alist, []):
					tmp.add(tab);
					tmp.add("<");
					tmp.add(tag);
					for (a in alist) buffer_attr(a);
					tmp.add("/>");
					if (newl) tmp.add("\n");
				case Element(tag, alist, l):
					tmp.add(tab);
					tmp.add("<");
					tmp.add(tag);
					for (a in alist) buffer_attr(a);
					tmp.add(">\n");
					for (x in l) loop(true, tab + "  ", x);
					tmp.add(tab);
					tmp.add("</");
					tmp.add(tag);
					tmp.add(">");
					if (newl) tmp.add("\n");
			}
		}
		loop(false, "", x);
		return tmp.toString();
	}

	static function detect_format(data:Bytes, p:Pos):FileFormat {
		var c0 = 0, c1 = 0, c2 = 0;
		if (data.length >= 3) {
			c0 = data.get(0);
			c1 = data.get(1);
			c2 = data.get(2);
		}
		return switch [c0, c1, c2] {
			case [0xFF, 0xD8, _]: BJPG;
			case [0x89, "P".code, "N".code]: BPNG;
			case ["R".code, "I".code, "F".code]: SWAV;
			case ["I".code, "D".code, "3".code]: SMP3;
			case [0xFF, i, _] if (i & 0xE2 == 0xE2): SMP3;
			case ["G".code, "I".code, "F".code]: BGIF;
			case _:
				Error.abort("Unknown file format", p);
		}
	}

	static function build_swf9(com:Gctx, file:String, swc:Null<{cat:String}>):Array<Tag> {
		var boot_name = if (swc != null || Gctx.defined(com, Define.HaxeBoot)) "haxe" else "boot_"
			+ haxe.crypto.Md5.make(Bytes.ofString(haxe.io.Path.withoutDirectory(file))).toHex().substr(0, 4);
		var code = Genswf9.generate(com, boot_name);
		var code = (switch swc {
			case null:
				var inits:HlTag = [
					for (c in code)
						{
							hls_method: c.m,
							hls_fields: [c.f],
						}
				];
				[tag(TActionScript3({id: 1, frame: boot_name}, libs.swflib.As3hlparse.flatten(inits)))];
			case cat:
				cat.cat = build_swc_catalog(com, [for (c in code) c.t]);
				[
					for (c in code) {
						var path = (switch tPath(c.t) {
							case {pack: [], name: name}: name;
							case {pack: path, name: name}: path.join("/") + "/" + name;
						});
						var init:HlStatic = {
							hls_method: c.m,
							hls_fields: [c.f],
						};
						tag(TActionScript3({id: 1, frame: path}, libs.swflib.As3hlparse.flatten([init])));
					}
				];
		});
		var cid = 0;
		var classes:Array<F9Class> = [{f9_cid: null, f9_classname: boot_name}]; // port: most recent first
		// port: Hashtbl.fold over com.resources, prepending.
		var res:Array<Tag> = [];
		for (name in Genswf9.resource_names(com)) {
			var data = com.resources.find(name);
			cid++;
			classes.unshift({f9_cid: cid, f9_classname: sTypePath(Genswf9.resource_path(name))});
			res.unshift(tag(TBinaryData(cid, data)));
		}
		function load_file_data(file:String, p:Pos):Bytes {
			var file = try Gctx.findFile(com, file) catch (_:NotFound) file;
			if (file.length > 5 && file.substr(0, 5) == "data:")
				return Bytes.ofString(file.substr(5, file.length - 5))
			else {
				// port: Std.input_file; the 16MB limit of 32-bit OCaml strings does not apply.
				return try sys.io.File.getBytes(file) catch (_:Dynamic) Error.abort("File not found", p);
			}
		}
		var bmp:Array<Tag> = [];
		for (t in com.types) {
			switch t {
				case TClassDecl(c):
					function loop(i:Int):Array<Tag> {
						if (i >= c.clMeta.length) return bmp;
						var m = c.clMeta[i];
						if (Meta.metaEq(Meta.Bitmap, m.meta)) switch m.exprs {
							case [{expr: EConst(String(file, _)), pos: p}]:
								var data = load_file_data(file, p);
								cid++;
								classes.unshift({f9_cid: cid, f9_classname: sTypePath(c.clPath)});
								function raw() {
									return tag(TBitsJPEG2({
										bd_id: cid,
										bd_data: data,
										bd_table: null,
										bd_alpha: null,
										bd_deblock: 0
									}));
								}
								var t = (switch detect_format(data, p) {
									case BPNG:
										/*
											There is a bug in Flash PNG decoder for 24-bits PNGs : Color such has 0xFF00FF is decoded as 0xFE00FE.
											In that particular case, we will then embed the decoded PNG bytes instead.
										*/
										// port: png.ml and zlib inflate (Extc.unzip) are not ported.
										throw new core.ds.Failure("haxe-in-haxe: PNG bitmaps (@:bitmap) are not supported: png.ml is not ported");
									case _: raw();
								});
								var rest = loop(i + 1);
								return [t].concat(rest);
							case [{expr: EConst(String(dfile, _)), pos: p1}, {expr: EConst(String(afile, _)), pos: p2}]:
								var ddata = load_file_data(dfile, p1);
								var adata = load_file_data(afile, p2);
								switch detect_format(ddata, p1) {
									case BJPG:
									case _: Error.abort("RGB channel must be a JPG file", p1);
								}
								switch detect_format(adata, p2) {
									case BPNG:
									case _: Error.abort("Alpha channel must be a PNG file", p2);
								}
								// port: png.ml and zlib inflate (Extc.unzip) are not ported.
								throw new core.ds.Failure("haxe-in-haxe: PNG alpha channels (@:bitmap) are not supported: png.ml is not ported");
							case _:
						}
						if (Meta.metaEq(Meta.File, m.meta)) switch m.exprs {
							case [{expr: EConst(String(file, _)), pos: p}]:
								var data = load_file_data(file, p);
								cid++;
								classes.unshift({f9_cid: cid, f9_classname: sTypePath(c.clPath)});
								// port: `tag (...) :: loop l` evaluates `loop l` first, so the
								// tag reads cid after the following metadata.
								var rest = loop(i + 1);
								return [tag(TBinaryData(cid, data))].concat(rest);
							case _:
						}
						if (Meta.metaEq(Meta.Sound, m.meta)) switch m.exprs {
							case [{expr: EConst(String(file, _)), pos: p}]:
								var data = load_file_data(file, p);
								function make_flags(fmt:Int, mono:Bool, freq:Int, bits:Int) {
									var fbits = (switch freq {
										case 5512 if (fmt != 2): 0;
										case 11025: 1;
										case 22050: 2;
										case 44100: 3;
										case _: throw new core.ds.Failure("Unsupported frequency " + Std.string(freq));
									});
									var bbits = (switch bits {
										case 8: 0;
										case 16: 1;
										case _: throw new core.ds.Failure("Unsupported bits " + Std.string(bits));
									});
									return (fmt << 4) | (fbits << 2) | (bbits << 1) | (if (mono) 0 else 1);
								}
								var r = (switch detect_format(data, p) {
									case SWAV:
										try {
											var i = new InputString(data);
											if (i.nread_ascii(4) != "RIFF") throw core.ds.Exit.raise();
											i.nread(4); /* size */
											if (i.nread_ascii(4) != "WAVE" || i.nread_ascii(4) != "fmt ") throw core.ds.Exit.raise();
											var chunk_size = i.read_i32();
											if (!(chunk_size == 0x10 || chunk_size == 0x12 || chunk_size == 0x40)) throw new core.ds.Failure("Unsupported chunk size "
												+ Std.string(chunk_size));
											if (i.read_ui16() != 1) throw new core.ds.Failure("Not a PCM file");
											var chan = i.read_ui16();
											if (chan > 2) throw new core.ds.Failure("Too many channels");
											var freq = i.read_i32();
											i.read_i32();
											i.read_i16();
											var bits = i.read_ui16();
											if (chunk_size != 0x10) i.nread(chunk_size - 0x10);
											if (i.nread_ascii(4) != "data") throw core.ds.Exit.raise();
											var data_size = i.read_i32();
											var data = i.nread(data_size);
											{flags: make_flags(0, (chan == 1), freq, bits), samples: (Std.int(data_size * 8 / (chan * bits))), data: data};
										} catch (_:core.ds.Exit) {
											Error.abort("Invalid WAV file", p);
										} catch (_:NoMoreInput) {
											Error.abort("Invalid WAV file", p);
										} catch (e:core.ds.Failure) {
											Error.abort("Invalid WAV file (" + e.message + ")", p);
										}
									case SMP3:
										try {
											var sampling = 0;
											var mono = false;
											var samples = 0;
											var i = new InputString(data);
											function read_frame() {
												switch (try i.read_byte() catch (_:NoMoreInput) -1) {
													case -1:
													case 0x49:
														/* ID3 */
														if (i.nread_ascii(2) != "D3") throw core.ds.Exit.raise();
														i.read_ui16(); /* version */
														i.read_byte(); /* flags */
														var size = i.read_byte() & 0x7F;
														var size = (size << 7) | (i.read_byte() & 0x7F);
														var size = (size << 7) | (i.read_byte() & 0x7F);
														var size = (size << 7) | (i.read_byte() & 0x7F);
														i.nread(size); /* id3 data */
														read_frame();
													case 0x54:
														/* TAG and TAG+ */
														if (i.nread_ascii(3) == "AG+") i.nread(223) else i.nread(124);
														read_frame();
													case 0xFF:
														var infos = i.read_byte();
														var ver = (infos >> 3) & 3;
														sampling = [11025, 0, 22050, 44100][ver];
														var layer = (infos >> 1) & 3;
														var bits = i.read_byte();
														var bitrate = (if (ver == 3) [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1] else [
															0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1
														])[bits >> 4];
														var srate = [
															[11025, 12000, 8000, -1],
															[-1, -1, -1, -1],
															[22050, 24000, 16000, -1],
															[44100, 48000, 32000, -1],
														][ver][(bits >> 2) & 3];
														var pad = (bits >> 1) & 1;
														mono = (i.read_byte()) >> 6 == 3;
														var bpp = (if (ver == 3) 144 else 72);
														// port: OCaml integer division truncates toward zero.
														var size = (Std.int((bpp * bitrate * 1000) / srate)) + pad - 4;
														i.nread(size);
														samples = samples + (if (layer == 3) 384 else 1152);
														read_frame();
													case _:
														throw core.ds.Exit.raise();
												}
											}
											read_frame();
											var d = Bytes.alloc(data.length + 2);
											d.fill(0, 2, 0);
											d.blit(2, data, 0, data.length);
											{flags: make_flags(2, mono, sampling, 16), samples: (samples), data: d};
										} catch (_:core.ds.Exit) {
											Error.abort("Invalid MP3 file", p);
										} catch (_:NoMoreInput) {
											Error.abort("Invalid MP3 file", p);
										} catch (e:core.ds.Failure) {
											Error.abort("Invalid MP3 file (" + e.message + ")", p);
										}
									case _:
										Error.abort("Sound extension not supported (only WAV or MP3)", p);
								});
								cid++;
								classes.unshift({f9_cid: cid, f9_classname: sTypePath(c.clPath)});
								// port: `tag (...) :: loop l` evaluates `loop l` first, so the
								// tag reads cid after the following metadata.
								var rest = loop(i + 1);
								return [
									tag(TSound({
										so_id: cid,
										so_flags: r.flags,
										so_samples: r.samples,
										so_data: r.data
									}))
								].concat(rest);
							case _:
						}
						return loop(i + 1);
					}
					bmp = loop(0);
				case _:
			}
		}
		var cl = classes.copy();
		cl.reverse();
		var clips = [tag(TF9Classes(cl))];
		return res.concat(bmp).concat(code).concat(clips);
	}

	public static function generate(swf_header:Null<{width:Int, height:Int, fps:Float, color:Int}>, swf_libs:Array<Dynamic>, flash_version:Float, com:Gctx):Void {
		var swc:Null<{cat:String}> = if (Gctx.defined(com, Define.Swc)) {cat: ""} else null;
		var file = (switch com.file.indexOf("@") {
			case -1: com.file;
			case i: com.file.substr(0, i);
		});
		/* list exports */
		// port: SWF library input (SwfLoader) is not ported; --swf-lib is rejected
		// when the library is added, so swf_libs is always empty here.
		if (swf_libs.length != 0) throw new core.ds.Failure("haxe-in-haxe: SWF library input (--swf-lib) is not supported");
		/* build haxe swf */
		var tags = build_swf9(com, file, swc);
		var hb = (switch swf_header {
			case null: default_header(com, flash_version);
			case h: convert_header(com, flash_version, h);
		});
		var header = hb.header, bg = hb.bg;
		var bg = tag(TSetBgColor({cr: bg >> 16, cg: (bg >> 8) & 0xFF, cb: bg & 0xFF}));
		var scene = tag(true, TScenes([{n: 0, s: "Scene1"}], []));
		var swf_debug_password = try haxe.crypto.Md5.make(Bytes.ofString(Gctx.definedValue(com, Define.SwfDebugPassword))).toHex() catch (_:NotFound) "";
		var debug = (if (Gctx.defined(com, Define.Fdb)) [tag(TEnableDebugger2(0, swf_debug_password))] else []);
		var meta_data = try {
			var file = Gctx.definedValue(com, Define.SwfMetadata);
			var file = try Gctx.findFile(com, file) catch (_:NotFound) file;
			var data = try sys.io.File.getBytes(file) catch (_:Dynamic) throw new core.ds.Failure("Metadata resource file not found : " + file);
			[tag(TMetaData(data))];
		} catch (_:NotFound) {
			[];
		}
		var fattr = (if (flash_version < 8.) [] else [
			tag(TFilesAttributes({
				fa_network: Gctx.defined(com, Define.NetworkSandbox),
				fa_as3: true,
				fa_metadata: meta_data.length != 0,
				fa_gpu: flash_version > 9. && Gctx.defined(com, Define.SwfGpu),
				fa_direct_blt: flash_version > 9. && Gctx.defined(com, Define.SwfDirectBlit),
			}))
		]);
		var fattr = if (Gctx.defined(com, Define.AdvancedTelemetry)) {
			var b = Bytes.alloc(2);
			b.fill(0, 2, 0);
			fattr.concat([tag(TUnknown(0x5D, b))]);
		} else fattr;
		var swf_script_limits = try {
			var s = Gctx.definedValue(com, Define.SwfScriptTimeout);
			var i = try core.ds.OcamlInt.ofString(s) catch (_:Dynamic) Error.abort("Argument to swf_script_timeout must be an integer", nullPos);
			[tag(TScriptLimits(256, if (i < 0) 0 else if (i > 65535) 65535 else i))];
		} catch (_:NotFound) {
			[];
		}
		var swf:SwfData = {
			header: header,
			tags: fattr.concat(meta_data).concat([bg, scene]).concat(debug).concat(swf_script_limits).concat(tags).concat([tag(TShowFrame)])
		};
		/* merge swf libraries */
		var swf = switch swf {
			case {header: header, tags: tags} if (Gctx.defined(com, Define.SwfPreloaderFrame)):
				function loop(l:Array<Tag>, i:Int):Array<Tag> {
					if (i >= l.length) return [];
					var t = l[i];
					return switch t.tdata {
						case TFilesAttributes(_) | TMetaData(_) | TSetBgColor(_) | TEnableDebugger2(_) | TScriptLimits(_): [t].concat(loop(l, i + 1));
						case TUnknown(0x5D, d) if (d.length == 2 && d.get(0) == 0 && d.get(1) == 0): [t].concat(loop(l, i + 1));
						case _: [tag(TShowFrame), t].concat(l.slice(i + 1));
					}
				}
				({
					header: {
						h_version: header.h_version,
						h_size: header.h_size,
						h_fps: header.h_fps,
						h_frame_count: header.h_frame_count + 1,
						h_compressed: header.h_compressed
					},
					tags: loop(tags, 0)
				} : SwfData);
			case _: swf;
		}
		/* write swf/swc */
		var stop = core.Timer.startTimer(com.timerCtx, ["write", "swf"]);
		try {
			var level = (try core.ds.OcamlInt.ofString(Gctx.definedValue(com, Define.SwfCompressLevel)) catch (_:NotFound) 9);
			libs.swflib.SwfParser.init(ch -> libs.extc.Extc.outputZip(65536, level, ch));
			switch swc {
				case null:
					var ch = IO.outputChannel(sys.io.File.write(file, true));
					Swf.write(ch, swf);
					IO.closeOut(ch);
				case cat:
					var buf = new haxe.io.BytesBuffer();
					var ch = IO.outputBytes(buf);
					Swf.write(ch, swf);
					IO.closeOut(ch);
					var swf = buf.getBytes();
					var z = libs.ziplib.Zip.open_out(file);
					libs.ziplib.Zip.add_entry(Bytes.ofString(cat.cat), z, "catalog.xml");
					libs.ziplib.Zip.add_entry(swf, z, "library.swf", "", "", 0);
					libs.ziplib.Zip.close_out(z);
			}
		} catch (e:Dynamic) {
			stop();
			throw e;
		}
		stop();
	}
}
