package sys.thread;

// Single-threaded stand-in for the JS benchmark build only (Node has no shared-memory threads).
class Condition {
	public function new() {}
	public function acquire():Void {}
	public function tryAcquire():Bool return true;
	public function release():Void {}
	public function wait():Void throw "Condition.wait would block forever (single-threaded JS build)";
	public function signal():Void {}
	public function broadcast():Void {}
}
