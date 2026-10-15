// The runtime of hxmc's programs: threads behind
// hxmc.NativeThread (hxmc/std/hxmc/NativeThread.hx), the base of the hxmc
// sys.thread package (hxmc/std/sys/thread) and of haxe.atomic.
//
// Every Haxe thread is an OS thread (pthreads; Windows: its threads with
// SRW locks and condition variables) and threads run in parallel. The
// per-thread runtime state (stack-map record, shadow stack, allocation
// buffer, exception handlers, current exception) is thread-local (rt.h
// RT_TLS). The collector stops the world: a thread that needs a collection
// sets rt_gc_requested and waits until every other thread is stopped at a
// safepoint (an allocation slow path, rt_safepoint) or in a safe region (a
// blocking native between rt_blocking_enter and rt_blocking_leave, which
// holds no heap pointer outside its root and shadow-stack slots); it then
// scans every thread's roots (rt_threads_scan: their shadow stacks) and remembered set
// (rt_mutators_foreach) and resumes them. The world lock `wl` guards the
// thread list and the collection handshake.
//
// The synchronization primitives (re-entrant mutex, condition variable,
// counting semaphore, thread-local values) are pthread mutexes and
// conditions; their handles are T_NATIVE objects freed by the collector
// (rt_native_new).
#define _GNU_SOURCE
#ifdef __APPLE__
// macOS: the ucontext routines (rt_run_main) need _XOPEN_SOURCE,
// and _DARWIN_C_SOURCE keeps the rest (MAP_ANONYMOUS, ...) visible
#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE
#endif
#include "rt_gc.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int32_t rt_nthreads = 1;
void (*rt_spawn_hook)(void);

static double now_secs(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static void sleep_secs(double seconds) {
	if (seconds <= 0) return;
	struct timespec t;
	t.tv_sec = (time_t)seconds;
	t.tv_nsec = (long)((seconds - (double)t.tv_sec) * 1e9);
	while (nanosleep(&t, &t) != 0 && errno == EINTR) {}
}

int32_t hxmc_NativeThread_park(double timeout);
void hxmc_NativeThread_unpark(int32_t id);
int32_t hxmc_NativeThread_current(void);


// ---- thread-local values (sys.thread.Tls): per thread, a K_PARR object
// indexed by Tls id (a root of the thread record)
static int32_t tls_next;

int32_t hxmc_NativeThread_tlsNew(void) {
	return __atomic_fetch_add(&tls_next, 1, __ATOMIC_RELAXED);
}

static void *tls_get(void **tls, int32_t id) {
	void *a = *tls;
	return a && (uint32_t)id < NSLOTS(a) ? FP(a, id) : NULL;
}

// `tls` is a GC root of the running thread's record (updated by a collection)
static void tls_set(void **tls, int32_t id, void *v) {
	if (id < 0) return;
	void *a = *tls;
	if (!a || (uint32_t)id >= NSLOTS(a)) {
		RT_ROOT(v);
		uint32_t n = a ? NSLOTS(a) * 2 : 8;
		if (n <= (uint32_t)id) n = id + 1;
		void *na = rt_alloc(n, T_ADATA_P, K_PARR);
		a = *tls;
		if (a)
			for (uint32_t i = 0; i < NSLOTS(a); i++) rt_set_ptr(na, &FP(na, i), FP(a, i));
		*tls = na;
		a = na;
		RT_RELOAD(v);
		RT_UNROOT(1);
	}
	rt_set_ptr(a, &FP(a, id), v);
}

// (the haxe.atomic cells, hxmc.NativeAtomic: hxmc/std/hxmc/rt/Atomics.hx)


#ifdef _WIN32
// Windows: the subset of pthreads used below over slim reader/writer locks,
// condition variables and CreateThread; poll is WSAPoll (sockets only); the
// stacks are reservations (rt_win.h)
#include "rt_win.h"
typedef SRWLOCK pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef int pthread_condattr_t;
#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
#define PTHREAD_COND_INITIALIZER CONDITION_VARIABLE_INIT
#define pthread_mutex_init(m, a) InitializeSRWLock(m)
#define pthread_mutex_destroy(m) ((void)(m))
#define pthread_mutex_lock(m) AcquireSRWLockExclusive(m)
#define pthread_mutex_trylock(m) (TryAcquireSRWLockExclusive(m) ? 0 : EBUSY)
#define pthread_mutex_unlock(m) ReleaseSRWLockExclusive(m)
#define pthread_condattr_init(a) ((void)(a))
#define pthread_condattr_setclock(a, c) ((void)(a))
#define pthread_cond_init(c, a) InitializeConditionVariable(c)
#define pthread_cond_destroy(c) ((void)(c))
#define pthread_cond_signal(c) WakeConditionVariable(c)
#define pthread_cond_broadcast(c) WakeAllConditionVariable(c)
#define pthread_cond_wait(c, m) (SleepConditionVariableSRW((c), (m), INFINITE, 0) ? 0 : EINVAL)
// the deadline is on CLOCK_MONOTONIC (deadline_ts)
static int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *ts) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	double left = (double)(ts->tv_sec - now.tv_sec) + (double)(ts->tv_nsec - now.tv_nsec) * 1e-9;
	DWORD ms = left <= 0 ? 0 : left > 4e6 ? 4000000000u : (DWORD)(left * 1000.0 + 0.999);
	if (SleepConditionVariableSRW(c, m, ms, 0)) return 0;
	return GetLastError() == ERROR_TIMEOUT ? ETIMEDOUT : EINVAL;
}
#define sched_yield() SwitchToThread()
static int win_poll(struct pollfd *fds, int n, int ms) {
	int r = WSAPoll(fds, (ULONG)n, ms);
	if (r < 0) errno = rt_win_sock_errno(WSAGetLastError());
	return r;
}
#define poll(fds, n, ms) win_poll((fds), (n), (ms))
void rt_win_lock(rt_lock_t *l) { AcquireSRWLockExclusive((SRWLOCK *)l); }
void rt_win_unlock(rt_lock_t *l) { ReleaseSRWLockExclusive((SRWLOCK *)l); }
#else
#include <poll.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>
#endif

#define CSTACK_BYTES ((size_t)64 << 20) // reserved, committed as touched
#define SSTACK_BYTES ((size_t)64 << 20) // shadow stack (the main thread's is 1 GB, rt.c)

static void *map_stack(size_t bytes) {
	void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
	return p == MAP_FAILED ? NULL : p;
}


// ======== OS threads (1:1)

#ifndef _WIN32
#include <sched.h>
#endif

enum { TS_RUNNING, TS_SAFE }; // TS_SAFE: in a safe region or stopped at a safepoint

typedef struct rt_thread {
	rt_mutator mut; // bound when the thread starts (refs to its TLS variables)
	int32_t id;
	int state; // atomic
	int started; // the mutator is bound (under wl)
	void *job; // the entry closure until the thread starts (a GC root)
	void *tls; // Tls values (a GC root)
	void **sbase; // shadow stack mapping (the main thread's is rt.c's)
	struct parker *pk; // park/unpark (never freed: an unpark may find it after the thread ended)
	struct rt_thread *next, *prev; // live threads
} rt_thread;

typedef struct parker {
	pthread_mutex_t m;
	pthread_cond_t c;
	int permit;
} parker;

int rt_mt; // a second thread was started (rt.h rt_lock)
volatile int rt_gc_requested;
static pthread_mutex_t wl = PTHREAD_MUTEX_INITIALIZER; // the world lock
static pthread_cond_t wl_stopped = PTHREAD_COND_INITIALIZER; // a thread became safe (the collector waits)
static pthread_cond_t wl_resumed = PTHREAD_COND_INITIALIZER; // a collection ended
static rt_thread main_thread;
static rt_thread *all_threads; // under wl
static rt_thread **by_id; // under wl
static int32_t by_id_cap, next_id = 2;
static rt_mutator dead_mut; // remembered sets of threads that ended (under wl)
static RT_TLS rt_thread *self;
// dead_mut's remembered set has no TLAB or stack: its refs point here
static void **dead_sp, **dead_hw, **dead_base;
static void *dead_exn;
static char *dead_yptr, *dead_ylim, *dead_yrlim;

static pthread_condattr_t mono_attr; // conditions waiting on CLOCK_MONOTONIC (CLOCK_REALTIME on macOS)

// RT_STATS: threads started, contended mutex acquisitions and their waits,
// collections and the time from a request until every thread had stopped
static int thr_stats;
static unsigned long st_spawned, st_contended, st_stw, st_stw_max_us;
static double st_contended_secs, st_stw_secs;
static void thr_report(void) {
	fprintf(stderr, "threads: %lu started; %lu contended mutex acquisitions (%.3fs waiting); %lu stops of the world, %.3fs until stopped (max %lu us)\n",
		st_spawned, st_contended, st_contended_secs, st_stw, st_stw_secs, st_stw_max_us);
}


int32_t hxmc_NativeThread_parallel(void) { return 1; }

static void cond_init(pthread_cond_t *c) { pthread_cond_init(c, &mono_attr); }

static parker *new_parker(void) {
	parker *p = (parker *)calloc(1, sizeof(parker));
	pthread_mutex_init(&p->m, NULL);
	cond_init(&p->c);
	return p;
}

void rt_threads_init(void) {
	pthread_condattr_init(&mono_attr);
#ifndef __APPLE__
	pthread_condattr_setclock(&mono_attr, CLOCK_MONOTONIC);
#endif
	main_thread.id = 1;
	main_thread.state = TS_RUNNING;
	main_thread.started = 1;
	main_thread.pk = new_parker();
	dead_mut.sp_ref = &dead_sp;
	dead_mut.hw_ref = &dead_hw;
	dead_mut.base_ref = &dead_base;
	dead_mut.exn_ref = &dead_exn;
	dead_mut.yptr_ref = &dead_yptr;
	dead_mut.ylim_ref = &dead_ylim;
	dead_mut.yrlim_ref = &dead_yrlim;
	rt_mutator_bind(&main_thread.mut);
	all_threads = &main_thread;
	by_id_cap = 64;
	by_id = (rt_thread **)calloc(by_id_cap, sizeof(rt_thread *));
	by_id[1] = &main_thread;
	self = &main_thread;
	thr_stats = getenv("RT_STATS") != NULL;
	if (thr_stats) atexit(thr_report);
}

static int get_state(rt_thread *t) { return __atomic_load_n(&t->state, __ATOMIC_SEQ_CST); }
static void set_state(rt_thread *t, int s) { __atomic_store_n(&t->state, s, __ATOMIC_SEQ_CST); }
static int gc_requested(void) { return __atomic_load_n(&rt_gc_requested, __ATOMIC_SEQ_CST); }

// under wl, while a collection is requested: stopped until it ends
static void stop_here(void) {
	set_state(self, TS_SAFE);
	pthread_cond_broadcast(&wl_stopped);
	while (gc_requested()) pthread_cond_wait(&wl_resumed, &wl);
	set_state(self, TS_RUNNING);
}

int rt_world_stop(void) {
	double t0 = thr_stats ? now_secs() : 0;
	pthread_mutex_lock(&wl);
	if (gc_requested()) { // another thread is collecting: wait for it as at a safepoint
		stop_here();
		pthread_mutex_unlock(&wl);
		return 0;
	}
	__atomic_store_n(&rt_gc_requested, 1, __ATOMIC_SEQ_CST);
	for (;;) {
		int all = 1;
		for (rt_thread *t = all_threads; t; t = t->next)
			if (t != self && get_state(t) == TS_RUNNING) {
				all = 0;
				break;
			}
		if (all) break;
		pthread_cond_wait(&wl_stopped, &wl);
	}
	if (thr_stats && all_threads->next) {
		double d = now_secs() - t0;
		st_stw++;
		st_stw_secs += d;
		if (d * 1e6 > st_stw_max_us) st_stw_max_us = (unsigned long)(d * 1e6);
	}
	return 1; // wl stays held during the collection
}

void rt_world_resume(void) {
	__atomic_store_n(&rt_gc_requested, 0, __ATOMIC_SEQ_CST);
	pthread_cond_broadcast(&wl_resumed);
	pthread_mutex_unlock(&wl);
}

void rt_safepoint_slow(void) {
	pthread_mutex_lock(&wl);
	if (gc_requested()) stop_here();
	pthread_mutex_unlock(&wl);
}

// Entering a safe region publishes the thread's state (seq_cst): a collector
// that set rt_gc_requested before this thread looked sees TS_SAFE, else this
// thread sees the request and wakes the collector.
// Both keep errno (natives read it after their blocking call).
void rt_blocking_enter(void) {
	set_state(self, TS_SAFE);
	if (gc_requested()) {
		int e = errno;
		pthread_mutex_lock(&wl);
		pthread_cond_broadcast(&wl_stopped);
		pthread_mutex_unlock(&wl);
		errno = e;
	}
}

void rt_blocking_leave(void) {
	set_state(self, TS_RUNNING);
	if (gc_requested()) {
		int e = errno;
		pthread_mutex_lock(&wl);
		if (gc_requested()) stop_here();
		pthread_mutex_unlock(&wl);
		errno = e;
	}
}

// Takes a mutex that a thread may hold while it leaves a safe region (and so
// waits for a collection): a thread blocked on it must be in a safe region.
static void lock_safe(pthread_mutex_t *m) {
	if (pthread_mutex_trylock(m) == 0) return;
	rt_blocking_enter();
	pthread_mutex_lock(m);
	rt_blocking_leave();
}

// under wl (a collection): every started thread, and the remembered sets of
// the threads that ended
void rt_mutators_foreach(void (*f)(rt_mutator *, void *), void *arg) {
	for (rt_thread *t = all_threads; t; t = t->next)
		if (t->started) f(&t->mut, arg);
	f(&dead_mut, arg);
}

void rt_threads_scan(void *(*fwd)(void *)) {
	for (rt_thread *t = all_threads; t; t = t->next) {
		if (t->job) t->job = fwd(t->job);
		if (t->tls) t->tls = fwd(t->tls);
		if (t == self || !t->started) continue; // the collector's own stack and rt_exn: rt.c
		void **sp = *t->mut.sp_ref;
		for (void **s = *t->mut.base_ref; s < sp; s++)
			if (*s) *s = fwd(*s);
		if (*t->mut.exn_ref) *t->mut.exn_ref = fwd(*t->mut.exn_ref);
	}
}


static void thread_exit(void) {
	rt_thread *t = self;
	rt_blocking_enter(); // touches no heap object from here on
	pthread_mutex_lock(&wl);
	if (t->prev) t->prev->next = t->next;
	else all_threads = t->next;
	if (t->next) t->next->prev = t->prev;
	by_id[t->id] = NULL;
	// its old-to-young slots stay remembered until the next minor collection
	rt_mutator *m = &t->mut;
	if (m->rem_len) {
		if (dead_mut.rem_len + m->rem_len > dead_mut.rem_cap) {
			dead_mut.rem_cap = (dead_mut.rem_len + m->rem_len) * 2;
			dead_mut.rem = (void ***)realloc(dead_mut.rem, dead_mut.rem_cap * sizeof(void **));
		}
		memcpy(dead_mut.rem + dead_mut.rem_len, m->rem, m->rem_len * sizeof(void **));
		dead_mut.rem_len += m->rem_len;
	}
	if (m->robjs_len) {
		if (dead_mut.robjs_len + m->robjs_len > dead_mut.robjs_cap) {
			dead_mut.robjs_cap = (dead_mut.robjs_len + m->robjs_len) * 2;
			dead_mut.robjs = (void **)realloc(dead_mut.robjs, dead_mut.robjs_cap * sizeof(void *));
		}
		memcpy(dead_mut.robjs + dead_mut.robjs_len, m->robjs, m->robjs_len * sizeof(void *));
		dead_mut.robjs_len += m->robjs_len;
	}
	__atomic_fetch_sub(&rt_nthreads, 1, __ATOMIC_SEQ_CST);
	pthread_mutex_unlock(&wl);
	free(m->rem);
	free(m->robjs);
	rt_dyn_thread_exit();
	munmap(t->sbase, SSTACK_BYTES);
	free(t);
}

static void *thread_start(void *arg) {
	rt_thread *t = (rt_thread *)arg;
	self = t;
	rt_sp = rt_stack_base = rt_sp_hw = t->sbase;
	rt_young_ptr = rt_young_limit = rt_young_rlimit = NULL;
	rt_hcur = NULL;
	rt_exn = NULL;
	pthread_mutex_lock(&wl); // no collection runs: bind the mutator (the thread is safe until it leaves)
	rt_mutator_bind(&t->mut);
	t->started = 1;
	pthread_mutex_unlock(&wl);
	rt_blocking_leave();
	void **job = rt_push(1);
	*job = t->job;
	t->job = NULL;
	RT_TRY(h)
		hx_dyn_call(*job, NULL);
	RT_CATCH(h)
		// the hxmc sys.thread.Thread catches everything: only a raw spawn gets here
		void *e = rt_exn;
		rt_exn = 0;
		char *s = hx_str_to_utf8(hx_std_string(e));
		fflush(stdout);
		fprintf(stderr, "Uncaught exception in thread %d: %s\n", (int)t->id, s);
		free(s);
	RT_END_TRY(h)
	thread_exit();
	return NULL;
}

#ifdef _WIN32
static DWORD WINAPI win_thread_start(void *arg) {
	thread_start(arg);
	return 0;
}
#endif

int32_t hxmc_NativeThread_spawn(void *job) {
	rt_thread *t = (rt_thread *)calloc(1, sizeof(rt_thread));
	if (t) t->sbase = (void **)map_stack(SSTACK_BYTES);
	if (!t || !t->sbase) {
		free(t);
		hx_throw_str("cannot allocate the stacks of a new thread");
	}
	t->state = TS_SAFE;
	t->pk = new_parker();
	// no safepoint from here to the insertion: `job` is not rooted
	pthread_mutex_lock(&wl);
	t->job = job;
	t->id = next_id++;
	if (t->id >= by_id_cap) {
		int32_t n = by_id_cap * 2;
		while (n <= t->id) n *= 2;
		by_id = (rt_thread **)realloc(by_id, n * sizeof(rt_thread *));
		memset(by_id + by_id_cap, 0, (n - by_id_cap) * sizeof(rt_thread *));
		by_id_cap = n;
	}
	by_id[t->id] = t;
	t->next = all_threads;
	all_threads->prev = t;
	all_threads = t;
	__atomic_fetch_add(&rt_nthreads, 1, __ATOMIC_SEQ_CST);
	st_spawned++;
	rt_mt = 1;
	int32_t id = t->id;
	pthread_mutex_unlock(&wl);
#ifdef _WIN32
	// the C stack reserved (committed as it grows); the thread is not joined
	HANDLE th = CreateThread(NULL, CSTACK_BYTES, win_thread_start, t, STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
	int r = th == NULL;
	if (th) CloseHandle(th);
#else
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setstacksize(&attr, CSTACK_BYTES);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
	pthread_t pt;
	int r = pthread_create(&pt, &attr, thread_start, t);
	pthread_attr_destroy(&attr);
#endif
	if (r != 0) {
		// never started: take it out again (it is safe, its job a root until now)
		pthread_mutex_lock(&wl);
		if (t->prev) t->prev->next = t->next;
		else all_threads = t->next;
		if (t->next) t->next->prev = t->prev;
		by_id[t->id] = NULL;
		__atomic_fetch_sub(&rt_nthreads, 1, __ATOMIC_SEQ_CST);
		pthread_mutex_unlock(&wl);
		munmap(t->sbase, SSTACK_BYTES);
		free(t);
		hx_throw_str("cannot start a new thread");
	}
	if (rt_spawn_hook) rt_spawn_hook();
	return id;
}

int32_t hxmc_NativeThread_current(void) { return self->id; }

int32_t hxmc_NativeThread_count(void) { return __atomic_load_n(&rt_nthreads, __ATOMIC_RELAXED); }

void *hxmc_NativeThread_tlsGet(int32_t id) { return tls_get(&self->tls, id); }
void hxmc_NativeThread_tlsSet(int32_t id, void *v) { tls_set(&self->tls, id, v); }

static void deadline_ts(struct timespec *ts, double timeout) {
#ifdef __APPLE__
	clock_gettime(CLOCK_REALTIME, ts); // macOS: no pthread_condattr_setclock, conditions wait on the real-time clock
#else
	clock_gettime(CLOCK_MONOTONIC, ts);
#endif
	double s = (double)ts->tv_sec + (double)ts->tv_nsec * 1e-9 + timeout;
	ts->tv_sec = (time_t)s;
	ts->tv_nsec = (long)((s - (double)ts->tv_sec) * 1e9);
	if (ts->tv_nsec >= 1000000000L) {
		ts->tv_sec++;
		ts->tv_nsec -= 1000000000L;
	}
}

// waits on c (m held), in a safe region: 0 timed out
static int cond_wait_safe(pthread_cond_t *c, pthread_mutex_t *m, int timed, const struct timespec *ts) {
	rt_blocking_enter();
	int r = timed ? pthread_cond_timedwait(c, m, ts) : pthread_cond_wait(c, m);
	rt_blocking_leave();
	return r != ETIMEDOUT;
}

// blocks until unparked (1) or timeout seconds pass (0); timeout < 0: no
// timeout. An unpark of a thread that is not parked makes its next park
// return at once.
int32_t hxmc_NativeThread_park(double timeout) {
	parker *p = self->pk;
	struct timespec ts;
	if (timeout >= 0) deadline_ts(&ts, timeout);
	lock_safe(&p->m);
	int woken = 1;
	while (!p->permit) {
		if (!cond_wait_safe(&p->c, &p->m, timeout >= 0, &ts)) {
			woken = p->permit;
			break;
		}
	}
	p->permit = 0;
	pthread_mutex_unlock(&p->m);
	return woken;
}

void hxmc_NativeThread_unpark(int32_t id) {
	pthread_mutex_lock(&wl);
	rt_thread *t = id > 0 && id < by_id_cap ? by_id[id] : NULL;
	parker *p = t ? t->pk : NULL;
	pthread_mutex_unlock(&wl);
	if (!p) return;
	lock_safe(&p->m);
	p->permit = 1;
	pthread_cond_signal(&p->c);
	pthread_mutex_unlock(&p->m);
}

void hxmc_NativeThread_yield(void) {
	rt_safepoint();
	sched_yield();
}

void rt_preempt(void) { rt_safepoint(); }

void rt_sleep(double seconds) {
	if (seconds <= 0) {
		hxmc_NativeThread_yield();
		return;
	}
	RT_BLOCKING(sleep_secs(seconds));
}

// per descriptor (below FD_GENS): incremented by rt_fd_closed; a thread
// waiting for a descriptor looks at it every POLL_SLICE seconds, so a close
// by another thread makes its wait fail (EBADF)
#define FD_GENS 4096
#define POLL_SLICE 0.1
static uint32_t fd_gens[FD_GENS];

static uint32_t fd_gen(int fd) { return fd >= 0 && fd < FD_GENS ? __atomic_load_n(&fd_gens[fd], __ATOMIC_RELAXED) : 0; }

void rt_fd_closed(int fd) {
	if (fd >= 0 && fd < FD_GENS) __atomic_fetch_add(&fd_gens[fd], 1, __ATOMIC_RELAXED);
}

int rt_wait_fds(void *pollfds, int n, double timeout) {
	struct pollfd *fds = (struct pollfd *)pollfds;
	for (int i = 0; i < n; i++) fds[i].revents = 0;
	int r = poll(fds, n, 0);
	if (r != 0 || timeout == 0) return r != 0; // a poll failure: let the caller's own call report it
	uint32_t gens_buf[8];
	uint32_t *gens = n <= 8 ? gens_buf : (uint32_t *)malloc(n * sizeof(uint32_t));
	for (int i = 0; i < n; i++) gens[i] = fd_gen(fds[i].fd);
	double deadline = timeout < 0 ? -1 : now_secs() + timeout;
	int result = 0, closed = 0;
	rt_blocking_enter();
	for (;;) {
		double slice = POLL_SLICE;
		if (deadline >= 0) {
			double left = deadline - now_secs();
			if (left <= 0) break;
			if (left < slice) slice = left;
		}
		r = poll(fds, n, (int)(slice * 1000.0 + 0.999));
		for (int i = 0; i < n; i++)
			if (fd_gen(fds[i].fd) != gens[i]) closed = 1;
		if (closed) break;
		if (r != 0) {
			if (r > 0 || errno != EINTR) {
				result = 1;
				break;
			}
		}
	}
	rt_blocking_leave();
	if (gens != gens_buf) free(gens);
	if (closed) {
		errno = EBADF;
		return -1;
	}
	return result;
}

// ---- synchronization: pthread mutexes and conditions. Their mutexes are
// taken with lock_safe (a holder may wait for a collection when it leaves a
// wait), waits are safe regions; handles are rooted while their thread waits.

typedef struct {
	pthread_mutex_t m;
	rt_thread *owner; // atomic: compared with self without the lock
	int depth;
} hx_mutex;

typedef struct {
	pthread_cond_t c;
} hx_cond;

typedef struct {
	pthread_mutex_t m;
	pthread_cond_t c;
	int32_t count;
} hx_sem;

static void free_mutex(void *p) {
	pthread_mutex_destroy(&((hx_mutex *)p)->m);
	free(p);
}

static void free_cond(void *p) {
	pthread_cond_destroy(&((hx_cond *)p)->c);
	free(p);
}

static void free_sem(void *p) {
	pthread_mutex_destroy(&((hx_sem *)p)->m);
	pthread_cond_destroy(&((hx_sem *)p)->c);
	free(p);
}

static rt_thread *owner_of(hx_mutex *m) { return __atomic_load_n(&m->owner, __ATOMIC_RELAXED); }

void *hxmc_NativeThread_mutexNew(void) {
	hx_mutex *m = (hx_mutex *)calloc(1, sizeof(hx_mutex));
	pthread_mutex_init(&m->m, NULL);
	return rt_native_new(m, free_mutex);
}

void hxmc_NativeThread_mutexAcquire(void *mo) {
	hx_mutex *m = (hx_mutex *)FP(mo, 0);
	if (owner_of(m) == self) {
		m->depth++;
		return;
	}
	if (pthread_mutex_trylock(&m->m) != 0) {
		RT_ROOT(mo); // the handle stays alive while this thread waits
		double t0 = thr_stats ? now_secs() : 0;
		rt_blocking_enter();
		pthread_mutex_lock(&m->m);
		rt_blocking_leave();
		if (thr_stats) {
			__atomic_fetch_add(&st_contended, 1, __ATOMIC_RELAXED);
			st_contended_secs += now_secs() - t0; // under the mutex just taken: approximate across mutexes
		}
		RT_UNROOT(1);
	}
	__atomic_store_n(&m->owner, self, __ATOMIC_RELAXED);
	m->depth = 1;
}

int32_t hxmc_NativeThread_mutexTryAcquire(void *mo) {
	hx_mutex *m = (hx_mutex *)FP(mo, 0);
	if (owner_of(m) == self) {
		m->depth++;
		return 1;
	}
	if (pthread_mutex_trylock(&m->m) != 0) return 0;
	__atomic_store_n(&m->owner, self, __ATOMIC_RELAXED);
	m->depth = 1;
	return 1;
}

void hxmc_NativeThread_mutexRelease(void *mo) {
	hx_mutex *m = (hx_mutex *)FP(mo, 0);
	if (owner_of(m) != self) return;
	if (--m->depth > 0) return;
	__atomic_store_n(&m->owner, NULL, __ATOMIC_RELAXED);
	pthread_mutex_unlock(&m->m);
}

void *hxmc_NativeThread_condNew(void) {
	hx_cond *c = (hx_cond *)calloc(1, sizeof(hx_cond));
	cond_init(&c->c);
	return rt_native_new(c, free_cond);
}

// waits for a signal (1) or until timeout seconds pass (0; < 0: no timeout);
// the calling thread holds mutex m, which is released meanwhile (fully) and
// taken back at the same depth. May wake spuriously (as pthread conditions).
int32_t hxmc_NativeThread_condWait(void *co, void *mo, double timeout) {
	hx_cond *c = (hx_cond *)FP(co, 0);
	hx_mutex *m = (hx_mutex *)FP(mo, 0);
	if (owner_of(m) != self) hx_throw_str("Condition.wait: the mutex is not held");
	struct timespec ts;
	if (timeout >= 0) deadline_ts(&ts, timeout);
	RT_ROOT(co);
	RT_ROOT(mo);
	int depth = m->depth;
	__atomic_store_n(&m->owner, NULL, __ATOMIC_RELAXED);
	int r = cond_wait_safe(&c->c, &m->m, timeout >= 0, &ts);
	__atomic_store_n(&m->owner, self, __ATOMIC_RELAXED);
	m->depth = depth;
	RT_UNROOT(2);
	return r;
}

void hxmc_NativeThread_condSignal(void *co) { pthread_cond_signal(&((hx_cond *)FP(co, 0))->c); }
void hxmc_NativeThread_condBroadcast(void *co) { pthread_cond_broadcast(&((hx_cond *)FP(co, 0))->c); }

void *hxmc_NativeThread_semNew(int32_t value) {
	hx_sem *s = (hx_sem *)calloc(1, sizeof(hx_sem));
	pthread_mutex_init(&s->m, NULL);
	cond_init(&s->c);
	s->count = value;
	return rt_native_new(s, free_sem);
}

// takes a unit (1), or times out (0) after timeout seconds (0: just try; < 0: no timeout)
int32_t hxmc_NativeThread_semAcquire(void *so, double timeout) {
	hx_sem *s = (hx_sem *)FP(so, 0);
	struct timespec ts;
	if (timeout > 0) deadline_ts(&ts, timeout);
	RT_ROOT(so);
	lock_safe(&s->m);
	int r = 1;
	while (s->count == 0) {
		if (timeout == 0 || !cond_wait_safe(&s->c, &s->m, timeout > 0, &ts)) {
			r = s->count > 0;
			break;
		}
	}
	if (r) s->count--;
	pthread_mutex_unlock(&s->m);
	RT_UNROOT(1);
	return r;
}

void hxmc_NativeThread_semRelease(void *so) {
	hx_sem *s = (hx_sem *)FP(so, 0);
	RT_ROOT(so);
	lock_safe(&s->m);
	s->count++;
	pthread_cond_signal(&s->c);
	pthread_mutex_unlock(&s->m);
	RT_UNROOT(1);
}


int rt_wait_fd(int fd, int write, double timeout) {
	struct pollfd p;
	p.fd = fd;
	p.events = write ? POLLOUT : POLLIN;
	p.revents = 0;
	return rt_wait_fds(&p, 1, timeout);
}

// The program's main runs on a reserved stack of RT_STACK_MB (default 1024)
// MB, committed as touched, with a guard page: OCaml 5, which the reference
// compiler is built with, lets the main fiber's stack grow to 1 GB, and deep
// recursion in the port (the typer, Eval-interpreted code, the hxmc regular
// expression engine) needs more than the default 8 MB process stack.
#if defined(_WIN32)
// Windows: main runs on a fiber of the main thread, whose stack is reserved
// at that size (committed as it grows, with the system's guard page)
static void *run_main_fiber;
static void (*run_main_body)(void);
static void WINAPI run_main_entry(void *arg) {
	(void)arg;
	run_main_body();
	SwitchToFiber(run_main_fiber);
}
#elif defined(__APPLE__) && defined(__aarch64__) || defined(RT_CALL_ON_STACK)
// macOS on arm64 has no working ucontext (getcontext fails), nor has musl
// (hxmc's static Linux builds define RT_CALL_ON_STACK): rt_call_on_stack
// calls fn on the stack below top, then returns on the caller's stack
void rt_call_on_stack(void *top, void (*fn)(void));
#if !defined(__APPLE__) && defined(__x86_64__)
__asm__(".text\n"
	".p2align 4\n"
	".hidden rt_call_on_stack\n"
	".globl rt_call_on_stack\n"
	"rt_call_on_stack:\n"
	"	push %rbp\n"
	"	mov %rsp, %rbp\n"
	"	mov %rdi, %rsp\n"
	"	call *%rsi\n"
	"	mov %rbp, %rsp\n"
	"	pop %rbp\n"
	"	ret\n");
#elif !defined(__APPLE__) && defined(__aarch64__)
__asm__(".text\n"
	".p2align 2\n"
	".hidden rt_call_on_stack\n"
	".globl rt_call_on_stack\n"
	"rt_call_on_stack:\n"
	"	stp x29, x30, [sp, #-16]!\n"
	"	mov x29, sp\n"
	"	mov sp, x0\n"
	"	blr x1\n"
	"	mov sp, x29\n"
	"	ldp x29, x30, [sp], #16\n"
	"	ret\n");
#else
__asm__(".text\n"
	".p2align 2\n"
	".private_extern _rt_call_on_stack\n"
	".globl _rt_call_on_stack\n"
	"_rt_call_on_stack:\n"
	"	stp x29, x30, [sp, #-16]!\n"
	"	mov x29, sp\n"
	"	mov sp, x0\n"
	"	blr x1\n"
	"	mov sp, x29\n"
	"	ldp x29, x30, [sp], #16\n"
	"	ret\n");
#endif
#else
static ucontext_t run_main_ret, run_main_ctx;
static void (*run_main_body)(void);
static void run_main_entry(void) { run_main_body(); }
#endif

void rt_run_main(void (*body)(void)) {
	const char *e = getenv("RT_STACK_MB");
	int mb = 1024;
	size_t bytes = (size_t)(e ? atoi(e) : mb) << 20;
#ifdef _WIN32
	void *fiber = NULL;
	if (bytes) {
		run_main_body = body;
		run_main_fiber = ConvertThreadToFiber(NULL);
		if (run_main_fiber) fiber = CreateFiberEx(64 << 10, bytes, FIBER_FLAG_FLOAT_SWITCH, run_main_entry, NULL);
	}
	if (!fiber) {
		body();
		return;
	}
	SwitchToFiber(fiber);
#else
	char *stack = bytes ? (char *)map_stack(bytes) : NULL;
	if (!stack) {
		body();
		return;
	}
	mprotect(stack, (size_t)sysconf(_SC_PAGESIZE), PROT_NONE);
#if defined(__APPLE__) && defined(__aarch64__) || defined(RT_CALL_ON_STACK)
	rt_call_on_stack(stack + bytes, body);
#else
	run_main_body = body;
	getcontext(&run_main_ctx);
	run_main_ctx.uc_stack.ss_sp = stack;
	run_main_ctx.uc_stack.ss_size = bytes;
	run_main_ctx.uc_link = &run_main_ret;
	makecontext(&run_main_ctx, run_main_entry, 0);
	swapcontext(&run_main_ret, &run_main_ctx);
#endif
#endif
}

