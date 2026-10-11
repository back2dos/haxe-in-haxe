package context;

// port: hxb_reader_stats and create_hxb_reader_stats from haxe/src/compiler/hxb/hxbReader.ml;
// incremented by compiler.hxb.HxbReader.
@:structInit class HxbReaderStatsData {
	public var modulesFullyRestored:Int;
	public var modulesPartiallyRestored:Int;

	public inline function new(modulesFullyRestored:Int, modulesPartiallyRestored:Int) {
		this.modulesFullyRestored = modulesFullyRestored;
		this.modulesPartiallyRestored = modulesPartiallyRestored;
	}

	public inline function clone():HxbReaderStatsData return new HxbReaderStatsData(modulesFullyRestored, modulesPartiallyRestored);
}

class HxbReaderStats {
	public static function create():HxbReaderStatsData return {modulesFullyRestored: 0, modulesPartiallyRestored: 0};
}
