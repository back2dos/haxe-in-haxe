package sys.thread;

// Single-threaded stand-in for the JS benchmark build only (Node has no shared-memory threads).
class Mutex {
	public function new() {}
	public function acquire():Void {}
	public function tryAcquire():Bool return true;
	public function release():Void {}
}
