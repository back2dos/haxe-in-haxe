package uv;

import haxe.Int64;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.run.Setup.LoopSetup;
import hxcoro.schedulers.ILoop;
import hxcoro.task.NodeLambda;
import uv.Uv;

using hxcoro.run.ContextRun;
using hxcoro.util.Convenience;

// hxcoro on a libuv loop for single-threaded hxc programs: what hxcoro's
// LuvScheduler is for Eval (eval.luv) and hxcpp, over uv.Uv instead. Coroutines
// suspend on libuv callbacks (see `await`) and timers; the loop runs until the
// main task completes.

private class TimerEvent implements ISchedulerHandle implements IDispatchObject {
	final cont:IContinuation<Any>;
	var timer:Null<Timer>;

	public function new(loop:Loop, ms:Int, cont:IContinuation<Any>) {
		this.cont = cont;
		timer = new Timer(loop);
		timer.start(fire, ms);
	}

	function fire() {
		close();
		cont.context.getOrRaise(haxe.coro.dispatchers.Dispatcher).dispatch(this);
	}

	public function onDispatch()
		cont.resume(null, null);

	public function close() {
		if (timer != null) {
			timer.stop();
			timer.close();
			timer = null;
		}
	}
}

class UvScheduler implements IScheduler implements ILoop {
	public final uvLoop:Loop;

	public function new(loop:Loop)
		uvLoop = loop;

	public function schedule<T>(ms:Int64, cont:IContinuation<T>):ISchedulerHandle
		return new TimerEvent(uvLoop, Int64.toInt(ms), cast cont);

	public function now():Int64
		return Int64.fromFloat(uvLoop.now());

	public function loop(runMode:hxcoro.schedulers.ILoop.RunMode)
		uvLoop.run(runMode == Once ? Once : NoWait);

	public function wakeUp() {}
}

class Coro {
	/** Runs `lambda` on the default libuv loop until it returns or throws. **/
	static public function run<T>(lambda:NodeLambda<T>):T {
		var scheduler = new UvScheduler(Loop.get());
		var setup = new LoopSetup(scheduler, new TrampolineDispatcher(scheduler));
		var task = hxcoro.run.LoopRun.runTask(setup.loop, setup.createContext(), lambda);
		return @:privateAccess ContextRun.resolveTask(task);
	}

	/**
		Suspends until `start`'s callback is called: with a value, or with an
		exception (thrown here).
	**/
	@:coroutine static public function await<T>(start:(done:(value:Null<T>, error:Null<haxe.Exception>) -> Void) -> Void):T {
		return hxcoro.Coro.suspend(cont -> start((value, error) -> cont.resume(value, error)));
	}
}
