// EXPERIMENTAL runtime for the C output of backend/: green threads behind
// hxc.NativeThread (backend/std-hxc/hxc/NativeThread.hx), the base of the hxc
// sys.thread package (backend/std-hxc/sys/thread).
//
// M:1 cooperative threads: every Haxe thread runs on the one OS thread, and a
// thread only gives way at a blocking point (park, sleep, yield, waiting for a
// file descriptor). Only one thread runs at a time, so the GC and the runtime
// tables need no locks. Each thread has its own C stack (ucontext), shadow
// stack and exception handler chain; a switch saves the globals rt_sp,
// rt_stack_base, rt_hcur and rt_exn into the thread record and loads the next
// thread's, so the single-threaded hot paths are unchanged.
//
// When no thread can run, the scheduler waits in poll() over the descriptors
// threads wait for, up to the nearest timer deadline. If no thread can ever be
// woken again (every thread parked without a deadline or descriptor), the
// program reports the deadlock and exits.
//
// Under __EMSCRIPTEN__ (the wasm playground) there are no threads: spawn
// throws, and waiting forever throws instead of blocking.
#define _GNU_SOURCE
#include "rt.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int32_t rt_nthreads = 1;

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

#ifdef __EMSCRIPTEN__

void rt_threads_scan(void *(*fwd)(void *)) { (void)fwd; }
int rt_wait_fd(int fd, int write, double timeout) { return 1; }
int rt_wait_fds(void *pollfds, int n, double timeout) { return 1; }
void rt_sleep(double seconds) { sleep_secs(seconds); }
void rt_preempt(void) {}
void rt_fd_closed(int fd) { (void)fd; }
int32_t hxc_NativeThread_spawn(void *job) { hx_throw_str("threads are not supported in this build of haxe-in-haxe"); }
int32_t hxc_NativeThread_current(void) { return 1; }
int32_t hxc_NativeThread_count(void) { return 1; }
int32_t hxc_NativeThread_park(double timeout) {
	if (timeout < 0) hx_throw_str("this wait would block forever (threads are not supported in this build)");
	sleep_secs(timeout);
	return 0;
}
void hxc_NativeThread_unpark(int32_t id) { (void)id; }
void hxc_NativeThread_yield(void) {}

#else

#include <poll.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

#define CSTACK_BYTES ((size_t)64 << 20) // reserved, committed as touched
#define SSTACK_BYTES ((size_t)64 << 20) // shadow stack (the main thread's is 128 MB)

enum { TS_RUNNING, TS_RUNNABLE, TS_PARKED, TS_DONE };

typedef struct rt_thread {
	int32_t id;
	int state;
	int woken; // result of a park: 1 unparked or descriptor ready, 0 timeout
	int unparkable; // parked in hxc_NativeThread_park (not sleeping or waiting for a descriptor)
	ucontext_t ctx;
	char *cstack; // NULL for the main thread (it runs on the process stack)
	void **sbase, **sp; // shadow stack (saved while not running)
	rt_handler *hcur;
	void *exn;
	void *job; // the entry closure until the thread starts (a GC root)
	double deadline; // parked: wake at this time (now_secs), < 0: no deadline
	struct pollfd *fds; // parked on descriptors (on the thread's C stack)
	int nfds;
	struct rt_thread *next; // run queue
	struct rt_thread *all_next, *all_prev; // live threads
} rt_thread;

static rt_thread main_thread;
static rt_thread *cur; // NULL until the first thread operation
static rt_thread *runq_head, *runq_tail;
static rt_thread *all_threads;
static rt_thread **by_id;
static int32_t by_id_cap, next_id = 2;
static rt_thread *zombies; // finished threads whose stacks are freed after switching away
static size_t page_size;

// per descriptor: incremented by rt_fd_closed, so a thread woken after its
// descriptor was closed (and the number maybe reused) does not touch it
static uint32_t *fd_gens;
static int fd_gens_cap;

static uint32_t fd_gen(int fd) { return fd >= 0 && fd < fd_gens_cap ? fd_gens[fd] : 0; }

static void ensure_init(void) {
	if (cur) return;
	page_size = (size_t)sysconf(_SC_PAGESIZE);
	main_thread.id = 1;
	main_thread.state = TS_RUNNING;
	main_thread.deadline = -1;
	all_threads = &main_thread;
	by_id_cap = 64;
	by_id = (rt_thread **)calloc(by_id_cap, sizeof(rt_thread *));
	by_id[1] = &main_thread;
	cur = &main_thread;
}

static void enqueue(rt_thread *t) {
	t->state = TS_RUNNABLE;
	t->next = NULL;
	if (runq_tail) runq_tail->next = t;
	else runq_head = t;
	runq_tail = t;
}

static void wake(rt_thread *t, int woken) {
	t->woken = woken;
	enqueue(t);
}

void rt_fd_closed(int fd) {
	if (fd < 0 || cur == NULL) return; // no thread was ever created: nobody waits
	if (fd >= fd_gens_cap) {
		int n = fd_gens_cap ? fd_gens_cap : 256;
		while (n <= fd) n *= 2;
		fd_gens = (uint32_t *)realloc(fd_gens, n * sizeof(uint32_t));
		memset(fd_gens + fd_gens_cap, 0, (n - fd_gens_cap) * sizeof(uint32_t));
		fd_gens_cap = n;
	}
	fd_gens[fd]++;
	// threads parked on it wake now (their poll would watch whatever reuses the number)
	for (rt_thread *t = all_threads; t; t = t->all_next)
		if (t->state == TS_PARKED)
			for (int i = 0; i < t->nfds; i++)
				if (t->fds[i].fd == fd) {
					t->fds[i].revents = POLLNVAL;
					wake(t, 1);
					break;
				}
}

void rt_threads_scan(void *(*fwd)(void *)) {
	for (rt_thread *t = all_threads; t; t = t->all_next) {
		if (t->job) t->job = fwd(t->job);
		if (t == cur) continue; // its stack and rt_exn are the globals rt.c scans
		for (void **s = t->sbase; s < t->sp; s++)
			if (*s) *s = fwd(*s);
		if (t->exn) t->exn = fwd(t->exn);
	}
}

static void reap(void) {
	rt_thread **p = &zombies;
	while (*p) {
		rt_thread *z = *p;
		if (z == cur) {
			p = &z->next;
			continue;
		}
		*p = z->next;
		munmap(z->cstack, CSTACK_BYTES);
		munmap(z->sbase, SSTACK_BYTES);
		free(z);
	}
}

// Waits for the descriptors and timers of parked threads, waking those whose
// event came. block: wait until at least one thread wakes (else just look).
// Returns 0 when no parked thread can ever be woken by an event.
static struct pollfd *poll_buf;
static int poll_cap;

static int wait_events(int block) {
	int nf = 0, any = 0;
	double nearest = -1;
	for (rt_thread *t = all_threads; t; t = t->all_next) {
		if (t->state != TS_PARKED) continue;
		if (t->nfds) {
			any = 1;
			nf += t->nfds;
		}
		if (t->deadline >= 0) {
			any = 1;
			if (nearest < 0 || t->deadline < nearest) nearest = t->deadline;
		}
	}
	if (!any) return 0;
	double now = nearest >= 0 ? now_secs() : 0;
	if (nf > 0) {
		if (nf > poll_cap) {
			poll_cap = nf * 2;
			poll_buf = (struct pollfd *)realloc(poll_buf, poll_cap * sizeof(struct pollfd));
		}
		int k = 0;
		for (rt_thread *t = all_threads; t; t = t->all_next)
			if (t->state == TS_PARKED)
				for (int i = 0; i < t->nfds; i++) {
					poll_buf[k] = t->fds[i];
					poll_buf[k++].revents = 0;
				}
		int ms = 0;
		if (block) {
			if (nearest < 0) ms = -1;
			else if (nearest > now) {
				double d = (nearest - now) * 1000.0 + 0.999;
				ms = d > 2e9 ? 2000000000 : (int)d;
			}
		}
		int r = poll(poll_buf, nf, ms);
		if (r < 0) r = 0; // EINTR: look again
		if (nearest >= 0) now = now_secs();
		k = 0;
		for (rt_thread *t = all_threads; t; t = t->all_next) {
			if (t->state != TS_PARKED || !t->nfds) continue;
			int ready = 0;
			for (int i = 0; i < t->nfds; i++, k++) {
				t->fds[i].revents = poll_buf[k].revents;
				if (poll_buf[k].revents) ready = 1;
			}
			if (ready) wake(t, 1);
		}
	} else if (block && nearest > now) {
		sleep_secs(nearest - now);
		now = now_secs();
	}
	if (nearest >= 0)
		for (rt_thread *t = all_threads; t; t = t->all_next)
			if (t->state == TS_PARKED && t->deadline >= 0 && now >= t->deadline) wake(t, 0);
	return 1;
}

// The running thread has given way (it is parked, runnable again or done):
// run the next runnable thread. Returns when the calling thread is resumed.
static void schedule(void) {
	rt_thread *prev = cur;
	wait_events(0);
	while (!runq_head) {
		if (!wait_events(1)) {
			fflush(stdout);
			fputs("fatal: deadlock, every thread is blocked forever\n", stderr);
			exit(1);
		}
	}
	rt_thread *next = runq_head;
	runq_head = next->next;
	if (!runq_head) runq_tail = NULL;
	next->state = TS_RUNNING;
	if (next == prev) return;
	prev->sp = rt_sp;
	prev->sbase = rt_stack_base;
	prev->hcur = rt_hcur;
	prev->exn = rt_exn;
	rt_sp = next->sp;
	rt_stack_base = next->sbase;
	rt_hcur = next->hcur;
	rt_exn = next->exn;
	cur = next;
	swapcontext(&prev->ctx, &next->ctx);
	reap();
}

static void thread_exit(void) {
	rt_thread *t = cur;
	t->state = TS_DONE;
	if (t->all_prev) t->all_prev->all_next = t->all_next;
	else all_threads = t->all_next;
	if (t->all_next) t->all_next->all_prev = t->all_prev;
	by_id[t->id] = NULL;
	rt_nthreads--;
	t->next = zombies;
	zombies = t;
	schedule();
	abort(); // not reached: a finished thread is never resumed
}

static void thread_main(void) {
	reap();
	rt_thread *t = cur;
	void **job = rt_sp++;
	*job = t->job;
	t->job = NULL;
	RT_TRY(h)
		hx_dyn_call(*job, NULL);
	RT_CATCH(h)
		// the hxc sys.thread.Thread catches everything: only a raw spawn gets here
		void *e = rt_exn;
		rt_exn = 0;
		char *s = hx_str_to_utf8(hx_std_string(e));
		fflush(stdout);
		fprintf(stderr, "Uncaught exception in thread %d: %s\n", (int)t->id, s);
		free(s);
	RT_END_TRY(h)
	thread_exit();
}

static void *map_stack(size_t bytes) {
	void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
	return p == MAP_FAILED ? NULL : p;
}

int32_t hxc_NativeThread_spawn(void *job) {
	ensure_init();
	rt_thread *t = (rt_thread *)calloc(1, sizeof(rt_thread));
	if (t) {
		t->cstack = (char *)map_stack(CSTACK_BYTES);
		t->sbase = (void **)map_stack(SSTACK_BYTES);
	}
	if (!t || !t->cstack || !t->sbase) {
		if (t && t->cstack) munmap(t->cstack, CSTACK_BYTES);
		if (t && t->sbase) munmap(t->sbase, SSTACK_BYTES);
		free(t);
		hx_throw_str("cannot allocate the stacks of a new thread");
	}
	mprotect(t->cstack, page_size, PROT_NONE); // guard page: overflow faults
	t->sp = t->sbase;
	t->deadline = -1;
	t->job = job;
	getcontext(&t->ctx);
	t->ctx.uc_stack.ss_sp = t->cstack;
	t->ctx.uc_stack.ss_size = CSTACK_BYTES;
	t->ctx.uc_link = NULL;
	makecontext(&t->ctx, thread_main, 0);
	t->id = next_id++;
	if (t->id >= by_id_cap) {
		int32_t n = by_id_cap * 2;
		while (n <= t->id) n *= 2;
		by_id = (rt_thread **)realloc(by_id, n * sizeof(rt_thread *));
		memset(by_id + by_id_cap, 0, (n - by_id_cap) * sizeof(rt_thread *));
		by_id_cap = n;
	}
	by_id[t->id] = t;
	t->all_next = all_threads;
	all_threads->all_prev = t;
	all_threads = t;
	rt_nthreads++;
	enqueue(t);
	return t->id;
}

int32_t hxc_NativeThread_current(void) { return cur ? cur->id : 1; }

int32_t hxc_NativeThread_count(void) { return rt_nthreads; }

// blocks until unparked (1) or timeout seconds pass (0); timeout < 0: no timeout
int32_t hxc_NativeThread_park(double timeout) {
	ensure_init();
	rt_thread *t = cur;
	t->deadline = timeout < 0 ? -1 : now_secs() + timeout;
	t->woken = 0;
	t->unparkable = 1;
	t->state = TS_PARKED;
	schedule();
	t->unparkable = 0;
	t->deadline = -1;
	return t->woken;
}

// wakes thread id if it is parked in hxc_NativeThread_park (else nothing: the
// sys.thread primitives check their state again after a park)
void hxc_NativeThread_unpark(int32_t id) {
	if (!cur || id <= 0 || id >= by_id_cap) return;
	rt_thread *t = by_id[id];
	if (t && t->state == TS_PARKED && t->unparkable) wake(t, 1);
}

void hxc_NativeThread_yield(void) {
	if (rt_nthreads <= 1) return;
	enqueue(cur);
	schedule();
}

// called by rt_alloc_slow (each minor collection) while several threads
// exist: a thread that computes without blocking (e.g. spinning on an atomic)
// does not starve the others
void rt_preempt(void) {
	if (!cur) return;
	wait_events(0);
	if (!runq_head) return;
	enqueue(cur);
	schedule();
}

void rt_sleep(double seconds) {
	if (rt_nthreads <= 1) {
		sleep_secs(seconds);
		return;
	}
	if (seconds <= 0) {
		hxc_NativeThread_yield();
		return;
	}
	rt_thread *t = cur;
	t->deadline = now_secs() + seconds;
	t->state = TS_PARKED;
	schedule();
	t->deadline = -1;
}

int rt_wait_fds(void *pollfds, int n, double timeout) {
	struct pollfd *fds = (struct pollfd *)pollfds;
	for (int i = 0; i < n; i++) fds[i].revents = 0;
	int r = poll(fds, n, 0);
	if (r != 0 || timeout == 0 || rt_nthreads <= 1 || cur == NULL) {
		if (r == 0 && timeout != 0) { // the only thread: just block
			int ms = timeout < 0 ? -1 : (int)(timeout * 1000.0 + 0.999);
			r = poll(fds, n, ms);
		}
		return r != 0; // a poll failure: let the caller's own call report it
	}
	rt_thread *t = cur;
	uint32_t gens_buf[8];
	uint32_t *gens = n <= 8 ? gens_buf : (uint32_t *)malloc(n * sizeof(uint32_t));
	for (int i = 0; i < n; i++) gens[i] = fd_gen(fds[i].fd);
	t->fds = fds;
	t->nfds = n;
	t->deadline = timeout < 0 ? -1 : now_secs() + timeout;
	t->woken = 0;
	t->state = TS_PARKED;
	schedule();
	t->fds = NULL;
	t->nfds = 0;
	t->deadline = -1;
	int closed = 0;
	for (int i = 0; i < n; i++)
		if (fd_gen(fds[i].fd) != gens[i]) closed = 1;
	if (gens != gens_buf) free(gens);
	if (closed) {
		errno = EBADF;
		return -1;
	}
	return t->woken;
}

int rt_wait_fd(int fd, int write, double timeout) {
	struct pollfd p;
	p.fd = fd;
	p.events = write ? POLLOUT : POLLIN;
	p.revents = 0;
	return rt_wait_fds(&p, 1, timeout);
}

#endif
