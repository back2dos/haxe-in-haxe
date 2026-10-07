package sys.thread;

// Runs the job synchronously; the compiler only spawns workers when parallelism is enabled.
class Thread {
	static final main = new Thread();
	function new() {}
	public static function current():Thread return main;
	public static function create(job:() -> Void):Thread {
		job();
		return new Thread();
	}
	public function join():Void {}
}
