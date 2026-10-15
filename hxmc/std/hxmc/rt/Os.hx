package hxmc.rt;

import hxmc.I64;
import hxmc.rt.Layouts as L;
import hxmc.unsafe.*;

// The system layer of the native runtime's collector and threads (once the
// C of rt.c and rt_thread.c): reserved memory committed as it is touched,
// mutexes and condition variables (pthreads; Windows: SRW locks and
// condition variables), detached threads, the main program's large stack
// (a pthread whose stack is a reservation; Windows: a fiber), time, the
// environment, errno, poll. Every function is no-GC: the collector calls
// them while objects move, and threads call them where they hold no heap
// pointer. The C structures are opaque memory of the target's sizes
// (Layouts, read from the headers).
@:hxmc.native
class Os {
	static inline function windows():Bool
		return Mem.os() == 2;

	static inline function mac():Bool
		return Mem.os() == 1;

	// ---- the environment

	@:hxmc.noGc public static function getenv(name:String):Ptr {
		var buf = Mem.stack(64);
		for (i in 0...name.length)
			Mem.setI8(buf, i, StringTools.fastCodeAt(name, i));
		Mem.setI8(buf, name.length, 0);
		return C.getenv(buf);
	}

	@:hxmc.noGc public static function has(name:String):Bool
		return !getenv(name).isNull();

	// the decimal value of an environment variable (atoi), or def when unset
	@:hxmc.noGc public static function envInt(name:String, def:Int):Int {
		var p = getenv(name);
		if (p.isNull()) return def;
		var i = 0, neg = false, v = 0;
		while (Mem.getU8(p, i) == " ".code)
			i++;
		if (Mem.getU8(p, i) == "-".code) {
			neg = true;
			i++;
		} else if (Mem.getU8(p, i) == "+".code)
			i++;
		while (true) {
			var c = Mem.getU8(p, i);
			if (c < "0".code || c > "9".code) break;
			v = v * 10 + (c - "0".code);
			i++;
		}
		return neg ? -v : v;
	}

	// ---- errno (kept across the runtime's own calls around blocking natives)

	@:hxmc.noGc static function errnoPtr():Ptr
		return windows() ? C._errno() : mac() ? C.__error() : C.__errno_location();

	@:hxmc.noGc public static function errno():Int
		return Mem.getI32(errnoPtr(), 0);

	@:hxmc.noGc public static function setErrno(e:Int)
		Mem.setI32(errnoPtr(), 0, e);

	// ---- time

	@:hxmc.noGc public static function now():Float {
		var ts = Mem.stack(16);
		C.clock_gettime(L.CLOCK_MONOTONIC, ts);
		var s:Float = cast Mem.getI64(ts, 0);
		var ns:Float = cast Mem.getI64(ts, 8);
		return s + ns * 1e-9;
	}

	@:hxmc.noGc public static function sleep(seconds:Float) {
		if (seconds <= 0) return;
		if (windows()) {
			var ms = seconds * 1000.0 + 0.999;
			K.Sleep(ms > 4e9 ? -2 : (cast ms : Int));
			return;
		}
		var t = Mem.stack(32);
		var whole = Math.ffloor(seconds);
		Mem.setI64(t, 0, haxe.Int64.fromFloat(whole));
		Mem.setI64(t, 8, haxe.Int64.fromFloat((seconds - whole) * 1e9));
		while (C.nanosleep(t, t) != 0 && errno() == L.EINTR) {}
	}

	@:hxmc.noGc public static function yield()
		if (windows()) K.SwitchToThread() else C.sched_yield();

	// ---- memory: reservations committed as touched

	static var pageBytes:Int;

	@:hxmc.noGc public static function pageSize():Int {
		if (pageBytes == 0) pageBytes = windows() ? WinRtCalls.rt_win_page_size().toInt() : C.sysconf(L.SC_PAGESIZE).toInt();
		return pageBytes;
	}

	// null on failure
	@:hxmc.noGc public static function reserve(bytes:I64):Ptr {
		if (windows()) return WinRtCalls.rt_win_reserve(bytes);
		var p = C.mmap(Ptr.nil(), bytes, L.PROT_READ | L.PROT_WRITE, L.MAP_PRIVATE | L.MAP_ANONYMOUS | L.MAP_NORESERVE, -1, 0);
		return p.toI64() == -1 ? Ptr.nil() : p;
	}

	@:hxmc.noGc public static function release(p:Ptr, bytes:I64)
		if (windows()) WinRtCalls.rt_win_release(p, bytes) else C.munmap(p, bytes);

	// never committed: an access faults
	@:hxmc.noGc public static function guard(p:Ptr, bytes:I64)
		if (windows()) WinRtCalls.rt_win_guard(p, bytes) else C.mprotect(p, bytes, L.PROT_NONE);

	// the pages go back to the system (zeros when touched again); false: not done
	@:hxmc.noGc public static function decommit(p:Ptr, bytes:I64):Bool {
		if (windows()) {
			WinRtCalls.rt_win_decommit(p, bytes);
			return true;
		}
		return C.madvise(p, bytes, L.MADV_DONTNEED) == 0;
	}

	// transparent huge pages (Linux, RT_HUGE)
	@:hxmc.noGc public static function hugePages(p:Ptr, bytes:I64)
		if (L.MADV_HUGEPAGE != 0) C.madvise(p, bytes, L.MADV_HUGEPAGE);

	// ---- mutexes and conditions (malloc'ed: they never move)

	static var condAttr:Ptr; // conditions wait on CLOCK_MONOTONIC (CLOCK_REALTIME on macOS)

	@:hxmc.noGc public static function mutexNew():Ptr {
		if (windows()) {
			var m = LibC.malloc(8);
			Mem.setI64(m, 0, 0); // SRWLOCK_INIT
			return m;
		}
		var m = LibC.malloc((L.PTHREAD_MUTEX_SIZE : I64));
		C.pthread_mutex_init(m, Ptr.nil());
		return m;
	}

	@:hxmc.noGc public static function mutexFree(m:Ptr) {
		if (!windows()) C.pthread_mutex_destroy(m);
		LibC.free(m);
	}

	@:hxmc.noGc public static inline function lock(m:Ptr)
		if (windows()) K.AcquireSRWLockExclusive(m) else C.pthread_mutex_lock(m);

	@:hxmc.noGc public static inline function tryLock(m:Ptr):Bool
		return windows() ? K.TryAcquireSRWLockExclusive(m) & 0xFF != 0 : C.pthread_mutex_trylock(m) == 0;

	@:hxmc.noGc public static inline function unlock(m:Ptr)
		if (windows()) K.ReleaseSRWLockExclusive(m) else C.pthread_mutex_unlock(m);

	@:hxmc.noGc public static function condNew():Ptr {
		if (windows()) {
			var c = LibC.malloc(8);
			Mem.setI64(c, 0, 0); // CONDITION_VARIABLE_INIT
			return c;
		}
		if (condAttr.isNull()) {
			var a = LibC.malloc((L.PTHREAD_CONDATTR_SIZE + 16 : I64));
			C.pthread_condattr_init(a);
			if (!mac()) C.pthread_condattr_setclock(a, L.CLOCK_MONOTONIC);
			condAttr = a;
		}
		var c = LibC.malloc((L.PTHREAD_COND_SIZE : I64));
		C.pthread_cond_init(c, condAttr);
		return c;
	}

	@:hxmc.noGc public static function condFree(c:Ptr) {
		if (!windows()) C.pthread_cond_destroy(c);
		LibC.free(c);
	}

	@:hxmc.noGc public static function condWait(c:Ptr, m:Ptr)
		if (windows()) K.SleepConditionVariableSRW(c, m, -1, 0) else C.pthread_cond_wait(c, m);

	// a deadline `timeout` seconds from now, for condTimedWait (16 bytes at d)
	@:hxmc.noGc public static function deadline(d:Ptr, timeout:Float) {
		if (windows()) {
			Mem.setF64(d, 0, now() + timeout);
			return;
		}
		// macOS: no pthread_condattr_setclock, conditions wait on the real-time clock
		C.clock_gettime(mac() ? L.CLOCK_REALTIME : L.CLOCK_MONOTONIC, d);
		var s:Float = cast Mem.getI64(d, 0);
		var ns:Float = cast Mem.getI64(d, 8);
		var t = s + ns * 1e-9 + timeout;
		var whole = Math.ffloor(t);
		var sec = haxe.Int64.fromFloat(whole);
		var nsec = haxe.Int64.fromFloat((t - whole) * 1e9);
		if (nsec >= 1000000000) {
			sec = sec + 1;
			nsec = nsec - 1000000000;
		}
		Mem.setI64(d, 0, sec);
		Mem.setI64(d, 8, nsec);
	}

	// false: timed out
	@:hxmc.noGc public static function condTimedWait(c:Ptr, m:Ptr, d:Ptr):Bool {
		if (windows()) {
			var left = Mem.getF64(d, 0) - now();
			var ms = left <= 0 ? 0 : left > 4e6 ? -294967296 : (cast (left * 1000.0 + 0.999) : Int);
			if (K.SleepConditionVariableSRW(c, m, ms, 0) != 0) return true;
			return K.GetLastError() != 1460; // ERROR_TIMEOUT
		}
		return C.pthread_cond_timedwait(c, m, d) != L.ETIMEDOUT;
	}

	@:hxmc.noGc public static inline function signal(c:Ptr)
		if (windows()) K.WakeConditionVariable(c) else C.pthread_cond_signal(c);

	@:hxmc.noGc public static inline function broadcast(c:Ptr)
		if (windows()) K.WakeAllConditionVariable(c) else C.pthread_cond_broadcast(c);

	// ---- threads

	// a detached thread running entry(arg) (a no-GC @:hxmc.callback taking and
	// returning a pointer) on a C stack of stackBytes (reserved); false: failed
	@:hxmc.noGc public static function spawn(entry:Ptr, arg:Ptr, stackBytes:I64):Bool {
		if (windows()) {
			// STACK_SIZE_PARAM_IS_A_RESERVATION; not joined
			var h = K.CreateThread(Ptr.nil(), stackBytes, entry, arg, 0x10000, Ptr.nil());
			if (h.isNull()) return false;
			K.CloseHandle(h);
			return true;
		}
		var attr = Mem.stack(128);
		C.pthread_attr_init(attr);
		C.pthread_attr_setstacksize(attr, stackBytes);
		C.pthread_attr_setdetachstate(attr, L.PTHREAD_CREATE_DETACHED);
		var t = Mem.stack(16);
		var r = C.pthread_create(t, attr, entry, arg);
		C.pthread_attr_destroy(attr);
		return r == 0;
	}

	// runs entry(arg) on a stack of `bytes` (reserved, committed as touched,
	// with a guard page) and waits for it: a joined pthread whose stack is a
	// reservation; Windows: a fiber of the calling thread. False: no such
	// stack (the caller runs it as it is).
	@:hxmc.noGc public static function runOnStack(entry:Ptr, fiberEntry:Ptr, arg:Ptr, bytes:I64):Bool {
		if (windows()) {
			var main = K.ConvertThreadToFiber(Ptr.nil());
			if (main.isNull()) return false;
			Mem.setPtr(arg, 0, main); // (the fiber switches back to it)
			// FIBER_FLAG_FLOAT_SWITCH
			var f = K.CreateFiberEx(64 << 10, bytes, 1, fiberEntry, arg);
			if (f.isNull()) return false;
			K.SwitchToFiber(f);
			return true;
		}
		var stack = reserve(bytes);
		if (stack.isNull()) return false;
		guard(stack, pageSize());
		var attr = Mem.stack(128);
		C.pthread_attr_init(attr);
		C.pthread_attr_setstack(attr, stack, bytes);
		var t:Ptr<Ptr> = Mem.stack(16);
		var r = C.pthread_create(t, attr, entry, arg);
		C.pthread_attr_destroy(attr);
		if (r != 0) {
			release(stack, bytes);
			return false;
		}
		C.pthread_join(t.value, Ptr.nil());
		return true;
	}

	// a fiber's end (Windows): back to the thread's own fiber
	@:hxmc.noGc public static function fiberReturn(to:Ptr)
		K.SwitchToFiber(to);

	// ---- descriptors: poll (Windows: WSAPoll, sockets only)

	@:hxmc.noGc public static function poll(fds:Ptr, n:Int, ms:Int):Int {
		if (windows()) {
			var r = W.WSAPoll(fds, n, ms);
			if (r < 0) setErrno(WinRtCalls.rt_win_sock_errno(W.WSAGetLastError()));
			return r;
		}
		return C.poll(fds, (n : I64), ms);
	}

	// ---- the end of the program

	@:hxmc.noGc public static function exit(code:Int)
		C.exit(code);

	// a message on stderr (ASCII, the runtime's own reports)
	@:hxmc.noGc public static function say(msg:String) {
		var buf = Mem.stack(256);
		var n = msg.length < 256 ? msg.length : 256;
		for (i in 0...n)
			Mem.setI8(buf, i, StringTools.fastCodeAt(msg, i));
		write(buf, n);
	}

	@:hxmc.noGc public static function write(p:Ptr, n:Int) {
		C.fflush(Ptr.nil());
		if (windows()) C._write(2, p, n) else C.write(2, p, (n : I64));
	}

	// decimal digits of v (at most 20) into buf at off; the next offset
	@:hxmc.noGc public static function digits(buf:Ptr, off:Int, v:I64):Int {
		if (v < 0) {
			Mem.setI8(buf, off++, "-".code);
			v = -v;
		}
		var tmp = Mem.stack(32);
		var n = 0;
		do {
			Mem.setI8(tmp, n++, 48 + (v % 10).toInt());
			v = v / 10;
		} while (v != 0);
		while (n > 0)
			Mem.setI8(buf, off++, Mem.getU8(tmp, --n));
		return off;
	}
}

// the C library (libc; Windows: the UCRT and MinGW-w64's pthread_time)
@:hxmc.c @:hxmc.fast private extern class C {
	static function getenv(name:Ptr):Ptr;
	static function __errno_location():Ptr;
	static function __error():Ptr;
	static function _errno():Ptr;
	static function clock_gettime(clock:Int, ts:Ptr):Int;
	static function nanosleep(req:Ptr, rem:Ptr):Int;
	static function sched_yield():Int;
	static function sysconf(name:Int):I64;
	static function mmap(addr:Ptr, len:I64, prot:Int, flags:Int, fd:Int, off:I64):Ptr;
	static function munmap(addr:Ptr, len:I64):Int;
	static function mprotect(addr:Ptr, len:I64, prot:Int):Int;
	static function madvise(addr:Ptr, len:I64, advice:Int):Int;
	static function pthread_mutex_init(m:Ptr, attr:Ptr):Int;
	static function pthread_mutex_destroy(m:Ptr):Int;
	static function pthread_mutex_lock(m:Ptr):Int;
	static function pthread_mutex_trylock(m:Ptr):Int;
	static function pthread_mutex_unlock(m:Ptr):Int;
	static function pthread_condattr_init(a:Ptr):Int;
	static function pthread_condattr_setclock(a:Ptr, clock:Int):Int;
	static function pthread_cond_init(c:Ptr, attr:Ptr):Int;
	static function pthread_cond_destroy(c:Ptr):Int;
	static function pthread_cond_wait(c:Ptr, m:Ptr):Int;
	static function pthread_cond_timedwait(c:Ptr, m:Ptr, ts:Ptr):Int;
	static function pthread_cond_signal(c:Ptr):Int;
	static function pthread_cond_broadcast(c:Ptr):Int;
	static function pthread_attr_init(a:Ptr):Int;
	static function pthread_attr_destroy(a:Ptr):Int;
	static function pthread_attr_setstacksize(a:Ptr, size:I64):Int;
	static function pthread_attr_setstack(a:Ptr, stack:Ptr, size:I64):Int;
	static function pthread_attr_setdetachstate(a:Ptr, state:Int):Int;
	static function pthread_create(t:Ptr, attr:Ptr, entry:Ptr, arg:Ptr):Int;
	static function pthread_join(t:Ptr, ret:Ptr):Int;
	static function poll(fds:Ptr, n:I64, ms:Int):Int;
	static function exit(code:Int):Void;
	static function fflush(f:Ptr):Int;
	static function write(fd:Int, p:Ptr, n:I64):I64;
	static function _write(fd:Int, p:Ptr, n:Int):Int;
}

// Windows (kernel32)
@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") private extern class K {
	static function Sleep(ms:Int):Void;
	static function SwitchToThread():Int;
	static function AcquireSRWLockExclusive(l:Ptr):Void;
	static function TryAcquireSRWLockExclusive(l:Ptr):Int;
	static function ReleaseSRWLockExclusive(l:Ptr):Void;
	static function SleepConditionVariableSRW(c:Ptr, l:Ptr, ms:Int, flags:Int):Int;
	static function WakeConditionVariable(c:Ptr):Void;
	static function WakeAllConditionVariable(c:Ptr):Void;
	static function GetLastError():Int;
	static function CreateThread(sa:Ptr, stack:I64, entry:Ptr, arg:Ptr, flags:Int, id:Ptr):Ptr;
	static function CloseHandle(h:Ptr):Int;
	static function ConvertThreadToFiber(p:Ptr):Ptr;
	static function CreateFiberEx(commit:I64, reserve:I64, flags:Int, entry:Ptr, arg:Ptr):Ptr;
	static function SwitchToFiber(f:Ptr):Void;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("ws2_32") private extern class W {
	static function WSAPoll(fds:Ptr, n:Int, ms:Int):Int;
	static function WSAGetLastError():Int;
}

// hxmc.rt.WinRt's exports (Windows)
@:hxmc.c @:hxmc.fast private extern class WinRtCalls {
	static function rt_win_page_size():I64;
	static function rt_win_reserve(bytes:I64):Ptr;
	static function rt_win_release(p:Ptr, bytes:I64):Void;
	static function rt_win_guard(p:Ptr, bytes:I64):Void;
	static function rt_win_decommit(p:Ptr, bytes:I64):Void;
	static function rt_win_sock_errno(wsa:Int):Int;
}
