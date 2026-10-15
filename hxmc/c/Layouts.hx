import sys.FileSystem;
import sys.io.File;

using StringTools;

// Writes hxmc/std/hxmc/rt/Layouts.hx: the constants and struct layouts of
// libuv and of the C library that the runtime's Haxe code (hxmc.rt.Uv) needs
// per target, read from the headers the runtime objects are built with
// (hxmc/c/deps.sh) by compiling them with zig for each target (the values of
// an int array in the assembly). Development time only: the runtime contains
// no C; `--check` fails when the committed file differs (make rt-build).
//   bin/hxmc/hxmc -cp hxmc/c --run Layouts [--check]
class Layouts {
	static final TARGETS = [
		{name: "linux-x86_64", triple: "x86_64-linux-musl"},
		{name: "linux-arm64", triple: "aarch64-linux-musl"},
		{name: "macos-x86_64", triple: "x86_64-macos"},
		{name: "macos-arm64", triple: "aarch64-macos"},
		{name: "windows-x86_64", triple: "x86_64-windows-gnu"},
		{name: "windows-arm64", triple: "aarch64-windows-gnu"},
	];
	static final OUT = "hxmc/std/hxmc/rt/Layouts.hx";

	static final PRELUDE = "
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <signal.h>
#include <unistd.h>
#endif
#include <stddef.h>
#include <uv.h>
#define O(t, f) ((int)offsetof(t, f))
#define S(t) ((int)sizeof(t))
#ifndef O_DIRECT
#define O_DIRECT 0
#endif
#ifndef O_NOATIME
#define O_NOATIME 0
#endif
";

	// name, C expression (an int)
	static final SCALARS:Array<Array<String>> = [
		["LONG_SIZE", "S(long)"],
		["SOCKADDR_STORAGE_SIZE", "S(struct sockaddr_storage)"],
		["SOCKADDR_IN_SIZE", "S(struct sockaddr_in)"],
		["SOCKADDR_IN6_SIZE", "S(struct sockaddr_in6)"],
		["SA_FAMILY", "O(struct sockaddr, sa_family)"],
		["SA_FAMILY_SIZE", "S(((struct sockaddr *)0)->sa_family)"],
		["SIN_PORT", "O(struct sockaddr_in, sin_port)"],
		["SIN6_PORT", "O(struct sockaddr_in6, sin6_port)"],
		["AF_UNSPEC", "AF_UNSPEC"],
		["AF_INET", "AF_INET"],
		["AF_INET6", "AF_INET6"],
		["ADDRINFO_SIZE", "S(struct addrinfo)"],
		["AI_FLAGS", "O(struct addrinfo, ai_flags)"],
		["AI_FAMILY", "O(struct addrinfo, ai_family)"],
		["AI_SOCKTYPE", "O(struct addrinfo, ai_socktype)"],
		["AI_PROTOCOL", "O(struct addrinfo, ai_protocol)"],
		["AI_ADDRLEN", "O(struct addrinfo, ai_addrlen)"],
		["AI_ADDRLEN_SIZE", "S(((struct addrinfo *)0)->ai_addrlen)"],
		["AI_ADDR", "O(struct addrinfo, ai_addr)"],
		["AI_CANONNAME", "O(struct addrinfo, ai_canonname)"],
		["AI_NEXT", "O(struct addrinfo, ai_next)"],
		["UV_BUF_SIZE", "S(uv_buf_t)"],
		["UV_BUF_BASE", "O(uv_buf_t, base)"],
		["UV_BUF_LEN", "O(uv_buf_t, len)"],
		["UV_BUF_LEN_SIZE", "S(((uv_buf_t *)0)->len)"],
		["SIGNAL_SIGNUM", "O(uv_signal_t, signum)"],
		["GNI_HOST", "O(uv_getnameinfo_t, host)"],
		["GNI_SERVICE", "O(uv_getnameinfo_t, service)"],
		["DIR_DIRENTS", "O(uv_dir_t, dirents)"],
		["DIR_NENTRIES", "O(uv_dir_t, nentries)"],
		["DIRENT_SIZE", "S(uv_dirent_t)"],
		["DIRENT_NAME", "O(uv_dirent_t, name)"],
		["DIRENT_TYPE", "O(uv_dirent_t, type)"],
		["STAT_ATIM", "O(uv_stat_t, st_atim)"],
		["RUSAGE_UTIME", "O(uv_rusage_t, ru_utime)"],
		["RUSAGE_STIME", "O(uv_rusage_t, ru_stime)"],
		["RUSAGE_MAXRSS", "O(uv_rusage_t, ru_maxrss)"],
		["CPU_INFO_SIZE", "S(uv_cpu_info_t)"],
		["CPU_MODEL", "O(uv_cpu_info_t, model)"],
		["CPU_SPEED", "O(uv_cpu_info_t, speed)"],
		["CPU_TIMES", "O(uv_cpu_info_t, cpu_times)"],
		["IFADDR_SIZE", "S(uv_interface_address_t)"],
		["IFADDR_NAME", "O(uv_interface_address_t, name)"],
		["IFADDR_PHYS", "O(uv_interface_address_t, phys_addr)"],
		["IFADDR_INTERNAL", "O(uv_interface_address_t, is_internal)"],
		["IFADDR_ADDRESS", "O(uv_interface_address_t, address)"],
		["IFADDR_NETMASK", "O(uv_interface_address_t, netmask)"],
		["PASSWD_SIZE", "S(uv_passwd_t)"],
		["PASSWD_USERNAME", "O(uv_passwd_t, username)"],
		["PASSWD_UID", "O(uv_passwd_t, uid)"],
		["PASSWD_GID", "O(uv_passwd_t, gid)"],
		["PASSWD_SHELL", "O(uv_passwd_t, shell)"],
		["PASSWD_HOMEDIR", "O(uv_passwd_t, homedir)"],
		["PROCESS_OPTIONS_SIZE", "S(uv_process_options_t)"],
		["PO_EXIT_CB", "O(uv_process_options_t, exit_cb)"],
		["PO_FILE", "O(uv_process_options_t, file)"],
		["PO_ARGS", "O(uv_process_options_t, args)"],
		["PO_ENV", "O(uv_process_options_t, env)"],
		["PO_CWD", "O(uv_process_options_t, cwd)"],
		["PO_FLAGS", "O(uv_process_options_t, flags)"],
		["PO_STDIO_COUNT", "O(uv_process_options_t, stdio_count)"],
		["PO_STDIO", "O(uv_process_options_t, stdio)"],
		["PO_UID", "O(uv_process_options_t, uid)"],
		["PO_GID", "O(uv_process_options_t, gid)"],
		["UID_SIZE", "S(uv_uid_t)"],
		["STDIO_CONTAINER_SIZE", "S(uv_stdio_container_t)"],
		["STDIO_FLAGS", "O(uv_stdio_container_t, flags)"],
		["STDIO_DATA", "O(uv_stdio_container_t, data)"],
		["UV_IGNORE", "UV_IGNORE"],
		["UV_CREATE_PIPE", "UV_CREATE_PIPE"],
		["UV_INHERIT_FD", "UV_INHERIT_FD"],
		["UV_INHERIT_STREAM", "UV_INHERIT_STREAM"],
		["UV_READABLE_PIPE", "UV_READABLE_PIPE"],
		["UV_WRITABLE_PIPE", "UV_WRITABLE_PIPE"],
		["UV_OVERLAPPED_PIPE", "UV_OVERLAPPED_PIPE"],
		["UV_PROCESS_SETUID", "UV_PROCESS_SETUID"],
		["UV_PROCESS_SETGID", "UV_PROCESS_SETGID"],
		["UV_PROCESS_WINDOWS_VERBATIM_ARGUMENTS", "UV_PROCESS_WINDOWS_VERBATIM_ARGUMENTS"],
		["UV_PROCESS_DETACHED", "UV_PROCESS_DETACHED"],
		["UV_PROCESS_WINDOWS_HIDE", "UV_PROCESS_WINDOWS_HIDE"],
		["UV_PROCESS_WINDOWS_HIDE_CONSOLE", "UV_PROCESS_WINDOWS_HIDE_CONSOLE"],
		["UV_PROCESS_WINDOWS_HIDE_GUI", "UV_PROCESS_WINDOWS_HIDE_GUI"],
		["UV_HANDLE_TYPE_MAX", "UV_HANDLE_TYPE_MAX"],
		["UV_REQ_TYPE_MAX", "UV_REQ_TYPE_MAX"],
		["UV_TCP", "UV_TCP"],
		["UV_UDP", "UV_UDP"],
		["UV_TTY", "UV_TTY"],
		["UV_NAMED_PIPE", "UV_NAMED_PIPE"],
		["UV_FILE", "UV_FILE"],
		["UV_RUN_DEFAULT", "UV_RUN_DEFAULT"],
		["UV_RUN_ONCE", "UV_RUN_ONCE"],
		["UV_RUN_NOWAIT", "UV_RUN_NOWAIT"],
		["UV_TCP_IPV6ONLY", "UV_TCP_IPV6ONLY"],
		["UV_READABLE", "UV_READABLE"],
		["UV_WRITABLE", "UV_WRITABLE"],
		["UV_TTY_MODE_NORMAL", "UV_TTY_MODE_NORMAL"],
		["UV_TTY_MODE_RAW", "UV_TTY_MODE_RAW"],
		["UV_TTY_MODE_IO", "UV_TTY_MODE_IO"],
		["UV_TTY_SUPPORTED", "UV_TTY_SUPPORTED"],
		["UV_TTY_UNSUPPORTED", "UV_TTY_UNSUPPORTED"],
		["UV_JOIN_GROUP", "UV_JOIN_GROUP"],
		["UV_LEAVE_GROUP", "UV_LEAVE_GROUP"],
		["UV_EINVAL", "UV_EINVAL"],
		["UV_ENOBUFS", "UV_ENOBUFS"],
		["UV_UNKNOWN", "UV_UNKNOWN"],
	];

	// luv's Error.t, in evalLuv.ml's encode_uv_error order (24: ECHARSET, none)
	static final UV_ERRORS = "UV_E2BIG UV_EACCES UV_EADDRINUSE UV_EADDRNOTAVAIL UV_EAFNOSUPPORT UV_EAGAIN UV_EAI_ADDRFAMILY UV_EAI_AGAIN UV_EAI_BADFLAGS
		UV_EAI_BADHINTS UV_EAI_CANCELED UV_EAI_FAIL UV_EAI_FAMILY UV_EAI_MEMORY UV_EAI_NODATA UV_EAI_NONAME UV_EAI_OVERFLOW
		UV_EAI_PROTOCOL UV_EAI_SERVICE UV_EAI_SOCKTYPE UV_EALREADY UV_EBADF UV_EBUSY UV_ECANCELED 0 UV_ECONNABORTED
		UV_ECONNREFUSED UV_ECONNRESET UV_EDESTADDRREQ UV_EEXIST UV_EFAULT UV_EFBIG UV_EHOSTUNREACH UV_EINTR UV_EINVAL UV_EIO
		UV_EISCONN UV_EISDIR UV_ELOOP UV_EMFILE UV_EMSGSIZE UV_ENAMETOOLONG UV_ENETDOWN UV_ENETUNREACH UV_ENFILE UV_ENOBUFS
		UV_ENODEV UV_ENOENT UV_ENOMEM UV_ENONET UV_ENOPROTOOPT UV_ENOSPC UV_ENOSYS UV_ENOTCONN UV_ENOTDIR UV_ENOTEMPTY
		UV_ENOTSOCK UV_ENOTSUP UV_EPERM UV_EPIPE UV_EPROTO UV_EPROTONOSUPPORT UV_EPROTOTYPE UV_ERANGE UV_EROFS UV_ESHUTDOWN
		UV_ESPIPE UV_ESRCH UV_ETIMEDOUT UV_ETXTBSY UV_EXDEV UV_UNKNOWN UV_EOF UV_ENXIO UV_EMLINK UV_ENOTTY UV_EFTYPE UV_EILSEQ
		UV_EOVERFLOW UV_ESOCKTNOSUPPORT UV_ENODATA UV_EUNATCH";

	// NativeUv.constant's groups (luv's to_c tables), as the C glue had them; per
	// group the C values by index (Windows: libuv's own flags and the C runtime's modes)
	static final GROUPS_POSIX = [
		"O_RDONLY O_WRONLY O_RDWR O_CREAT O_EXCL 0 O_NOCTTY O_NOFOLLOW 0 O_TRUNC O_APPEND O_DIRECT O_DSYNC 0 O_NOATIME O_NONBLOCK 0 0 0 0 O_SYNC",
		"S_IRWXU S_IRUSR S_IWUSR S_IXUSR S_IRWXG S_IRGRP S_IWGRP S_IXGRP S_IRWXO S_IROTH S_IWOTH S_IXOTH S_ISUID S_ISGID S_ISVTX S_IFMT S_IFREG S_IFDIR S_IFBLK S_IFCHR S_IFLNK S_IFIFO",
		"F_OK R_OK W_OK X_OK",
		"AF_UNSPEC AF_INET AF_INET6",
		"SOCK_STREAM SOCK_DGRAM SOCK_RAW",
		"SIGABRT SIGFPE SIGHUP SIGILL SIGINT SIGKILL SIGSEGV SIGTERM SIGWINCH SIGPROF",
	];
	static final GROUPS_WINDOWS = [
		"UV_FS_O_RDONLY UV_FS_O_WRONLY UV_FS_O_RDWR UV_FS_O_CREAT UV_FS_O_EXCL UV_FS_O_EXLOCK UV_FS_O_NOCTTY UV_FS_O_NOFOLLOW UV_FS_O_TEMPORARY UV_FS_O_TRUNC UV_FS_O_APPEND UV_FS_O_DIRECT UV_FS_O_DSYNC UV_FS_O_FILEMAP UV_FS_O_NOATIME UV_FS_O_NONBLOCK UV_FS_O_RANDOM UV_FS_O_SEQUENTIAL UV_FS_O_SHORT_LIVED UV_FS_O_SYMLINK UV_FS_O_SYNC",
		"0700 _S_IREAD _S_IWRITE _S_IEXEC 0070 0040 0020 0010 0007 0004 0002 0001 0 0 0 _S_IFMT _S_IFREG _S_IFDIR 0 _S_IFCHR 0 _S_IFIFO",
		"0 4 2 1",
		"AF_UNSPEC AF_INET AF_INET6",
		"SOCK_STREAM SOCK_DGRAM SOCK_RAW",
		"SIGABRT SIGFPE SIGHUP SIGILL SIGINT SIGKILL SIGSEGV SIGTERM SIGWINCH 27",
	];
	static final GROUPS_COMMON = [
		"AI_PASSIVE AI_CANONNAME AI_NUMERICHOST AI_NUMERICSERV AI_V4MAPPED AI_ALL AI_ADDRCONFIG",
		"NI_NAMEREQD NI_DGRAM NI_NOFQDN NI_NUMERICHOST NI_NUMERICSERV",
		"UV_FS_COPYFILE_EXCL UV_FS_COPYFILE_FICLONE UV_FS_COPYFILE_FICLONE_FORCE UV_FS_SYMLINK_DIR UV_FS_SYMLINK_JUNCTION",
		"UV_VERSION_MAJOR UV_VERSION_MINOR UV_VERSION_PATCH UV_VERSION_IS_RELEASE UV_VERSION_HEX",
		"UV_DIRENT_UNKNOWN UV_DIRENT_FILE UV_DIRENT_DIR UV_DIRENT_LINK UV_DIRENT_FIFO UV_DIRENT_SOCKET UV_DIRENT_CHAR UV_DIRENT_BLOCK",
		"UV_UDP_PARTIAL UV_UDP_MMSG_CHUNK UV_UDP_MMSG_FREE UV_UDP_RECVMMSG UV_UDP_IPV6ONLY UV_UDP_REUSEADDR",
		"UV_RENAME UV_CHANGE UV_FS_EVENT_WATCH_ENTRY UV_FS_EVENT_STAT UV_FS_EVENT_RECURSIVE",
	];

	static function words(s:String):Array<String>
		return [for (w in ~/\s+/g.split(s.trim())) if (w != "") w];

	// the values of `exprs` for target t: an int array compiled to assembly
	static function values(t:{name:String, triple:String}, exprs:Array<String>, tmp:String):Array<Int> {
		var c = PRELUDE + "const int hxmc_layouts[] = {\n" + exprs.join(",\n") + "\n};\n";
		var src = '$tmp/l-${t.name}.c', asm = '$tmp/l-${t.name}.s';
		File.saveContent(src, c);
		var inc = 'bin/hxmc/deps/${t.name}/include';
		if (!FileSystem.exists(inc)) throw 'Layouts: $inc is missing (make deps)';
		var p = new sys.io.Process(Sys.getEnv("ZIG") ?? "zig", ["cc", "-target", t.triple, "-I", inc, "-S", "-O1", "-g0", "-o", asm, src]);
		var err = p.stderr.readAll().toString();
		if (p.exitCode() != 0) throw 'Layouts: zig cc for ${t.name}: $err';
		p.close();
		var r = [];
		var inArray = false;
		for (l in File.getContent(asm).split("\n")) {
			var s = l.trim();
			if (s.startsWith("hxmc_layouts:") || s.startsWith("_hxmc_layouts:")) {
				inArray = true;
				continue;
			}
			if (!inArray) continue;
			if (s.startsWith(".long") || s.startsWith(".word")) {
				var v = Std.parseFloat(s.substr(5).trim());
				if (v >= 2147483648.0) v -= 4294967296.0;
				r.push(Std.int(v));
			} else if (s.startsWith(".zero") || s.startsWith(".space")) {
				var n = Std.parseInt(s.split(" ").pop().split("\t").pop()) >> 2;
				for (_ in 0...n)
					r.push(0);
			} else if (r.length >= exprs.length || (s != "" && !s.startsWith(".") && !s.startsWith("#") && !s.startsWith(";")))
				break;
		}
		if (r.length < exprs.length) throw 'Layouts: ${t.name}: ${r.length} values for ${exprs.length} expressions';
		return r.slice(0, exprs.length);
	}

	// `a` as a Haxe expression of the target: one value, or the target's
	static function perTarget(vs:Array<Int>):String {
		var same = true;
		for (v in vs)
			if (v != vs[0]) same = false;
		if (same) return Std.string(vs[0]);
		var s = new StringBuf();
		for (i in 0...vs.length - 1)
			s.add('Mem.target() == $i ? ${vs[i]} : ');
		s.add(vs[vs.length - 1]);
		return s.toString();
	}

	static function main() {
		var check = Sys.args().indexOf("--check") >= 0;
		var tmp = "bin/hxmc/layouts";
		if (!FileSystem.exists(tmp)) FileSystem.createDirectory(tmp);
		var exprs = [for (s in SCALARS) s[1]];
		var errs = words(UV_ERRORS);
		var errAt = exprs.length;
		exprs = exprs.concat(errs);
		var groupAt = exprs.length;
		var winGroups = [for (g in GROUPS_WINDOWS) words(g)];
		var posixGroups = [for (g in GROUPS_POSIX) words(g)];
		var common = [for (g in GROUPS_COMMON) words(g)];
		// (per target, the groups of its system; the same count of values either way)
		var results = [];
		for (t in TARGETS) {
			var groups = (t.name.startsWith("windows") ? winGroups : posixGroups).concat(common);
			var e = exprs.copy();
			for (g in groups)
				e = e.concat(g);
			results.push(values(t, e, tmp));
		}
		var out = new StringBuf();
		out.add("package hxmc.rt;\n\nimport hxmc.unsafe.Mem;\n\n");
		out.add("// Generated by hxmc/c/Layouts.hx from the headers of libuv and the C\n");
		out.add("// libraries (hxmc/c/deps.sh): do not edit. The constants and struct layouts\n");
		out.add("// hxmc.rt.Uv needs, per target (Mem.target(): " + [for (i in 0...TARGETS.length) '$i ${TARGETS[i].name}'].join(", ") + "),\n");
		out.add("// folded when the program is lowered for one.\n");
		out.add("@:hxmc.native\nclass Layouts {\n");
		out.add("\tpublic static inline var UV_VERSION_SUFFIX = \"\";\n");
		for (k in 0...SCALARS.length) {
			var vs = [for (r in results) r[k]];
			var name = SCALARS[k][0];
			var e = perTarget(vs);
			if (e.indexOf("?") < 0) out.add('\tpublic static inline var $name = $e;\n') else {
				out.add('\tpublic static var $name(get, never):Int;\n\n\tstatic inline function get_$name():Int\n\t\treturn $e;\n\n');
			}
		}
		function table(name:String, at:Int, n:Int, doc:String) {
			out.add('\n\t// $doc\n');
			out.add('\tstatic var ${name}Values:Array<Int>;\n\n');
			out.add('\tpublic static function $name(i:Int):Int {\n\t\tif (${name}Values == null) ${name}Values = ');
			var arrays = [for (r in results) "[" + r.slice(at, at + n).join(", ") + "]"];
			var same = true;
			for (a in arrays)
				if (a != arrays[0]) same = false;
			if (same) out.add(arrays[0]) else {
				for (i in 0...arrays.length - 1)
					out.add('Mem.target() == $i ? ${arrays[i]} : ');
				out.add(arrays[arrays.length - 1]);
			}
			out.add(';\n\t\treturn ${name}Values[i];\n\t}\n');
		}
		table("uvError", errAt, errs.length, "luv's Error.t (evalLuv.ml's encode_uv_error order) -> libuv's code");
		// the constant groups, flattened: group g's values from groupStart(g)
		var sizes = [for (i in 0...posixGroups.length) posixGroups[i].length].concat([for (g in common) g.length]);
		var total = 0;
		for (s in sizes)
			total += s;
		var starts = [];
		var a = 0;
		for (s in sizes) {
			starts.push(a);
			a += s;
		}
		table("constantValue", groupAt, total, "NativeUv.constant's groups, flattened (constant)");
		out.add('\n\tstatic final GROUP_START = [${starts.join(", ")}];\n\tstatic final GROUP_SIZE = [${sizes.join(", ")}];\n');
		out.add("\n\t// the C value of index i in group g (0 for unknown ones)\n");
		out.add("\tpublic static function constant(g:Int, i:Int):Int\n\t\treturn g >= 0 && g < GROUP_SIZE.length && i >= 0 && i < GROUP_SIZE[g] ? constantValue(GROUP_START[g] + i) : 0;\n");
		out.add("}\n");
		var text = out.toString();
		if (check) {
			if (!FileSystem.exists(OUT) || File.getContent(OUT) != text) {
				Sys.println('Layouts: $OUT is not what the headers give (bin/hxmc/hxmc -cp hxmc/c --run Layouts)');
				Sys.exit(1);
			}
			Sys.println('Layouts: $OUT is current');
		} else {
			File.saveContent(OUT, text);
			Sys.println('Layouts: wrote $OUT');
		}
	}
}
