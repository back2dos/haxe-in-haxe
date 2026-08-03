package unit.moduleload;

typedef Cursor<T> = {
	function hasNext():Bool;
	function next():T;
}
