// @:hxmc.noGc is a checked rule: the chain of calls to the first GC point is named.
// expect: NoGcAlloc.hx:11: NoGcAlloc.leaf is declared @:hxmc.noGc but reaches a GC point: it calls NoGcAlloc.helper, which allocates an array
class NoGcAlloc {
	static var keep:Array<Int>;

	static function helper(n:Int):Int {
		keep = [n];
		return n;
	}

	@:hxmc.noGc static function leaf(n:Int):Int
		return helper(n) + 1;

	static function main()
		trace(leaf(1));
}
