package context;

// Shared counters from haxe/src/compiler/hxb/hxbReader.ml:21-29.
// This model does not implement HXB-library input.
@:structInit class HxbReaderStatsData {
	public var modulesFullyRestored:Int;
	public var modulesPartiallyRestored:Int;
	public inline function new(modulesFullyRestored:Int, modulesPartiallyRestored:Int) { this.modulesFullyRestored = modulesFullyRestored; this.modulesPartiallyRestored = modulesPartiallyRestored; }
	public inline function clone():HxbReaderStatsData return new HxbReaderStatsData(modulesFullyRestored, modulesPartiallyRestored);
}
class HxbReaderStats {
 public static function create():HxbReaderStatsData return {modulesFullyRestored:0,modulesPartiallyRestored:0};
}
