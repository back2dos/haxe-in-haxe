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
    var proc = try Process.spawn(loop, cmd, args, { cwd: cwd, env: mergeEnv(env), stdio: if (p == null) null else p.stdio }, (status, signal) ->
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
    return Process.spawn(Loop.get(), cmd, args, { cwd: cwd, env: mergeEnv(env) }, (status, signal) ->
      if (onExit != null) onExit(if (signal != 0) 128 + signal else status)
    );

  static function shellArgs(cmd:String)
    return
      if (Os.IS_WINDOWS) { cmd: Sys.getEnv('ComSpec') ?? 'cmd.exe', args: ['/d', '/s', '/c', '"$cmd"'] }
      else { cmd: '/bin/sh', args: ['-c', cmd] };

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
