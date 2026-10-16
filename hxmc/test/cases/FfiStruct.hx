import hxmc.unsafe.*;

// C structs by value in calls (AAPCS64, arm64 only for now): homogeneous
// float and double aggregates (nested too), small integer structs in one
// or two registers, larger ones by address, results in registers or
// through x8, structs that no longer fit in registers on the stack, and an
// indirect call (FfiStruct.c, built by the corpus harness with zig).
@:hxmc.struct @:publicFields class Color {
	var r:Float;
	var g:Float;
	var b:Float;
	var a:Float;
}

@:hxmc.struct @:publicFields class Pt {
	var x:Float;
	var y:Float;
}

@:hxmc.struct @:publicFields class Box {
	var origin:Pt;
	var size:Pt;
}

@:hxmc.struct @:publicFields class F3 {
	var x:Float32;
	var y:Float32;
	var z:Float32;
}

@:hxmc.struct @:publicFields class One {
	var d:Float;
}

@:hxmc.struct @:publicFields class Size3 {
	var w:Int64;
	var h:Int64;
	var d:Int64;
}

@:hxmc.struct @:publicFields class View {
	var x:Float;
	var y:Float;
	var w:Float;
	var h:Float;
	var zn:Float;
	var zf:Float;
}

@:hxmc.struct @:publicFields class Small {
	var a:Int32;
	var b:Int8;
}

@:hxmc.struct @:publicFields class Mid {
	var a:Int64;
	var b:Int32;
}

@:hxmc.struct @:publicFields class Tiny {
	var a:UInt8;
	var b:UInt8;
	var c:UInt8;
}

@:hxmc.struct @:publicFields class Mixed {
	var a:Int32;
	var f:Float32;
}

@:hxmc.c @:hxmc.fast extern class S {
	static function s_color_sum(c:Color):Float;
	static function s_color(r:Float, g:Float, b:Float, a:Float):Color;
	static function s_box(x:Float, y:Float, w:Float, h:Float):Box;
	static function s_box_area(self:Ptr, sel:Ptr, b:Box):Float;
	static function s_f3_scale(v:F3, k:Float32):F3;
	static function s_one(o:One):One;
	static function s_size3(w:Int64, h:Int64, d:Int64):Size3;
	static function s_size3_vol(s:Size3, k:Int):Int64;
	static function s_view(v:View):View;
	static function s_small(s:Small):Small;
	static function s_mid(m:Mid, k:Int):Mid;
	static function s_tiny(t:Tiny):Tiny;
	static function s_mixed(m:Mixed):Mixed;
	static function s_spill_int(a:Int, b:Int, c:Int, d:Int, e:Int, f:Int, g:Int, m:Mid, z:Int):Int64;
	static function s_spill_hfa(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float, g:Float, k:Color, z:Float):Float;
	static function s_spill_f3(a:Float32, b:Float32, c:Float32, d:Float32, e:Float32, f:Float32, g:Float32, h:Float32, v:F3, z:Float32, w:F3):Float32;
	static function s_fnptr():Ptr;
	@:hxmc.indirect static function boxArea(fn:Ptr, self:Ptr, sel:Ptr, b:Box):Float;
}

// (in a safe region: the result's registers outlive rt_blocking_leave)
@:hxmc.c extern class Slow {
	@:native("s_box_slow") static function box(x:Float, y:Float, w:Float, h:Float):Box;
	@:native("s_size3_slow") static function size3(w:Int64, h:Int64, d:Int64):Size3;
}

class FfiStruct {
	static function main() {
		Arena.scoped(a -> {
			var c = a.make(Color);
			c.value.r = 1;
			c.value.g = 2;
			c.value.b = 3;
			c.value.a = 4;
			trace(S.s_color_sum(c.value));
			var k = S.s_color(0.5, 0.25, 0.125, 1);
			trace(k.r, k.g, k.b, k.a, S.s_color_sum(k));
			var b = S.s_box(1, 2, 4, 6);
			trace(b.origin.x, b.origin.y, b.size.x, b.size.y, S.s_box_area(Ptr.nil(), Ptr.nil(), b));
			var s = Slow.box(10, 20, 30, 40);
			var s3 = Slow.size3(6, 7, 8);
			trace(s.size.y, b.size.y, haxe.Int64.toStr(s3.h));
			var v = a.make(F3);
			v.value.x = 1.5;
			v.value.y = -2;
			v.value.z = 0.25;
			var r = S.s_f3_scale(v.value, 2);
			trace(r.x, r.y, r.z);
			var o = a.make(One);
			o.value.d = 1.25;
			trace(S.s_one(o.value).d);
			var z = S.s_size3(3, 4, 5);
			trace(haxe.Int64.toStr(z.w), haxe.Int64.toStr(z.d), haxe.Int64.toStr(S.s_size3_vol(z, 7)));
			var w = a.make(View);
			w.value.x = 1;
			w.value.y = 2;
			w.value.w = 3;
			w.value.h = 4;
			w.value.zn = 5;
			w.value.zf = 6;
			var u = S.s_view(w.value);
			trace(u.x, u.y, u.w, u.h, u.zn, u.zf, w.value.x);
			var m = a.make(Small);
			m.value.a = 21;
			m.value.b = -128;
			var mr = S.s_small(m.value);
			trace(mr.a, mr.b);
			var d = a.make(Mid);
			d.value.a = 1 << 30;
			d.value.b = 9;
			var dr = S.s_mid(d.value, 5);
			trace(haxe.Int64.toStr(dr.a), dr.b);
			var t = a.make(Tiny);
			t.value.a = 1;
			t.value.b = 2;
			t.value.c = 250;
			var tr = S.s_tiny(t.value);
			trace(tr.a, tr.b, tr.c);
			var x = a.make(Mixed);
			x.value.a = -3;
			x.value.f = 0.75;
			var xr = S.s_mixed(x.value);
			trace(xr.a, xr.f);
			trace(haxe.Int64.toStr(S.s_spill_int(1, 2, 3, 4, 5, 6, 7, d.value, 11)));
			trace(S.s_spill_hfa(1, 2, 3, 4, 5, 6, 7, c.value, 8));
			trace(S.s_spill_f3(1, 2, 3, 4, 5, 6, 7, 8, v.value, 4, v.value));
			trace(S.boxArea(S.s_fnptr(), Ptr.nil(), Ptr.nil().add(1), S.s_box(0, 0, 3, 3)));
			// a result in a loop: one slot per call, the same each iteration
			var sum = 0.0;
			for (i in 0...3)
				sum += S.s_color(i, 0, 0, 0).r;
			trace(sum);
		});
	}
}
