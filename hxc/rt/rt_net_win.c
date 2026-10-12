// The runtime for the C output of hxc/: Winsock behind hxc.NativeNet
// (hxc/std/hxc/NativeNet.hx) on Windows, as rt_net.c does with BSD sockets
// elsewhere, standing for OCaml's Unix library on Windows. Empty elsewhere.
//
// A socket is its SOCKET handle as an Int. Errors are Winsock's, mapped to the
// errno values OCaml's Unix library reports for them; strerror is the C
// runtime's message for those. Sockets are not inherited by child processes.
// Winsock has no way to ask whether a socket blocks, so the sockets the
// program made non-blocking (setBlocking) are remembered here.
#if defined(_WIN32) && !defined(HXC_NO_NET)
#include "rt.h"
#include "rt_win.h"
#include <stdio.h>

#define BYTES_LEN(b) (((int32_t *)(b))[0])
#define BYTES_DATA(b) ((unsigned char *)(b) + 8)

static RT_TLS int last_errno;

static int32_t fail(void) {
	last_errno = rt_win_sock_errno(WSAGetLastError());
	return -1;
}

static int32_t ret(int r) { return r == SOCKET_ERROR ? fail() : r; }

int32_t hxc_NativeNet_errno(void) { return last_errno; }

void *hxc_NativeNet_strerror(int32_t err) {
	const char *s = strerror(err);
	return hx_str_of_utf8(s, (int32_t)strlen(s));
}

// the sockets in non-blocking mode
static SOCKET *nonblocking;
static int n_nonblocking, cap_nonblocking;
static SRWLOCK nb_lock = SRWLOCK_INIT;

static int is_nonblocking(SOCKET s) {
	int r = 0;
	AcquireSRWLockShared(&nb_lock);
	for (int i = 0; i < n_nonblocking; i++)
		if (nonblocking[i] == s) r = 1;
	ReleaseSRWLockShared(&nb_lock);
	return r;
}

static void set_nonblocking(SOCKET s, int on) {
	AcquireSRWLockExclusive(&nb_lock);
	for (int i = 0; i < n_nonblocking; i++)
		if (nonblocking[i] == s) nonblocking[i--] = nonblocking[--n_nonblocking];
	if (on) {
		if (n_nonblocking == cap_nonblocking) {
			cap_nonblocking = cap_nonblocking ? cap_nonblocking * 2 : 16;
			nonblocking = (SOCKET *)realloc(nonblocking, sizeof(SOCKET) * cap_nonblocking);
		}
		nonblocking[n_nonblocking++] = s;
	}
	ReleaseSRWLockExclusive(&nb_lock);
}

// With other threads, a blocking call waits for the socket in a safe region
// first (WSAPoll), so a collection can run meanwhile
static int cooperative(SOCKET s) { return RT_NTHREADS() > 1 && !is_nonblocking(s); }

// SO_RCVTIMEO/SO_SNDTIMEO (milliseconds on Windows): seconds, -1 when none
static double sock_timeout(SOCKET s, int opt) {
	DWORD ms = 0;
	int n = sizeof ms;
	if (getsockopt(s, SOL_SOCKET, opt, (char *)&ms, &n) != 0 || ms == 0) return -1;
	return (double)ms / 1000.0;
}

// waits for s as a blocking call would (with the socket's timeout): 0 when the
// wait failed, last_errno set as the blocking call would have (EAGAIN: timeout)
static int wait_sock(SOCKET s, int write) {
	int r = rt_wait_fd((int)s, write, sock_timeout(s, write ? SO_SNDTIMEO : SO_RCVTIMEO));
	if (r > 0) return 1;
	last_errno = r == 0 ? EAGAIN : EBADF;
	return 0;
}

int32_t hxc_NativeNet_socket(void) {
	rt_win_sockets_init();
	SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
	if (s == INVALID_SOCKET) return fail();
	SetHandleInformation((HANDLE)s, HANDLE_FLAG_INHERIT, 0);
	return (int32_t)s;
}

int32_t hxc_NativeNet_close(int32_t fd) {
	rt_fd_closed(fd);
	set_nonblocking((SOCKET)fd, 0);
	return ret(closesocket((SOCKET)fd));
}

int32_t hxc_NativeNet_accept(int32_t fd) {
	SOCKET s = (SOCKET)fd;
	if (cooperative(s) && !wait_sock(s, 0)) return -1;
	struct sockaddr_storage a;
	int n = sizeof a;
	SOCKET c = accept(s, (struct sockaddr *)&a, &n);
	if (c == INVALID_SOCKET) return fail();
	SetHandleInformation((HANDLE)c, HANDLE_FLAG_INHERIT, 0);
	return (int32_t)c;
}

static struct sockaddr_in inet_addr_of(int32_t ip, int32_t port) {
	struct sockaddr_in a;
	memset(&a, 0, sizeof a);
	a.sin_family = AF_INET;
	a.sin_addr.s_addr = htonl((uint32_t)ip);
	a.sin_port = htons((uint16_t)port);
	return a;
}

int32_t hxc_NativeNet_bind(int32_t fd, int32_t ip, int32_t port) {
	struct sockaddr_in a = inet_addr_of(ip, port);
	return ret(bind((SOCKET)fd, (struct sockaddr *)&a, sizeof a));
}

int32_t hxc_NativeNet_connect(int32_t fd, int32_t ip, int32_t port) {
	SOCKET s = (SOCKET)fd;
	struct sockaddr_in a = inet_addr_of(ip, port);
	if (cooperative(s)) { // a non-blocking connect, then wait until it completes
		u_long on = 1, off = 0;
		ioctlsocket(s, FIONBIO, &on);
		int r = connect(s, (struct sockaddr *)&a, sizeof a);
		int e = r == SOCKET_ERROR ? WSAGetLastError() : 0;
		if (e == WSAEWOULDBLOCK) {
			if (wait_sock(s, 1)) {
				int err = 0, n = sizeof err;
				getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &n);
				r = err ? -1 : 0;
				if (err) last_errno = rt_win_sock_errno(err);
			} else
				r = -1;
		} else if (e)
			last_errno = rt_win_sock_errno(e);
		ioctlsocket(s, FIONBIO, &off);
		return r;
	}
	return ret(connect(s, (struct sockaddr *)&a, sizeof a));
}

int32_t hxc_NativeNet_listen(int32_t fd, int32_t n) { return ret(listen((SOCKET)fd, n)); }

void *hxc_NativeNet_sockName(int32_t fd, int32_t peer) {
	struct sockaddr_storage s;
	int n = sizeof s;
	int r = peer ? getpeername((SOCKET)fd, (struct sockaddr *)&s, &n) : getsockname((SOCKET)fd, (struct sockaddr *)&s, &n);
	if (r != 0) {
		fail();
		return NULL;
	}
	void *a = hx_arr_new(AK_I32, 2);
	if (s.ss_family == AF_INET) {
		struct sockaddr_in *i = (struct sockaddr_in *)&s;
		((int32_t *)ARR_DATA(a))[0] = (int32_t)ntohl(i->sin_addr.s_addr);
		((int32_t *)ARR_DATA(a))[1] = ntohs(i->sin_port);
	} else {
		((int32_t *)ARR_DATA(a))[0] = 0;
		((int32_t *)ARR_DATA(a))[1] = -1;
	}
	return a;
}

// OCaml's Unix.recv/send check the range (Invalid_argument "Unix.recv")
int32_t hxc_NativeNet_recv(int32_t fd, void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos > BYTES_LEN(b) - len) hx_throw_str("Unix.recv");
	SOCKET s = (SOCKET)fd;
	if (cooperative(s)) {
		RT_ROOT(b); // the wait lets other threads run (and collect)
		int ok = wait_sock(s, 0);
		RT_RELOAD(b);
		RT_UNROOT(1);
		if (!ok) return -1;
	}
	return ret(recv(s, (char *)BYTES_DATA(b) + pos, len, 0));
}

int32_t hxc_NativeNet_send(int32_t fd, void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos > BYTES_LEN(b) - len) hx_throw_str("Unix.send");
	SOCKET s = (SOCKET)fd;
	if (cooperative(s)) {
		RT_ROOT(b);
		int ok = wait_sock(s, 1);
		RT_RELOAD(b);
		RT_UNROOT(1);
		if (!ok) return -1;
	}
	return ret(send(s, (const char *)BYTES_DATA(b) + pos, len, 0));
}

static void to_fdset(void *a, fd_set *s) {
	FD_ZERO(s);
	int32_t n = a ? ARR_LEN(a) : 0;
	for (int32_t i = 0; i < n; i++) FD_SET((SOCKET)hx_aget_i_slow(a, i), s);
}

static void from_fdset(void **slot, fd_set *s) {
	int32_t n = *slot ? ARR_LEN(*slot) : 0;
	for (int32_t i = 0; i < n; i++) {
		int32_t fd = hx_aget_i_slow(*slot, i);
		if (!FD_ISSET((SOCKET)fd, s)) hx_aset_slow(slot, i, AK_I32, (uint64_t)(uint32_t)-1);
	}
}

// Unix.select: a negative timeout waits forever; Winsock's select fails
// without sockets, then the timeout is slept as select would
int32_t hxc_NativeNet_select(void *r, void *w, void *o, double timeout) {
	int32_t nr = r ? ARR_LEN(r) : 0, nw = w ? ARR_LEN(w) : 0, no = o ? ARR_LEN(o) : 0;
	if (nr > FD_SETSIZE || nw > FD_SETSIZE || no > FD_SETSIZE) {
		last_errno = EINVAL;
		return -1;
	}
	if (nr + nw + no == 0) {
		if (timeout > 0) rt_sleep(timeout);
		else if (timeout < 0) hx_throw_str("select: no descriptor and no timeout");
		return 0;
	}
	if (RT_NTHREADS() > 1 && timeout != 0) {
		// other threads run until a socket is ready or the timeout passes,
		// then select looks without waiting
		WSAPOLLFD *p = (WSAPOLLFD *)malloc((nr + nw + no + 1) * sizeof(WSAPOLLFD));
		int k = 0;
		for (int32_t i = 0; i < nr; i++, k++) p[k].fd = (SOCKET)hx_aget_i_slow(r, i), p[k].events = POLLRDNORM;
		for (int32_t i = 0; i < nw; i++, k++) p[k].fd = (SOCKET)hx_aget_i_slow(w, i), p[k].events = POLLWRNORM;
		for (int32_t i = 0; i < no; i++, k++) p[k].fd = (SOCKET)hx_aget_i_slow(o, i), p[k].events = POLLRDBAND;
		RT_ROOT(r);
		RT_ROOT(w);
		RT_ROOT(o);
		rt_wait_fds(p, k, timeout);
		RT_RELOAD(r);
		RT_RELOAD(w);
		RT_RELOAD(o);
		RT_UNROOT(3);
		free(p);
		timeout = 0;
	}
	fd_set rs, ws, os;
	to_fdset(r, &rs);
	to_fdset(w, &ws);
	to_fdset(o, &os);
	struct timeval tv, *tvp = NULL;
	if (timeout >= 0) {
		tv.tv_sec = (long)timeout;
		tv.tv_usec = (long)(1e6 * (timeout - (double)tv.tv_sec));
		tvp = &tv;
	}
	int n = select(0, &rs, &ws, &os, tvp);
	if (n == SOCKET_ERROR) return fail();
	RT_ROOT(r);
	RT_ROOT(w);
	RT_ROOT(o);
	from_fdset(r_root, &rs);
	from_fdset(w_root, &ws);
	from_fdset(o_root, &os);
	RT_UNROOT(3);
	return n;
}

static int32_t set_bool(int32_t fd, int level, int opt, int32_t b) {
	BOOL v = b ? TRUE : FALSE;
	return ret(setsockopt((SOCKET)fd, level, opt, (const char *)&v, sizeof v));
}

int32_t hxc_NativeNet_setNoDelay(int32_t fd, int32_t b) { return set_bool(fd, IPPROTO_TCP, TCP_NODELAY, b); }
int32_t hxc_NativeNet_setBroadcast(int32_t fd, int32_t b) { return set_bool(fd, SOL_SOCKET, SO_BROADCAST, b); }
int32_t hxc_NativeNet_setReuseAddr(int32_t fd, int32_t b) { return set_bool(fd, SOL_SOCKET, SO_REUSEADDR, b); }

// Unix.setsockopt_float SO_RCVTIMEO, then SO_SNDTIMEO (milliseconds)
int32_t hxc_NativeNet_setTimeout(int32_t fd, double t) {
	DWORD ms = (DWORD)(t * 1000.0);
	if (setsockopt((SOCKET)fd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&ms, sizeof ms) != 0) return fail();
	return ret(setsockopt((SOCKET)fd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&ms, sizeof ms));
}

int32_t hxc_NativeNet_shutdown(int32_t fd, int32_t mode) {
	int how = mode == 0 ? SD_RECEIVE : mode == 1 ? SD_SEND : SD_BOTH;
	return ret(shutdown((SOCKET)fd, how));
}

int32_t hxc_NativeNet_setBlocking(int32_t fd, int32_t b) {
	u_long nb = b ? 0 : 1;
	if (ioctlsocket((SOCKET)fd, FIONBIO, &nb) != 0) return fail();
	set_nonblocking((SOCKET)fd, !b);
	return 0;
}

int32_t hxc_NativeNet_blocked(void) { return last_errno == EAGAIN || last_errno == EWOULDBLOCK; }

void *hxc_NativeNet_gethostname(void) {
	rt_win_sockets_init();
	char buf[4096];
	if (gethostname(buf, sizeof buf - 1) != 0) {
		fail();
		return NULL;
	}
	buf[sizeof buf - 1] = 0;
	return hx_str_of_utf8(buf, (int32_t)strlen(buf));
}

// one lookup at a time, in a safe region (it may block on the network)
static SRWLOCK resolver_lock = SRWLOCK_INIT;

void *hxc_NativeNet_resolve(void *name) {
	rt_win_sockets_init();
	char *n = hx_str_to_utf8(name);
	uint32_t ip;
	int found = 0;
	rt_blocking_enter();
	AcquireSRWLockExclusive(&resolver_lock);
	struct hostent *h = gethostbyname(n);
	if (h && h->h_addrtype == AF_INET && h->h_addr_list[0]) {
		memcpy(&ip, h->h_addr_list[0], 4);
		found = 1;
	}
	ReleaseSRWLockExclusive(&resolver_lock);
	rt_blocking_leave();
	free(n);
	last_errno = 0;
	if (!found) return NULL;
	void *a = hx_arr_new(AK_I32, 1);
	((int32_t *)ARR_DATA(a))[0] = (int32_t)ntohl(ip);
	return a;
}

void *hxc_NativeNet_reverse(int32_t ip) {
	rt_win_sockets_init();
	uint32_t a = htonl((uint32_t)ip);
	char *name = NULL;
	rt_blocking_enter();
	AcquireSRWLockExclusive(&resolver_lock);
	struct hostent *h = gethostbyaddr((const char *)&a, 4, AF_INET);
	if (h && h->h_name) name = _strdup(h->h_name);
	ReleaseSRWLockExclusive(&resolver_lock);
	rt_blocking_leave();
	last_errno = 0;
	if (!name) return NULL;
	void *s = hx_str_of_utf8(name, (int32_t)strlen(name));
	free(name);
	return s;
}

#endif
