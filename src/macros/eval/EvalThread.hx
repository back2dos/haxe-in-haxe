package macros.eval;

import macros.eval.EvalValue;
import macros.eval.EvalContext;

// port: deviations:
// - `Deque` locks and waits on `dcond` (a host `sys.thread.Condition` owns its
//   mutex); `dmutex` is not used by these functions.
// - `ctx.next_thread_id` and `ctx.evals` are plain fields guarded by
//   `threadLock` (upstream: an `Atomic.t` and a `ThreadSafeHashtbl`).
// - OCaml domains (`spawn_domain`) and threads both become host threads,
//   which run Eval code holding `EvalLock` (OCaml's runtime lock).
class Deque {
	public static function create():Vdeque return new Vdeque();

	public static function add(self:Vdeque, i:Value):Void {
		self.dcond.acquire();
		self.dvalues.push(i);
		self.dcond.signal();
		self.dcond.release();
	}

	public static function pop(self:Vdeque, blocking:Bool):Null<Value> {
		// port: a blocking pop waits without the Eval lock (Condition.wait releases OCaml's runtime lock)
		return if (blocking) EvalLock.blocking(() -> popHost(self, true)) else popHost(self, false);
	}

	static function popHost(self:Vdeque, blocking:Bool):Null<Value> {
		self.dcond.acquire();
		if (blocking) {
			while (self.dvalues.length == 0) self.dcond.wait();
		}
		var result = if (self.dvalues.length > 0) self.dvalues.shift() else null;
		self.dcond.release();
		return result;
	}

	public static function push(self:Vdeque, i:Value):Void {
		self.dcond.acquire();
		self.dvalues.unshift(i);
		self.dcond.signal();
		self.dcond.release();
	}
}

class EvalThread {
	static final threadLock = new sys.thread.Mutex();

	public static function createEval(tthread:Vthread):Eval {
		threadLock.acquire();
		var breakpoint = EvalDebugMisc.makeBreakpoint(0, 0, BPDisabled, BPAny, null);
		threadLock.release();
		var eval = new Eval(tthread, breakpoint);
		return eval;
	}

	public static function run(ctx:Context, tthread:Vthread, f:Void->Value):Void {
		var newEval = createEval(tthread);
		var id = tthread.threadId;
		function maybeSendThreadEvent(reason:String):Void {
			switch ctx.debug.debugSocket {
				case null:
				case socket:
					socket.connection.sendThreadEvent(id, reason);
			}
		}
		threadLock.acquire();
		ctx.evals.add(id, newEval);
		threadLock.release();
		EvalContext.setEval(ctx, newEval);
		inline function close():Void {
			threadLock.acquire();
			ctx.evals.remove(id);
			threadLock.release();
			maybeSendThreadEvent("exited");
		}
		try {
			maybeSendThreadEvent("started");
			f();
			close();
		} catch (e:RunTimeException) {
			var msg = EvalExceptions.getExcErrorMessage(ctx, e.value, e.envs, e.pos);
			Sys.stderr().writeString(msg + "\n");
			close();
		} catch (e:macros.eval.EvalTypes.SysExit) {
			close();
			Sys.exit(e.code);
		} catch (exc:Dynamic) {
			close();
			throw exc;
		}
	}

	public static function createThreadInfo(ctx:Context, mode:Null<VthreadMode>):Vthread {
		threadLock.acquire();
		var id = ctx.nextThreadId;
		ctx.nextThreadId = id + 1;
		threadLock.release();
		var id = id + 1;
		var tthread = new Vthread(id, mode, Deque.create());
		return tthread;
	}

	public static function spawnDomain(ctx:Context, f:Void->Value):Vthread return spawn(ctx, f, true);

	public static function spawnThread(ctx:Context, f:Void->Value):Vthread return spawn(ctx, f, false);

	static function spawn(ctx:Context, f:Void->Value, domain:Bool):Vthread {
		var tthread = createThreadInfo(ctx, null);
		var startSem = new sys.thread.Semaphore(0);
		var finished = new sys.thread.Lock();
		EvalLock.activate();
		var t = sys.thread.Thread.create(() -> {
			startSem.acquire();
			EvalLock.enter();
			try run(ctx, tthread, f)
			catch (e:Dynamic) {
				EvalLock.leave();
				finished.release();
				throw e;
			}
			EvalLock.leave();
			finished.release();
		});
		tthread.threadMode = domain ? Domain(t, finished) : Thread(t, finished);
		startSem.release();
		return tthread;
	}
}
