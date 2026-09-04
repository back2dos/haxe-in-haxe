package context;

// Shared counters from haxe/src/compiler/hxb/hxbReader.ml:21-29.
// This model does not implement HXB-library input.
typedef HxbReaderStatsData = { var modulesFullyRestored:Int; var modulesPartiallyRestored:Int; }
class HxbReaderStats {
 public static function create():HxbReaderStatsData return {modulesFullyRestored:0,modulesPartiallyRestored:0};
}
