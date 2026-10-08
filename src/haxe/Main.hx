package haxe;

import compiler.Args;
import compiler.HighLevel;
import compiler.io.CompilerIo;
import compiler.io.CompilerOutput;
import context.Common;
import context.Parallel.ManagedPool;
import core.Timer;
import core.ds.TaskPool;

// Batch entry from haxe/src/compiler/haxe.ml, server/server.ml:create_request_scope
// and server/serverCompilationContext.ml:create. Client and server modes
// (--connect, --wait, --server-connect) belong to the display/server milestone.
class Main {
	static function main():Void {
		#if js
		// Like OCaml, only record backtraces with OCAMLRUNPARAM=b: the compiler
		// throws exceptions for ordinary control flow (see runtime/hl for HashLink).
		var ocamlrunparam = Sys.getEnv("OCAMLRUNPARAM");
		if (ocamlrunparam == null || ocamlrunparam.indexOf("b") < 0) js.Syntax.code("Error.stackTraceLimit = 0");
		#end
		core.ds.GcPolicy.init();
		Sys.exit(run(Sys.args()));
	}

	// Upstream assigns these forward references during OCaml module
	// initialization. Static initialization order differs between Haxe
	// targets, so they are (re)assigned once all statics are initialized.
	public static function initHooks():Void {
		core.Type.initialize();
		core.TUnification.initHooks();
		context.AbstractCast.install(); // the JVM initializes classes lazily
		typing.Typer.initialize();
		typing.TyperEntry.initHooks();
		typing.TypeloadFunction.initHooks();
		typing.Generic.initHooks();
		optimization.Analyzer.initHooks();
	}

	public static function run(args:Array<String>):Int {
		initHooks();
		// The port is executed by a host compiler, so the std location of the
		// executable is not meaningful; HAXE_IN_HAXE_STD_PATH overrides the
		// HAXE_STD_PATH the host may have rewritten for --run.
		var std = Sys.getEnv("HAXE_IN_HAXE_STD_PATH");
		if (std != null && std != "" && Sys.getEnv("HAXE_STD_PATH") != std) Sys.putEnv("HAXE_STD_PATH", std);
		else if (Sys.getEnv("HAXE_STD_PATH") == null && sys.FileSystem.exists("haxe/std")) Sys.putEnv("HAXE_STD_PATH", sys.FileSystem.fullPath("haxe/std"));
		var parsedArgs = Args.parseArgs(args);
		var requestArgs = try Args.expandArgs(parsedArgs) catch (e:core.ds.ArgumentError) return badArg(e.message);
		if (requestArgs.connectArg != null) return badArg("--connect is outside the batch HXB milestone");
		switch requestArgs.serverMode {
			case SMNone:
			case _: return badArg("Compilation server modes are outside the batch HXB milestone");
		}
		// We are a normal non-server compilation.
		var pool = ManagedPool.create(function() return new TaskPool(TaskPool.recommendedDomainCount() - 1));
		var version:core.Globals.CompilerVersion = {
			version: core.Globals.version,
			major: core.Globals.versionMajor,
			minor: core.Globals.versionMinor,
			revision: core.Globals.versionRevision,
			pre: core.Globals.versionPre,
			extra: null
		};
		// Compilation-cache services are deferred; source-only batch loading never
		// dereferences cs. All active shared context fields follow upstream defaults.
		var sctx = {
			isServer: false,
			version: version,
			verbose: false,
			cs: null,
			classPaths: new core.ds.Hashtbl<String, Array<String>>(0),
			changedDirectories: new core.ds.Hashtbl<String, Array<Dynamic>>(0),
			compilationStep: 0,
			delays: new Array<Void->Void>(),
			wasCompilation: false,
			macroContextSetup: false,
			currentStdin: null,
			persistentCwd: null,
			pool: pool
		};
		var io = CompilerIo.createStdioIo();
		lastRequest = {
			stats: Stats.create(),
			timerCtx: Timer.makeContext(Timer.make(["other"])),
			cancellationRequested: false,
			io: io,
			resultHandler: CompilerOutput.createCliResultHandler(io)
		};
		var code = try HighLevel.entry(sctx, lastRequest, requestArgs) catch (e:core.ds.ArgumentError) {
			ManagedPool.release(pool);
			return badArg(e.message);
		} catch (e:Dynamic) {
			ManagedPool.release(pool);
			reportInternalError(e);
			return 1;
		}
		ManagedPool.release(pool);
		return code;
	}

	public static var lastRequest(default, null):Null<RequestScope>;

	static function badArg(msg:String):Int {
		Sys.stderr().writeString(msg + "\n");
		return 1;
	}

	// Upstream reports an uncaught OCaml exception with its backtrace.
	static function reportInternalError(e:Dynamic):Void {
		var stack = Std.isOfType(e, haxe.Exception) ? (cast(e, haxe.Exception)).stack : haxe.CallStack.exceptionStack();
		Sys.stderr().writeString(haxe.CallStack.toString(stack) + "\n" + Std.string(e) + "\n");
		switch core.ds.ExceptionTools.unification(e) {
			case Some(errors):
				for (error in errors) Sys.stderr().writeString(core.Error.unifyErrorMsg(core.TPrinting.printContext(), error) + "\n");
			case None:
		}
	}
}
