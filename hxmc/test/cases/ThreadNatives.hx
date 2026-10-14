// The thread natives: haxe.atomic cells (contended from several threads, and
// object cells holding young objects across collections), Tls, Mutex, Lock,
// Condition, Semaphore and Deque. Output is deterministic.
import haxe.atomic.AtomicBool;
import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicObject;
import sys.thread.Condition;
import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Semaphore;
import sys.thread.Thread;
import sys.thread.Tls;

class Box {
	public var v:Int;
	public var s:String;

	public function new(v:Int) {
		this.v = v;
		s = "box" + v;
	}
}

class ThreadNatives {
	static function garbage(n:Int):Int {
		var t = 0;
		for (i in 0...n) {
			var a = [i, i + 1, i + 2];
			t += a.length + ("x" + i).length;
		}
		return t;
	}

	static function main() {
		// Int cells, single-threaded
		var a = new AtomicInt(5);
		trace(a.load(), a.add(3), a.load(), a.sub(10), a.load());
		trace(a.and(0xF0), a.load(), a.or(0x0F), a.load(), a.xor(0xFF), a.load());
		trace(a.exchange(42), a.compareExchange(41, 0), a.load(), a.compareExchange(42, 7), a.load(), a.store(-1), a.load());
		var big = new AtomicInt(0x7FFFFFFF);
		trace(big.add(1), big.load(), big.sub(1), big.load());
		var b = new AtomicBool(false);
		trace(b.load(), b.exchange(true), b.load(), b.compareExchange(true, false), b.load());

		// object cells: young values stored into an old cell survive minor collections
		var o = new AtomicObject<Box>(new Box(1));
		garbage(200000);
		var x = new Box(2);
		trace(o.store(x).v, o.load().s);
		garbage(200000);
		trace(o.load().s);
		var b1 = o.load();
		trace(o.compareExchange(new Box(9), new Box(3)).v, o.load().v);
		trace(o.compareExchange(b1, new Box(4)).v, o.load().v);
		garbage(200000);
		trace(o.exchange(new Box(5)).s, o.load().s);
		garbage(200000);
		trace(o.load().s);
		var on = new AtomicObject<Box>(null);
		trace(on.load() == null, on.store(null) == null, on.compareExchange(null, new Box(6)) == null, on.load().v);

		// contended counters
		var counter = new AtomicInt(0);
		var bits = new AtomicInt(0);
		var cell = new AtomicObject<Box>(new Box(0));
		var mutex = new Mutex();
		var shared = 0;
		var done = new Lock();
		var n = 4, per = 20000;
		for (t in 0...n) {
			Thread.create(() -> {
				for (i in 0...per) {
					counter.add(1);
					if (i % 1000 == 0) {
						bits.or(1 << t);
						garbage(100);
					}
					var cur = cell.load();
					while (true) {
						var seen = cell.compareExchange(cur, new Box(cur.v + 1));
						if (seen == cur) break;
						cur = seen;
					}
					mutex.acquire();
					shared++;
					mutex.release();
				}
				done.release();
			});
		}
		for (t in 0...n) done.wait();
		trace(counter.load(), bits.load(), cell.load().v, cell.load().s, shared);

		// Tls
		var tls = new Tls<String>();
		tls.value = "main";
		var l = new Lock();
		Thread.create(() -> {
			var before = tls.value == null;
			tls.value = "child";
			trace(before, tls.value);
			l.release();
		});
		l.wait();
		trace(tls.value);

		// Condition, Semaphore, Deque
		var cond = new Condition();
		var ready = new AtomicBool(false);
		Thread.create(() -> {
			cond.acquire();
			ready.store(true);
			cond.signal();
			cond.release();
		});
		cond.acquire();
		while (!ready.load()) cond.wait();
		cond.release();
		trace("condition", ready.load());
		var sem = new Semaphore(0);
		var q = new Deque<Int>();
		Thread.create(() -> {
			for (i in 0...5) q.add(i * i);
			sem.release();
		});
		sem.acquire();
		var got = [];
		for (i in 0...5) got.push(q.pop(true));
		trace(got, sem.tryAcquire(), q.pop(false));
		trace(new Lock().wait(0.01));
	}
}
