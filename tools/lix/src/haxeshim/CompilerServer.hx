package haxeshim;

import haxe.io.Bytes;
import haxeshim.scope.Scope;
import haxeshim.sys.Exec;
import hxcoro.task.ICoroNode;
import uv.Reader;
import uv.Uv;


enum ServerKind {
  Port(num:Int);
  Stdio;
  Connect(hostPort:String);
}

typedef HostPort = {
  var host(default, null):String;
  var port(default, null):Int;
}

// a running compiler of some version (see `connect`)
private typedef Waiting = {
  var version(default, null):String;
  var port(default, null):Int;
  var proc(default, null):Process;
  var alive:Bool;
}

/**
 * This beauty exists because we may need to hotswap the running haxe version.
 */
// port: node's net/child_process streams and tink Futures become libuv handles
// (uv.Uv) driven by hxcoro coroutines on the libuv loop (uv.Coro)
class CompilerServer {

  var scope:Scope;
  var lastVersion:String;
  var args:Array<String>;
  var loop = Loop.get();
  var cleanups:Array<Void->Void> = [];

  // a port nobody listens on (node: listen on port 0, close, use its number)
  function freePort():Int {
    var test = new Tcp(loop);
    test.bind('127.0.0.1', 0);
    var port = test.port();
    test.close();
    return port;
  }

  public static function extractMode(args:Array<String>):Null<{kind:ServerKind, args:Array<String>}> {
    for (flag in ['--server-listen', '--wait']) {
      var idx = args.indexOf(flag);
      if (idx >= 0 && idx < args.length - 1) {
        var value = args.splice(idx, 2).pop();
        var kind:ServerKind = switch value {
          case 'stdio':
            Stdio;
          case v:
            switch Std.parseInt(v) {
              case null:
                Exec.die(422, 'invalid $flag argument: $value');
              case p:
                Port(p);
            }
        }
        return { kind: kind, args: args };
      }
    }

    var connectIdx = args.indexOf('--server-connect');
    if (connectIdx >= 0 && connectIdx < args.length - 1) {
      var target = args.splice(connectIdx, 2).pop();
      return { kind: Connect(target), args: args };
    }

    return null;
  }

  public function new(kind:ServerKind, scope, args) {
    this.args = args;
    this.scope = scope;

    try uv.Coro.run(node -> {
      switch kind {
        case Port(port):
          waitOnPort(node, port);
        case Stdio:
          stdio(node);
        case Connect(hostPort):
          serverConnect(hostPort);
      }
    })
    catch (e:Dynamic)
      Exec.die(500, Std.string(e));
    exit();
  }

  function exit(code = 0) {
    for (f in cleanups) try f() catch (e:Dynamic) {}
    Sys.exit(code);
  }

  static function parseHostPort(s:String):HostPort {
    var colon = s.lastIndexOf(':');
    if (colon == -1) {
      var port = Std.parseInt(s);
      if (port == null) Exec.die(422, 'Invalid port: $s');
      return { host: '127.0.0.1', port: port };
    }
    var port = Std.parseInt(s.substr(colon + 1));
    if (port == null) Exec.die(422, 'Invalid port in: $s');
    return { host: s.substr(0, colon), port: port };
  }

  static function frame(payload:Bytes):Bytes {
    var ret = Bytes.alloc(4 + payload.length);
    ret.setInt32(0, payload.length);
    ret.blit(4, payload, 0, payload.length);
    return ret;
  }

  static function concat(a:Bytes, b:Bytes) {
    var ret = Bytes.alloc(a.length + b.length);
    ret.blit(0, a, 0, a.length);
    ret.blit(a.length, b, 0, b.length);
    return ret;
  }

  function handleIntSignals() {
    //See http://stackoverflow.com/a/31562361/111466

    for (signum in [Signal.SIGINT, Signal.SIGTERM]) {// catch ctrl-c, catch kill
      var s = new Signal(loop);
      s.start(signum, _ -> exit());
      s.unref();
    }
  }

  function watchConfig() {
    var watcher = new FsWatcher(loop);
    watcher.unref();
    watcher.start(scope.configFile, function () {
      var max = 10;
      function attempt(count = 0) {
        try scope.reload()
        catch (e:Dynamic) {
          if (count >= max) {
            Logger.get().error('Reloading .haxerc after change detected failed $max times!');
            exit(500);
          }
          else {
            var t = new Timer(loop);
            t.start(() -> {
              t.close();
              attempt(count + 1);
            }, 100);
          }
        }
      }
      attempt();
    });
  }

  // connects to host:port (a name or an IP address), with up to 10 attempts 100ms apart
  @:coroutine function connectToHost(host:String, port:Int):Tcp {
    var ip = try new sys.net.Host(host).toString() catch (e:Dynamic) host;
    var max = 10;
    var attempt = 1;
    while (true) {
      var cnx = new Tcp(loop);
      var status = uv.Coro.await(done -> cnx.connect(ip, port, status -> done(status, null)));
      if (status >= 0)
        return cnx;
      cnx.close();
      if (attempt >= max)
        throw 'Failed to connect to $host:$port after $max attempts because ${new UvError(status).message}';
      attempt++;
      hxcoro.Coro.delay(100);
    }
  }

  function spawn(version:String, extraArgs:Array<String>, ?stdio:Array<StdioSpec>, onExit:Int->Void):Process {
    var installation = scope.getInstallation(version);
    return Exec.spawn(loop, installation.compiler, this.args.concat(extraArgs), {
      cwd: scope.cwd,
      env: Exec.mergeEnv(installation.env),
      stdio: stdio,
    }, (code, _) -> onExit(code));
  }

  // --server-connect: the compiler of the current version and its connection to us
  var connChild:Null<Process>;
  var connChildAlive = false;
  var haxeSocket:Null<Reader>;

  @:coroutine function ensureHaxe(version:String):Reader {
    if (connChild != null && connChildAlive && haxeSocket != null && version == lastVersion)
      return haxeSocket;

    if (connChild != null && connChildAlive) connChild.kill();
    if (haxeSocket != null) haxeSocket.stream.close();
    connChild = null;
    haxeSocket = null;

    lastVersion = version;

    var port = freePort();
    var server = new Tcp(loop);
    server.bind('127.0.0.1', port);
    var accepted:Tcp = uv.Coro.await(done -> {
      var finished = false;
      function fail(e:Dynamic) {
        if (finished) return;
        finished = true;
        server.close();
        if (connChild != null && connChildAlive) connChild.kill();
        done(null, new haxe.Exception(Std.string(e)));
      }
      server.listen(status -> {
        if (finished) return;
        if (status < 0) {
          fail(new UvError(status, 'accept').message);
          return;
        }
        var sock = new Tcp(loop);
        server.accept(sock);
        finished = true;
        server.close();
        done(sock, null);
      });
      try {
        connChildAlive = true;
        connChild = spawn(version, ['--server-connect', Std.string(port)], code -> {
          connChildAlive = false;
          fail('haxe exited before connecting');
        });
      }
      catch (e:Dynamic) {
        connChildAlive = false;
        fail(e);
      }
    });
    return haxeSocket = new Reader(accepted);
  }

  @:coroutine function serverConnect(hostPort:String) {
    watchConfig();

    var target = parseHostPort(hostPort);
    var ideSocket:Reader = null;

    function cleanup() {
      if (connChild != null && connChildAlive) connChild.kill();
      if (haxeSocket != null) haxeSocket.stream.close();
      if (ideSocket != null) ideSocket.stream.close();
    }

    cleanups.push(cleanup);
    handleIntSignals();

    ensureHaxe(scope.haxeInstallation.version);
    ideSocket = new Reader(connectToHost(target.host, target.port));

    while (true) {
      var data = try ideSocket.readFrame() catch (e:Dynamic) break;
      var ctx = parseArgs(data);

      var haxe = try ensureHaxe(ctx.version) catch (e:Dynamic) break;
      var resolved = switch (try Success(scope.resolve(ctx.args)) catch (e:Dynamic) Failure(Error.of(e))) {
        case Success(v): v;
        case Failure(e): Exec.die(e.code, e.message);
      }
      var payload = concat(Bytes.ofString(resolved.join('\n')), ctx.postfix);
      haxe.stream.write(frame(payload));
      var response = try haxe.readFrame() catch (e:Dynamic) break;
      ideSocket.stream.write(frame(response));
    }
    cleanup();
  }

  @:coroutine function stdio(node:ICoroNode) {
    watchConfig();

    var child:Process = null;
    var childIn:Pipe = null;

    function quit() {
      if (child != null) child.kill();
    }

    cleanups.push(quit);
    handleIntSignals();

    // port: node's process.stdin
    var stdin = new Reader(Pipe.open(loop, 0));

    function processData(data:Bytes) {

      var ctx = parseArgs(data);

      if (child == null || ctx.version != lastVersion) {
        if (child != null) {
          child.kill();
          childIn.close();
        }

        lastVersion = ctx.version;

        var input = new Pipe(loop);
        var proc = null;
        proc = spawn(ctx.version, ['--server-listen', 'stdio'], [CreatePipe(input, true, false), Inherit, Inherit], _ -> {
          if (child == proc) child = null;
          proc.close();
        });
        child = proc;
        childIn = input;
      }

      switch (try Success(scope.resolve(ctx.args)) catch (e:Dynamic) Failure(Error.of(e))) {
        case Failure(e):
          Exec.die(e.code, e.message);
        case Success(args):
          var first = Bytes.ofString(args.join('\n'));
          childIn.write(frame(concat(first, ctx.postfix)));
      }

    }

    while (true) {
      var data = try stdin.readFrame() catch (e:Dynamic) break;
      processData(data);
    }
    quit();
  }

  function parseArgs(raw:Bytes) {
    var postfix = Bytes.alloc(0);
    for (i in 0...raw.length)
      if (raw.get(i) == 0x01) {
        postfix = raw.sub(i, raw.length - i);
        raw = raw.sub(0, i);
        break;
      }

    var args = raw.toString().split('\n');

    var version =
      switch args.indexOf('--haxe-version') {
        case -1:
          if (lastVersion == null)
            scope.haxeInstallation.version;
          else
            lastVersion;
        case v:
          args.splice(v, 2).pop();
      }

    return {
      version: version,
      args: args,
      postfix: postfix,
    }
  }

  @:coroutine function waitOnPort(node:ICoroNode, port:Int) {
    function quit() {
      if (waiting != null && waiting.alive) waiting.proc.kill();
    }

    cleanups.push(quit);
    handleIntSignals();

    var server = new Tcp(loop);
    server.bind('0.0.0.0', port);
    server.listen(status -> if (status >= 0) {
      var cnx = new Tcp(loop);
      server.accept(cnx);
      node.async(_ -> handleConnection(cnx));
    });
    // serve until killed
    uv.Coro.await(_ -> {});
  }

  @:coroutine function handleConnection(cnx:Tcp) {
    var reader = new Reader(cnx);
    function end(message:String) {
      cnx.write(Bytes.ofString(message + '\n' + String.fromCharCode(2) + '\n'));
      cnx.shutdown(_ -> cnx.close());
    }
    var request = try reader.readUntil(0) catch (e:Dynamic) {
      cnx.close();
      return;
    }
    reader.stream.readStop();
    var args = request.toString().split('\n');
    var version =
      switch args.indexOf('--haxe-version') {
        case -1:
          if (lastVersion == null)
            scope.haxeInstallation.version;
          else
            lastVersion;
        case v:
          args.splice(v, 2).pop();
      }

    var compiler = try connect(version) catch (e:Dynamic) {
      end(Error.of(e).message);
      return;
    }

    switch (try Success(scope.resolve(args)) catch (e:Dynamic) Failure(Error.of(e))) {
      case Failure(e):
        compiler.close();
        end(e.message);
      case Success(resolved):
        compiler.write(Bytes.ofString(resolved.join('\n') + String.fromCharCode(0)));
        // compiler.pipe(cnx, { end: true })
        compiler.readStart(data ->
          if (data != null) cnx.write(data)
          else {
            compiler.close();
            cnx.shutdown(_ -> cnx.close());
          }
        , _ -> {
          compiler.close();
          cnx.close();
        });
    }
  }

  var waiting:Null<Waiting>;
  var starting:Null<{ version:String, ready:Array<Void->Void> }>;

  @:coroutine function disconnect() {
    if (waiting != null) {
      if (waiting.alive) waiting.proc.kill();
      waiting = null;
      hxcoro.Coro.delay(500);
    }
  }

  @:coroutine function connect(version:String):Tcp {

    // another connection is starting a compiler: wait for it
    while (starting != null) {
      var s = starting;
      uv.Coro.await(done -> s.ready.push(() -> done(null, null)));
    }

    if (version != lastVersion || waiting == null || !waiting.alive) {
      lastVersion = version;
      var s = starting = { version: version, ready: [] };
      try {
        disconnect();
        var port = freePort();
        var w:Waiting = null;
        w = {
          version: version,
          port: port,
          proc: spawn(version, ['--server-listen', Std.string(port)], code -> {
            w.alive = false;
            w.proc.close();
            if (waiting == w) waiting = null;
          }),
          alive: true,
        };
        waiting = w;
      }
      catch (e:Dynamic) {
        starting = null;
        for (f in s.ready) f();
        throw e;
      }
      starting = null;
      for (f in s.ready) f();
    }

    try return connectToHost('127.0.0.1', waiting.port)
    catch (e:Dynamic) throw new Error(Std.string(e));
  }
}
