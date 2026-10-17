package hxmc.rt.gc;

// -D hxmc.wasm-gc: Date, a time in milliseconds (GcDateValue), its calendar
// fields from the host's (W.dateNum: op 0 a local time's milliseconds, 1-7
// the local fields, 8-14 the UTC ones, 15 the zone's offset, 16 now)
@:keep @:hxmc.wasmgc
class GcDate {
	static inline function t(d:Dynamic):Float
		return (d : GcDateValue).t;

	static inline function field(d:Dynamic, op:Int):Int
		return Std.int(W.dateNum(op, t(d), 0, 0, 0, 0, 0, 0));

	@:hxmc.host("Date_new") static function make(y:Int, m:Int, d:Int, h:Int, mi:Int, s:Int):Dynamic
		return new GcDateValue(W.dateNum(0, 0, y, m, d, h, mi, s));

	@:hxmc.host("Date_now") static function now():Dynamic
		return new GcDateValue(W.dateNum(16, 0, 0, 0, 0, 0, 0, 0));

	@:hxmc.host("Date_fromTime") static function fromTime(t:Float):Dynamic
		return new GcDateValue(t);

	// "YYYY-MM-DD hh:mm:ss", "YYYY-MM-DD" or "hh:mm:ss" (a time of day: from the epoch, UTC)
	@:hxmc.host("Date_fromString") static function fromString(s:String):Dynamic {
		inline function num(i:Int, n:Int):Int {
			var v = Std.parseInt(s.substr(i, n));
			if (v == null) throw "Invalid date format : " + s;
			return v;
		}
		return switch s.length {
			case 8: new GcDateValue(1000.0 * (num(0, 2) * 3600 + num(3, 2) * 60 + num(6, 2)));
			case 10: make(num(0, 4), num(5, 2) - 1, num(8, 2), 0, 0, 0);
			case 19: make(num(0, 4), num(5, 2) - 1, num(8, 2), num(11, 2), num(14, 2), num(17, 2));
			case _: throw "Invalid date format : " + s;
		}
	}

	@:hxmc.host("Date_getTime") @:hxmc.noGc static function getTime(d:Dynamic):Float
		return t(d);

	@:hxmc.host("Date_getFullYear") @:hxmc.noGc static function getFullYear(d:Dynamic):Int
		return field(d, 1);

	@:hxmc.host("Date_getMonth") @:hxmc.noGc static function getMonth(d:Dynamic):Int
		return field(d, 2);

	@:hxmc.host("Date_getDate") @:hxmc.noGc static function getDate(d:Dynamic):Int
		return field(d, 3);

	@:hxmc.host("Date_getDay") @:hxmc.noGc static function getDay(d:Dynamic):Int
		return field(d, 4);

	@:hxmc.host("Date_getHours") @:hxmc.noGc static function getHours(d:Dynamic):Int
		return field(d, 5);

	@:hxmc.host("Date_getMinutes") @:hxmc.noGc static function getMinutes(d:Dynamic):Int
		return field(d, 6);

	@:hxmc.host("Date_getSeconds") @:hxmc.noGc static function getSeconds(d:Dynamic):Int
		return field(d, 7);

	@:hxmc.host("Date_getUTCFullYear") @:hxmc.noGc static function getUTCFullYear(d:Dynamic):Int
		return field(d, 8);

	@:hxmc.host("Date_getUTCMonth") @:hxmc.noGc static function getUTCMonth(d:Dynamic):Int
		return field(d, 9);

	@:hxmc.host("Date_getUTCDate") @:hxmc.noGc static function getUTCDate(d:Dynamic):Int
		return field(d, 10);

	@:hxmc.host("Date_getUTCDay") @:hxmc.noGc static function getUTCDay(d:Dynamic):Int
		return field(d, 11);

	@:hxmc.host("Date_getUTCHours") @:hxmc.noGc static function getUTCHours(d:Dynamic):Int
		return field(d, 12);

	@:hxmc.host("Date_getUTCMinutes") @:hxmc.noGc static function getUTCMinutes(d:Dynamic):Int
		return field(d, 13);

	@:hxmc.host("Date_getUTCSeconds") @:hxmc.noGc static function getUTCSeconds(d:Dynamic):Int
		return field(d, 14);

	@:hxmc.host("Date_getTimezoneOffset") @:hxmc.noGc static function getTimezoneOffset(d:Dynamic):Int
		return field(d, 15);

	static function two(v:Int):String
		return v < 10 ? "0" + v : "" + v;

	@:hxmc.host("Date_toString") static function toString(d:Dynamic):String
		return getFullYear(d) + "-" + two(getMonth(d) + 1) + "-" + two(getDate(d)) + " " + two(getHours(d)) + ":" + two(getMinutes(d)) + ":"
			+ two(getSeconds(d));
}

@:keep @:hxmc.wasmgc
class GcDateValue {
	public final t:Float;

	public function new(t)
		this.t = t;
}
