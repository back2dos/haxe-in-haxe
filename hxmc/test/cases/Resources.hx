// resource: Resources.txt@greeting
// resource: Resources.txt@copy
// haxe.Resource (--resource, upstream's unit test TestResource): the
// program's resources, each one's name and data in base64 as genjs writes
// them (FnLower: `untyped __resources__()`).
class Resources {
	static function main() {
		var names = haxe.Resource.listNames();
		names.sort(Reflect.compare);
		Sys.println(names);
		Sys.println(haxe.Resource.getString("greeting"));
		var b = haxe.Resource.getBytes("copy");
		Sys.println(b.length + " " + b.toHex());
		Sys.println(haxe.Resource.getString("missing") + " " + haxe.Resource.getBytes("missing"));
	}
}
