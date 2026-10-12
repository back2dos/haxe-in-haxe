package haxeshim.sys;

import haxe.ds.*;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxeshim.Errors;
import uv.Uv;

// port: node's child_process (spawn, spawnSync, execSync) becomes libuv's
// uv_spawn (uv.Uv.Process), each synchronous call running a loop of its own
class Exec {

  static public function die(code, ?reason):Dynamic {
    if (reason != null)
      Logger.get().error(reason);
    Sys.exit(code);
    return throw 'unreachable';
  }

  static public function dieFromErrors(errors:ReadOnlyArray<ErrorMessage>):Dynamic {
    var code = null,
        logger = Logger.get();

    for (e in errors)
      logger.error(e.pos.toString() + ': ${e.message}');

    Sys.exit(Errors.getCode(errors));
    return throw 'unreachable';
  }
  static public function gracefully<T>(f:Void->T)
    return
      try f()
      catch (e:Error)
        die(e.code, e.message)
      catch (e:haxe.Exception)
        die(500, e.message)
      catch (e:Dynamic)
        die(500, Std.string(e));

  static public function mergeEnv(env:Env):Map<String, String>
    return env.mergeInto(Sys.environment()).toVars();

  // what node reports for a spawn that failed, e.g. `Error: spawnSync foo ENOENT`
  static function spawnError(cmd:String, e:UvError)
    return 'Error: spawnSync $cmd ${e.name}';

  // runs `cmd` to completion on a loop of its own: the exit code (128 + the
  // signal when killed). `pipes` creates the child's pipes and gets them read.
  static function run(cmd:String, args:Array<String>, cwd:String, env:Env, ?pipes:Loop->{ stdio:Array<StdioSpec>, start:Void->Void, close:Void->Void }):Int {
    var loop = Loop.create(),
        code = -1;
    var p = if (pipes == null) null else pipes(loop);
    function finish() {
      loop.run();
      loop.close();
    }
    var proc = try spawn(loop, cmd, args, { cwd: cwd, env: mergeEnv(env), stdio: if (p == null) null else p.stdio }, (status, signal) ->
      code = if (signal != 0) 128 + signal else status
    ) catch (e:UvError) {
      if (p != null) p.close();
      finish();
      throw e;
    }
    if (p != null) p.start();
    loop.run();
    proc.close();
    finish();
    return code;
  }

  static public function async(cmd:String, cwd:String, args:Array<String>, ?env:Env, ?onExit:Int->Void):Process
    return spawn(Loop.get(), cmd, args, { cwd: cwd, env: mergeEnv(env) }, (status, signal) ->
      if (onExit != null) onExit(if (signal != 0) 128 + signal else status)
    );

  // the commands of the lix npm package: on a Cosmopolitan binary on Windows
  // they run as this binary itself (it has no other name to be found by)
  static final SELF = ['lix', 'haxe', 'haxelib', 'neko'];

  /**
    Spawns `cmd` like `uv.Process.spawn`. On a Cosmopolitan binary on Windows,
    the program is looked up as Windows would (`.exe`, `.com`, then `.cmd` and
    `.bat` through cmd.exe), and paths in the arguments and environment become
    Windows' (`Os.hostPath`).
  **/
  static public function spawn(loop:Loop, cmd:String, args:Array<String>, options:SpawnOptions, onExit:(code:Int, signal:Int) -> Void):Process {
    if (Os.IS_POSIX_ON_WINDOWS) {
      var name = haxe.io.Path.withoutDirectory(cmd).toLowerCase();
      if (cmd.indexOf('/') == -1 && cmd.indexOf('\\') == -1 && SELF.contains(name)) {
        args = ['--run-as', name].concat(args);
        cmd = Sys.programPath();
      }
      else {
        var found = findProgram(cmd);
        if (found == null)
          throw new UvError(-2, 'spawn $cmd');// UV_ENOENT (Cosmopolitan's errno values are POSIX')
        args = found.prefix.concat([for (a in args) Os.hostPath(a)]);
        cmd = found.path;
        if (options.env != null)
          options = {
            cwd: options.cwd,
            stdio: options.stdio,
            // lists such as PATH keep their form: Cosmopolitan converts them
            env: [for (k => v in options.env) k => if (v.indexOf(':') == -1) Os.hostPath(v) else v],
          };
      }
    }
    return Process.spawn(loop, cmd, args, options, onExit);
  }

  // a program in PATH (or at a path) as Windows finds it: its path, and the
  // arguments that come first (cmd.exe /c for scripts); null when there is none
  static function findProgram(cmd:String):Null<{ path:String, prefix:Array<String> }> {
    function file(p:String)
      return sys.FileSystem.exists(p) && !sys.FileSystem.isDirectory(p);
    var candidates =
      if (cmd.indexOf('/') != -1 || cmd.indexOf('\\') != -1) [Os.fromHostPath(cmd)]
      else [for (dir in (Sys.getEnv('PATH') ?? '').split(':')) if (dir != '') '$dir/$cmd'];
    var hasExt = haxe.io.Path.extension(cmd) != '';
    for (ext in if (hasExt) [''] else ['.exe', '.com', '', '.cmd', '.bat'])
      for (c in candidates)
        if (file(c + ext))
          return
            if (ext == '.cmd' || ext == '.bat' || c.endsWith('.cmd') || c.endsWith('.bat'))
              { path: comspec(), prefix: ['/d', '/c', Os.hostPath(c + ext)] };
            else
              { path: c + ext, prefix: [] };
    return null;
  }

  static function comspec()
    return Os.fromHostPath(Sys.getEnv('ComSpec') ?? 'C:\\Windows\\System32\\cmd.exe');

  static function shellArgs(cmd:String)
    return
      if (Os.IS_POSIX_ON_WINDOWS)
        // port: no /bin/sh; a plain command runs directly (as hxc's Sys.command
        // does there), anything else through cmd.exe
        switch posixWords(cmd) {
          case null: { cmd: comspec(), args: ['/d', '/s', '/c', cmd] };
          case words: { cmd: words[0], args: words.slice(1) };
        }
      else if (Os.IS_WINDOWS) { cmd: Sys.getEnv('ComSpec') ?? 'cmd.exe', args: ['/d', '/s', '/c', '"$cmd"'] }
      else { cmd: '/bin/sh', args: ['-c', cmd] };

  /**
    The words of a POSIX shell command, or null when it is more than a plain
    command (hxc/rt/rt_sys.c's posix_words): unquoted `| & ; < > ( ) $ \` * ? [`,
    a leading `#` or `~`, or `=` in the first word.
  **/
  static public function posixWords(c:String):Null<Array<String>> {
    var words = [],
        i = 0,
        n = c.length;
    inline function space(ch:String)
      return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
    while (true) {
      while (i < n && space(c.charAt(i))) i++;
      if (i >= n) break;
      var w = new StringBuf(),
          start = true;
      while (i < n && !space(c.charAt(i))) {
        var ch = c.charAt(i);
        if (ch == "'") {
          var e = c.indexOf("'", i + 1);
          if (e == -1) return null;
          w.add(c.substring(i + 1, e));
          i = e + 1;
        }
        else if (ch == '"') {
          i++;
          while (i < n && c.charAt(i) != '"') {
            var d = c.charAt(i);
            if (d == '$' || d == '`') return null;
            if (d == '\\' && i + 1 < n && '"\\$`'.indexOf(c.charAt(i + 1)) != -1) i++;
            w.add(c.charAt(i++));
          }
          if (i >= n) return null;
          i++;
        }
        else if (ch == '\\') {
          if (i + 1 >= n) return null;
          w.add(c.charAt(i + 1));
          i += 2;
        }
        else {
          if ('|&;<>()$`*?['.indexOf(ch) != -1 || (start && (ch == '#' || ch == '~')) || (words.length == 0 && ch == '=')) return null;
          w.add(ch);
          i++;
        }
        start = false;
      }
      words.push(w.toString());
    }
    return if (words.length == 0) null else words;
  }

  static public function shell(cmd:String, cwd:String, ?env:Env):Outcome<Int, Error> {
    var sh = shellArgs(cmd);
    return
      try switch run(sh.cmd, sh.args, cwd, env) {
        case 0: Success(0);
        case status: Failure(new Error(status, 'Failed to invoke `$cmd` because Error: Command failed: $cmd'));
      }
      catch (e:UvError)
        Failure(new Error('Failed to invoke `$cmd` because ${spawnError(sh.cmd, e)}'));
  }

  static public function sync(cmd:String, cwd:String, args:Array<String>, ?env:Env):Outcome<Int, Error>
    return
      try Success(run(cmd, args, cwd, env))
      catch (e:UvError)
        Failure(new Error('Failed to call $cmd because ${spawnError(cmd, e)}'));

  /** Runs `cmd`, capturing its stdout and (unless `inheritStderr`) its stderr. **/
  static public function eval(cmd:String, cwd:String, ?args:Array<String>, ?env:Env, inheritStderr = false):Outcome<{ status:Int, stdout:String, stderr:String }, Error> {
    var stdout = new BytesBuffer(),
        stderr = new BytesBuffer();
    function capture(loop:Loop) {
      var out = new Pipe(loop),
          err = if (inheritStderr) null else new Pipe(loop);
      function read(pipe:Pipe, into:BytesBuffer)
        pipe.readStart(b -> if (b == null) pipe.close() else into.add(b), _ -> pipe.close());
      return {
        stdio: [Inherit, CreatePipe(out, false, true), if (err == null) Inherit else CreatePipe(err, false, true)],
        start: () -> {
          read(out, stdout);
          if (err != null) read(err, stderr);
        },
        close: () -> {
          out.close();
          if (err != null) err.close();
        }
      }
    }
    return
      try {
        var status = run(cmd, if (args == null) [] else args, cwd, env, capture);
        Success({ status: status, stdout: stdout.getBytes().toString(), stderr: stderr.getBytes().toString() });
      }
      catch (e:UvError)
        Failure(new Error('Failed to call $cmd because ${spawnError(cmd, e)}'));
  }

}
