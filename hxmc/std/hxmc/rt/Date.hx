package hxmc.rt;

import hxmc.I64;
import hxmc.rt.C;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The Date natives and Math.random (formerly in rt_std.c). A Date is a
// T_NATIVE K_RAW object holding the milliseconds since the epoch (a
// double); calendar fields come from the C library (mktime, localtime_r,
// gmtime_r; the UCRT's _mktime64, _localtime64_s, _gmtime64_s on Windows),
// whose struct tm starts with nine ints on every target.
@:keep
class Date {
	static inline var T_NATIVE = 16;
	static inline var K_RAW = 2;
	// struct tm's int fields
	static inline var SEC = 0;
	static inline var MIN = 4;
	static inline var HOUR = 8;
	static inline var MDAY = 12;
	static inline var MON = 16;
	static inline var YEAR = 20;
	static inline var WDAY = 24;
	static inline var ISDST = 32;

	static inline function windows():Bool
		return Mem.os() == 2;

	static function of(ms:Float):Dynamic {
		var d = Mem.allocRaw(1, T_NATIVE, K_RAW);
		Mem.setF64(Mem.addr(d), 0, ms);
		return d;
	}

	static inline function ms(d:Dynamic):Float
		return Mem.getF64(Mem.addr(d), 0);

	@:hxmc.noGc static function mktime(tm:Ptr):I64
		return windows() ? LibC._mktime64(tm) : LibC.mktime(tm);

	// the broken-down time of `ms` into tm (local or UTC)
	@:hxmc.noGc static function breakDown(ms:Float, utc:Bool, tm:Ptr) {
		var t = Mem.stack(8);
		var s:I64 = cast Math.ffloor(ms / 1000.0);
		Mem.setI64(t, 0, s);
		if (windows()) {
			if (utc) LibC._gmtime64_s(tm, t) else LibC._localtime64_s(tm, t);
		} else {
			if (utc) LibC.gmtime_r(t, tm) else LibC.localtime_r(t, tm);
		}
	}

	@:hxmc.host("Date_new") static function make(y:Int, m:Int, d:Int, h:Int, mi:Int, s:Int):Dynamic {
		var tm = Mem.stack(64);
		LibC.memset(tm, 0, 64);
		Mem.setI32(tm, YEAR, y - 1900);
		Mem.setI32(tm, MON, m);
		Mem.setI32(tm, MDAY, d);
		Mem.setI32(tm, HOUR, h);
		Mem.setI32(tm, MIN, mi);
		Mem.setI32(tm, SEC, s);
		Mem.setI32(tm, ISDST, -1);
		var t:Float = cast mktime(tm);
		return of(t * 1000.0);
	}

	@:hxmc.host("Date_now") static function now():Dynamic {
		var ts = Mem.stack(16);
		LibC.clock_gettime(0, ts); // CLOCK_REALTIME
		var sec:Float = cast Mem.getI64(ts, 0);
		var nsec:Float = Mem.getI32(ts, 8);
		return of(sec * 1000.0 + nsec / 1e6);
	}

	@:hxmc.host("Date_fromTime") static function fromTime(t:Float):Dynamic
		return of(t);

	// HxOverrides.strDate: "hh:mm:ss" (UTC time of day), "YYYY-MM-DD",
	// "YYYY-MM-DD hh:mm:ss" (local)
	@:hxmc.host("Date_fromString") static function fromString(s:String):Dynamic {
		var n = Str.len(s);
		var f = [0, 0, 0, 0, 0, 0];
		inline function digitsAt(pos:Int, count:Int, k:Int):Bool {
			var v = 0;
			var ok = true;
			for (i in pos...pos + count) {
				var c = Str.unit(s, i);
				if (c < 48 || c > 57) ok = false else v = v * 10 + c - 48;
			}
			f[k] = v;
			return ok;
		}
		inline function sep(pos:Int, c:Int):Bool
			return Str.unit(s, pos) == c;
		if (n == 8 && digitsAt(0, 2, 3) && sep(2, ":".code) && digitsAt(3, 2, 4) && sep(5, ":".code) && digitsAt(6, 2, 5))
			return of((f[3] * 3600.0 + f[4] * 60 + f[5]) * 1000.0);
		if (n == 10 && digitsAt(0, 4, 0) && sep(4, "-".code) && digitsAt(5, 2, 1) && sep(7, "-".code) && digitsAt(8, 2, 2))
			return make(f[0], f[1] - 1, f[2], 0, 0, 0);
		if (n == 19 && digitsAt(0, 4, 0) && sep(4, "-".code) && digitsAt(5, 2, 1) && sep(7, "-".code) && digitsAt(8, 2, 2) && sep(10, " ".code)
			&& digitsAt(11, 2, 3) && sep(13, ":".code) && digitsAt(14, 2, 4) && sep(16, ":".code) && digitsAt(17, 2, 5))
			return make(f[0], f[1] - 1, f[2], f[3], f[4], f[5]);
		Rt.rt_throw(Str.concat("Invalid date format : ", n > 60 ? Str.substr(s, 0, 60) : s));
		return null;
	}

	@:hxmc.host("Date_getTime") @:hxmc.noGc static function getTime(d:Dynamic):Float
		return ms(d);

	@:hxmc.noGc static function field(d:Dynamic, utc:Bool, off:Int):Int {
		var tm = Mem.stack(64);
		breakDown(ms(d), utc, tm);
		return Mem.getI32(tm, off);
	}

	@:hxmc.host("Date_getFullYear") @:hxmc.noGc static function getFullYear(d:Dynamic):Int
		return field(d, false, YEAR) + 1900;

	@:hxmc.host("Date_getMonth") @:hxmc.noGc static function getMonth(d:Dynamic):Int
		return field(d, false, MON);

	@:hxmc.host("Date_getDate") @:hxmc.noGc static function getDate(d:Dynamic):Int
		return field(d, false, MDAY);

	@:hxmc.host("Date_getDay") @:hxmc.noGc static function getDay(d:Dynamic):Int
		return field(d, false, WDAY);

	@:hxmc.host("Date_getHours") @:hxmc.noGc static function getHours(d:Dynamic):Int
		return field(d, false, HOUR);

	@:hxmc.host("Date_getMinutes") @:hxmc.noGc static function getMinutes(d:Dynamic):Int
		return field(d, false, MIN);

	@:hxmc.host("Date_getSeconds") @:hxmc.noGc static function getSeconds(d:Dynamic):Int
		return field(d, false, SEC);

	@:hxmc.host("Date_getUTCFullYear") @:hxmc.noGc static function getUTCFullYear(d:Dynamic):Int
		return field(d, true, YEAR) + 1900;

	@:hxmc.host("Date_getUTCMonth") @:hxmc.noGc static function getUTCMonth(d:Dynamic):Int
		return field(d, true, MON);

	@:hxmc.host("Date_getUTCDate") @:hxmc.noGc static function getUTCDate(d:Dynamic):Int
		return field(d, true, MDAY);

	@:hxmc.host("Date_getUTCDay") @:hxmc.noGc static function getUTCDay(d:Dynamic):Int
		return field(d, true, WDAY);

	@:hxmc.host("Date_getUTCHours") @:hxmc.noGc static function getUTCHours(d:Dynamic):Int
		return field(d, true, HOUR);

	@:hxmc.host("Date_getUTCMinutes") @:hxmc.noGc static function getUTCMinutes(d:Dynamic):Int
		return field(d, true, MIN);

	@:hxmc.host("Date_getUTCSeconds") @:hxmc.noGc static function getUTCSeconds(d:Dynamic):Int
		return field(d, true, SEC);

	@:hxmc.host("Date_getTimezoneOffset") @:hxmc.noGc static function getTimezoneOffset(d:Dynamic):Int {
		var l = Mem.stack(64), u = Mem.stack(64);
		breakDown(ms(d), false, l);
		breakDown(ms(d), true, u);
		return ((mktime(u) - mktime(l)) / 60).toInt();
	}

	// "%04d-%02d-%02d %02d:%02d:%02d" of the local time
	@:hxmc.host("Date_toString") static function toString(d:Dynamic):String {
		var tm = Mem.stack(64);
		breakDown(ms(d), false, tm);
		var b = new StringBuf();
		inline function pad(v:Int, w:Int) {
			if (v < 0) {
				b.addChar("-".code);
				v = -v;
				w--;
			}
			var s = Str.ofInt(v);
			for (_ in Str.len(s)...w)
				b.addChar("0".code);
			b.add(s);
		}
		pad(Mem.getI32(tm, YEAR) + 1900, 4);
		b.addChar("-".code);
		pad(Mem.getI32(tm, MON) + 1, 2);
		b.addChar("-".code);
		pad(Mem.getI32(tm, MDAY), 2);
		b.addChar(" ".code);
		pad(Mem.getI32(tm, HOUR), 2);
		b.addChar(":".code);
		pad(Mem.getI32(tm, MIN), 2);
		b.addChar(":".code);
		pad(Mem.getI32(tm, SEC), 2);
		return b.toString();
	}

	// ---- Math.random: [0, 1) from rand() (the UCRT's has 15 bits: two make 30)
	@:hxmc.host("Math_random") @:hxmc.noGc static function random():Float {
		if (windows()) return ((LibC.rand() << 15) ^ LibC.rand()) / 1073741824.0;
		return LibC.rand() / 2147483648.0;
	}
}
