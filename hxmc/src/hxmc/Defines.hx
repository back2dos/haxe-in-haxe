package hxmc;

// Target-specific help entries, installed only by the hxmc entry points.
// Keep the reference compiler's registry in haxe/src unchanged.
class Defines {
	static var installed = false;

	public static function install():Void {
		if (installed) return;
		installed = true;
		core.DefineRegistry.all.push({
			key: "hxmc.check_vector_access",
			doc: "Check haxe.ds.Vector reads and writes on hxmc; throw haxe.exceptions.ArgumentException for an invalid index. Off by default.",
			flags: []
		});
	}
}
