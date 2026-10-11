import eval.luv.*;
import eval.vm.NativeThread;

// eval.luv threads, thread pool and synchronization primitives in the port's
// Eval (src/macros/eval/EvalLuv.hx); the output must match the reference
// (`haxe/haxe -cp hxc/test/natives -main LuvThreads --interp`). Orders that
// depend on thread timing are sorted.
class LuvThreads {
	static function unwrap<T>(r:Result<T>):T {
		return switch r {
			case Ok(v): v;
			case Error(e): throw 'error $e';
		}
	}

	static function main() {
		var loop = Loop.defaultLoop();
		var mainId = NativeThread.self().id();

		// Thread.self, create, join
		var main = Thread.self();
		Sys.println("self equal: " + (main == Thread.self()));
		var mutex = unwrap(Mutex.init());
		var log = [];
		var t = unwrap(Thread.create(() -> {
			mutex.lock();
			log.push("in thread");
			mutex.unlock();
		}));
		Sys.println("join: " + t.join());
		Sys.println("join again: " + t.join());
		Sys.println("log: " + log);
		Sys.println("join self: " + Thread.self().join());
		var inner:Null<Thread> = null;
		var t2 = unwrap(Thread.create(() -> inner = Thread.self()));
		t2.join();
		Sys.println("inner == t2: " + (inner == t2) + ", inner == main: " + (inner == main));

		// eval.vm.NativeThread in a luv thread: own Eval thread, messages, exit
		var lock = new sys.thread.Lock();
		var other:Null<NativeThread> = null;
		var t3 = unwrap(Thread.create(() -> {
			other = NativeThread.self();
			lock.release();
			var msg = NativeThread.readMessage(true);
			Sys.println("luv thread got " + msg + ", own id: " + (NativeThread.self().id() != mainId));
			NativeThread.exit();
			Sys.println("unreachable");
		}));
		lock.wait();
		other.sendMessage("hello");
		t3.join();

		// Mutex
		Sys.println("tryLock: " + mutex.tryLock());
		var t4 = unwrap(Thread.create(() -> Sys.println("tryLock (other thread, held): " + mutex.tryLock())));
		t4.join();
		mutex.unlock();
		var rec = unwrap(Mutex.init(true));
		rec.lock();
		Sys.println("recursive tryLock: " + rec.tryLock());
		rec.unlock();
		rec.unlock();

		// Condition: producer / consumer
		var cond = unwrap(Condition.init());
		var queue = [];
		var consumer = unwrap(Thread.create(() -> {
			var got = [];
			mutex.lock();
			while (got.length < 3) {
				while (queue.length == 0)
					cond.wait(mutex);
				got.push(queue.shift());
			}
			mutex.unlock();
			Sys.println("consumer got " + got);
		}));
		for (i in 0...3) {
			mutex.lock();
			queue.push(i);
			cond.signal();
			mutex.unlock();
		}
		consumer.join();
		mutex.lock();
		cond.timedWait(mutex, 1000000);
		mutex.unlock();
		Sys.println("timedWait returned");

		// Semaphore
		var sem = unwrap(Semaphore.init(0));
		Sys.println("tryWait: " + sem.tryWait());
		var poster = unwrap(Thread.create(() -> {
			sem.post();
			sem.post();
		}));
		sem.wait();
		sem.wait();
		poster.join();
		Sys.println("semaphore done, tryWait: " + sem.tryWait());

		// RwLock
		var rw = unwrap(RwLock.init());
		rw.rdLock();
		Sys.println("rdTryLock while reading: " + rw.rdTryLock());
		Sys.println("wrTryLock while reading: " + rw.wrTryLock());
		rw.rdUnlock();
		rw.rdUnlock();
		Sys.println("wrTryLock: " + rw.wrTryLock());
		Sys.println("rdTryLock while writing: " + rw.rdTryLock());
		rw.wrUnlock();

		// Barrier
		var barrier = unwrap(Barrier.init(3));
		var serials = 0;
		var counter = unwrap(Mutex.init());
		function arrive() {
			if (barrier.wait()) {
				counter.lock();
				serials++;
				counter.unlock();
			}
		}
		var threads = [for (i in 0...2) unwrap(Thread.create(arrive))];
		arrive();
		for (t in threads)
			t.join();
		Sys.println("barrier serial threads: " + serials);
		Sys.println("barrier 0: " + Barrier.init(0));

		// Once
		var once = unwrap(Once.init());
		var calls = 0;
		var ts = [for (i in 0...3) unwrap(Thread.create(() -> once.once(() -> calls++)))];
		for (t in ts)
			t.join();
		once.once(() -> calls++);
		Sys.println("once calls: " + calls);

		// ThreadPool: work, after-work callbacks on the loop, cancellation
		var results = [];
		var after = [];
		for (i in 0...3) {
			ThreadPool.queueWork(loop, null, () -> {
				mutex.lock();
				results.push("work " + i + (NativeThread.self().id() != mainId ? " (pool thread)" : ""));
				mutex.unlock();
			}, r -> after.push("after work " + i + ": " + r));
		}
		Sys.println("cancel fresh request: " + ThreadPool.createRequest().cancel());
		var cancelled = ThreadPool.createRequest();
		ThreadPool.queueWork(loop, cancelled, () -> Sys.println("cancelled work ran"), r -> after.push("cancelled callback: " + r));
		Sys.println("cancel queued: " + cancelled.cancel());
		Sys.println("alive: " + loop.alive());
		loop.run(DEFAULT);
		results.sort(Reflect.compare);
		after.sort(Reflect.compare);
		Sys.println(after.join("\n"));
		Sys.println("results: " + results);
		Sys.println("alive after: " + loop.alive());

		// a thread signalling an Async while the loop runs
		var async:Null<Async> = null;
		async = unwrap(Async.init(loop, a -> {
			Sys.println("async received");
			a.close(() -> Sys.println("async closed"));
		}));
		var signaller = unwrap(Thread.create(() -> {
			Sys.sleep(0.05);
			async.send();
		}));
		loop.run(DEFAULT);
		signaller.join();

		// work queued from a loop callback
		var timer = unwrap(Timer.init(loop));
		timer.start(() -> {
			ThreadPool.queueWork(loop, null, () -> Sys.sleep(0.02), r -> Sys.println("nested work done: " + r));
			timer.close(() -> {});
		}, 10);
		loop.run(DEFAULT);

		// Loop.stop while other threads exist
		var n = 0;
		var bg = unwrap(Thread.create(() -> Sys.sleep(0.2)));
		timer = unwrap(Timer.init(loop));
		timer.start(() -> {
			n++;
			if (n == 3)
				loop.stop();
		}, 5, 5);
		Sys.println("run returns " + loop.run(DEFAULT) + " after " + n);
		timer.stop();
		timer.close(() -> {});
		loop.run(DEFAULT);
		bg.join();

		// Loop.run ONCE until pending work completes
		var flag = false;
		ThreadPool.queueWork(loop, null, () -> Sys.sleep(0.05), _ -> flag = true);
		while (!flag)
			loop.run(ONCE);
		Sys.println("once loop done: " + flag);

		// exceptions in luv threads go to the unhandled exception handler
		UVError.setOnUnhandledException(e -> Sys.println("unhandled: " + e));
		var bad = unwrap(Thread.create(() -> throw "boom"));
		bad.join();
		ThreadPool.queueWork(loop, null, () -> throw "work boom", r -> Sys.println("after bad work: " + r));
		loop.run(DEFAULT);
		ThreadPool.setSize(8, true);
		Sys.println("done");
	}
}
