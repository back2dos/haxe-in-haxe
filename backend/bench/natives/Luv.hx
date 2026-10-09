// Checks the libuv natives (eval.luv) of a build of the port: timers, a TCP
// echo between two handles of one loop, file system requests, a child process
// with a pipe, an idle handle and a few system queries. Run in the port's Eval:
//   <port> -cp backend/bench/natives -main Luv --interp
// Prints "luv: ok" when every check passed (and the reference compiler prints
// the same output).
import eval.luv.*;
import eval.luv.File;
import eval.luv.SockAddr;
import haxe.io.Bytes;

using eval.luv.Result;

class Luv {
	static var failures = 0;

	static function check(what:String, ok:Bool) {
		Sys.println((ok ? "ok   " : "FAIL ") + what);
		if (!ok) failures++;
	}

	static function main() {
		var loop = Loop.defaultLoop();
		var log = [];
		loop.updateTime(); // the cached loop time may be old

		// timers: a repeating one stopped after 3 ticks, a one-shot after it
		var ticks = 0;
		var timer = Timer.init(loop).resolve();
		timer.start(() -> {
			ticks++;
			log.push("tick " + ticks);
			if (ticks == 3) {
				timer.stop().resolve();
				timer.close(() -> log.push("timer closed"));
			}
		}, 5, 5).resolve();
		var once = Timer.init(loop).resolve();
		once.start(() -> {
			log.push("once");
			once.close(() -> {});
		}, 40).resolve();

		// TCP echo: server and client on the same loop
		var server = Tcp.init(loop).resolve();
		server.bind(SockAddr.ipv4("127.0.0.1", 0).resolve()).resolve();
		var port = server.getSockName().resolve().port;
		check("tcp bound to a port", port != null && port > 0);
		var echoed = "";
		server.listen(r -> {
			r.resolve();
			var conn = Tcp.init(loop).resolve();
			server.accept(conn).resolve();
			conn.readStart(r -> switch r {
				case Ok(buf):
					conn.write([buf], (r, n) -> r.resolve());
				case Error(UV_EOF):
					conn.close(() -> server.close(() -> log.push("server closed")));
				case Error(e):
					throw new LuvException(e);
			});
		});
		var client = Tcp.init(loop).resolve();
		client.connect(SockAddr.ipv4("127.0.0.1", port).resolve(), r -> {
			r.resolve();
			client.write(["hello ", "luv"], (r, n) -> {
				r.resolve();
				log.push("client wrote " + n);
			});
			client.readStart(r -> switch r {
				case Ok(buf):
					echoed += buf.toString();
					if (echoed.length == 9) {
						client.readStop().resolve();
						client.shutdown(r -> client.close(() -> log.push("client closed")));
					}
				case Error(e):
					throw new LuvException(e);
			});
		});

		// file system: write, stat, read back, unlink; a missing file fails with ENOENT
		var dir = Sys.getEnv("TMPDIR");
		if (dir == null) dir = "/tmp";
		var path = dir + "/hxc-luv-" + Std.random(1000000) + ".txt";
		var readBack = "";
		var missing = null;
		File.open(loop, path, [CREAT, WRONLY, TRUNC], [IRUSR, IWUSR], f -> {
			var file = f.resolve();
			file.write(loop, eval.integers.Int64.ofInt(0), [Buffer.fromString("file data")], r -> {
				check("fs write 9 bytes", Std.string(r.resolve()) == "9");
				file.close(loop, r -> {
					r.resolve();
					File.stat(loop, path, r -> {
						var st = r.resolve();
						check("fs stat size", Std.string(st.size) == "9");
						File.open(loop, path, [RDONLY], f -> {
							var file = f.resolve();
							var buf = Buffer.create(64);
							file.read(loop, eval.integers.Int64.ofInt(0), [buf], r -> {
								var n = Std.parseInt(Std.string(r.resolve()));
								readBack = buf.sub(0, n).toString();
								file.close(loop, r -> File.unlink(loop, path, r -> {
									r.resolve();
									log.push("unlinked");
								}));
							});
						});
					});
				});
			});
		});
		File.open(loop, dir + "/hxc-luv-missing/none", [RDONLY], r -> switch r {
			case Ok(_): missing = "opened";
			case Error(e): missing = e == UV_ENOENT ? "UV_ENOENT" : Std.string(e);
		});

		// a child process writing to a pipe
		var out = Pipe.init(loop).resolve();
		var childOut = "";
		var exit = null;
		var proc = Process.spawn(loop, "sh", ["sh", "-c", "echo from child; exit 3"], {
			redirect: [Process.toParentPipe(1, out, false, true, false)],
			onExit: (p, status, signal) -> {
				exit = Std.string(status);
				p.close(() -> {});
			}
		}).resolve();
		check("child pid", proc.pid() > 0);
		out.readStart(r -> switch r {
			case Ok(buf): childOut += buf.toString();
			case Error(UV_EOF): out.close(() -> {});
			case Error(e): throw new LuvException(e);
		});

		// an idle handle runs once per loop iteration
		var idles = 0;
		var idle = Idle.init(loop).resolve();
		idle.start(() -> if (++idles == 10) {
			idle.stop().resolve();
			idle.close(() -> {});
		}).resolve();

		var t0 = Sys.time();
		loop.run(DEFAULT);
		var elapsed = Sys.time() - t0;

		check("timer ticked 3 times, then the one-shot", log.indexOf("tick 3") >= 0 && log.indexOf("once") > log.indexOf("tick 3"));
		check("loop ran at least 40 ms", elapsed >= 0.03);
		check("tcp echo", echoed == "hello luv");
		check("tcp handles closed", log.indexOf("client closed") >= 0 && log.indexOf("server closed") >= 0);
		check("fs read back", readBack == "file data");
		check("fs unlinked", log.indexOf("unlinked") >= 0 && !sys.FileSystem.exists(path));
		check("fs missing file: " + missing, missing == "UV_ENOENT");
		check("child stdout", childOut == "from child\n");
		check("child exit status " + exit, exit == "3");
		check("idle ran 10 times", idles == 10);
		check("loop not alive", !loop.alive());
		check("version " + Version.string(), Version.string().length > 0);
		check("uptime", Resource.uptime().resolve() > 0);
		check("cpus", SystemInfo.cpuInfo().resolve().length > 0);
		check("total memory", Resource.totalMemory() != null);
		Sys.println(failures == 0 ? "luv: ok" : 'luv: $failures failure(s)');
	}
}
