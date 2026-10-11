package syntax;

import core.ds.InvalidArgument;
import core.ds.OcamlInt;

/**
	A single version within semver string (e.g major or minor or patch)
**/
enum SemVerPart {
	// port: OCaml int (63-bit); kept as Int64 so int_of_string's full range survives.
	SVNum(value:haxe.Int64);
	SVStr(value:String); // `alpha`, `pre`, `rc` etc.
}

// port: upstream uses the tuple ((major,minor,patch),pre); `release` holds exactly
// the three parts produced by parse_release.
@:structInit class SemVer {
	public var release:Array<SemVerPart>;
	public var pre:Null<Array<SemVerPart>>;

	public inline function new(release:Array<SemVerPart>, pre:Null<Array<SemVerPart>>) {
		this.release = release;
		this.pre = pre;
	}

	public inline function clone():SemVer return new SemVer(release, pre);
}

class SemVerTools {
	public static function stringOfVersion(version:SemVerPart):String {
		return switch (version) {
			case SVNum(n): "SVNum " + haxe.Int64.toStr(n);
			case SVStr(s): "SVStr " + s;
		};
	}

	public static function toString(version:SemVer):String {
		function str(v:SemVerPart) {
			return switch (v) {
				case SVNum(n): haxe.Int64.toStr(n);
				case SVStr(s): s;
			}
		}
		return version.release.map(str).join(".") + switch (version.pre) {
			case null: "";
			case pre: "-" + pre.map(str).join(".");
		};
	}

	/**
		Parse SemVer string
	**/
	public static function parseVersion(s:String):SemVer {
		function error():Dynamic {
			throw new InvalidArgument("Invalid version string \"" + s + "\". Should follow SemVer.");
		}
		function parse(dotted_str:String) {
			// port: ExtString.String.nsplit (an empty string has no parts).
			return (dotted_str == "" ? [] : dotted_str.split(".")).map(function(s) {
				return try SVNum(OcamlInt.parse(s)) catch (_:Dynamic) SVStr(s);
			});
		}
		function parse_release(dotted_str:String) {
			return switch (parse(dotted_str)) {
				case [major = SVNum(_), minor = SVNum(_), patch = SVNum(_)]: [major, minor, patch];
				case _: error();
			}
		}
		var index = s.indexOf("-");
		return switch (index) {
			// 1.2.3
			case -1: new SemVer(parse_release(s), null);
			// 1.2.3-
			case index if (index + 1 == s.length): error();
			// 1.2.3-alpha.1+23
			case index:
				var release = parse_release(s.substr(0, index));
				var pre = {
					var pre_str = s.substr(index + 1, s.length - (index + 1));
					// remove build meta
					var pre_str = switch (pre_str.indexOf("+")) {
						case -1: pre_str;
						case i: pre_str.substr(0, i);
					}
					parse(pre_str);
				}
				new SemVer(release, pre);
		}
	}

	/**
		@see https://semver.org/#spec-item-11
	**/
	public static function compareVersion(a:SemVer, b:SemVer):Int {
		function compare_v(v1:SemVerPart, v2:SemVerPart) {
			return switch [v1, v2] {
				case [SVNum(n1), SVNum(n2)]: haxe.Int64.compare(n1, n2) < 0 ? -1 : haxe.Int64.compare(n1, n2) > 0 ? 1 : 0;
				case [SVStr(s1), SVStr(s2)]: s1 < s2 ? -1 : s1 > s2 ? 1 : 0;
				case [SVStr(_), SVNum(_)]: 1;
				case [SVNum(_), SVStr(_)]: -1;
			}
		}
		function compare_lists(version_list1:Array<SemVerPart>, version_list2:Array<SemVerPart>) {
			// port: the recursion over both lists, as a loop.
			var i = 0;
			while (true) {
				if (i == version_list1.length && i == version_list2.length) return 0;
				if (i == version_list1.length) return -1;
				if (i == version_list2.length) return 1;
				var diff = compare_v(version_list1[i], version_list2[i]);
				if (diff != 0) return diff;
				i++;
			}
		}
		var diff = compare_lists(a.release, b.release);
		return if (diff != 0) diff else switch [a.pre, b.pre] {
			case [null, null]: 0;
			case [null, _]: 1;
			case [_, null]: -1;
			case [pre1, pre2]: compare_lists(pre1, pre2);
		}
	}
}
