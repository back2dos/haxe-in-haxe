package macros.eval;

import core.Globals;
import core.Globals.Pos;
import core.TType;
import core.ds.NotFound;
import macros.eval.EvalContext;
import macros.eval.EvalValue;
import macros.eval.EvalExceptions;
import macros.eval.EvalDebugMisc;
import macros.eval.EvalJitContext;
import macros.eval.EvalEmitter.Emitter;

class EvalDebug {
	public static function isCaught(eval:Eval, v:Value):Bool {
		for (path in eval.caughtTypes.keys()) if (EvalContext.is(v, path)) return true;
		return false;
	}

	// port: OCaml's physical equality on values: the boxed values by reference,
	// the immediate ones (and the host's unboxed numbers) by value
	static function physEq(a:Value, b:Value):Bool {
		return switch [a, b] {
			case [VString(s1), VString(s2)]: s1 == s2;
			case [VEnumValue(e1), VEnumValue(e2)]: e1 == e2;
			case [VObject(o1), VObject(o2)]: o1 == o2;
			case [VInstance(i1), VInstance(i2)]: i1 == i2;
			case [VArray(a1), VArray(a2)]: a1 == a2;
			case [VVector(v1), VVector(v2)]: v1 == v2;
			case [VPrototype(p1), VPrototype(p2)]: p1 == p2;
			case [VLazy(l1), VLazy(l2)]: l1 == l2;
			case [VLazy(_), _] | [_, VLazy(_)]: false;
			case _: EvalValueTools.equals(a, b);
		}
	}

	/** Checks debug state and calls what's needed. **/
	public static function runLoop(run:Env->Value, env:Env):Value {
		var eval = env.envEval;
		function checkBreakpoint() {
			if (eval.breakpoint.bpstate == BPHit && env.envDebug.line != eval.breakpoint.bpline) eval.breakpoint.bpstate = BPEnabled;
		}
		switch eval.debugState {
			case DbgRunning:
				checkBreakpoint();
				return run(env);
			case DbgNext(env2, p):
				var b = core.display.DisplayPosition.enclosesPosition(env.envDebug.debugPos, p);
				function isOnStack(env:Env):Bool {
					return switch env.envParent {
						case null: false;
						case env: env == env2 || isOnStack(env);
					}
				}
				if (isOnStack(env) || b) return run(env) else {
					eval.debugState = DbgWaiting;
					return runLoop(run, env);
				}
			case DbgFinish(env2):
				if (env2 != env) return run(env) else {
					eval.debugState = DbgWaiting;
					return runLoop(run, env);
				}
			case DbgStep:
				eval.debugState = DbgWaiting;
				return run(env);
			case DbgWaiting:
				eval.debugChannel.receive();
				return runLoop(run, env);
		}
	}

	public static function debugLoop(jit:JitContext, conn:DebugConnection, e:TExpr, f:Emitter):Emitter {
		var ctx = jit.ctx;
		// port: a snapshot of the scope stack (an immutable list upstream)
		var scopes = jit.scopes.copy();
		var coords = syntax.Lexer.getPosCoords(e.epos);
		var line = coords.lineStart, col1 = coords.columnStart;
		function columnMatches(breakpoint:Breakpoint):Bool {
			return switch breakpoint.bpcolumn {
				case BPAny: true;
				case BPColumn(i): i == col1;
			}
		}
		function conditionHolds(env:Env, breakpoint:Breakpoint):Bool {
			return switch breakpoint.bpcondition {
				case null: true;
				case e:
					switch EvalDebugMisc.safeCall(env.envEval, EvalDebugMisc.exprToValueSafe.bind(ctx, env), e) {
						case VTrue: true;
						case _: false;
					}
			}
		}
		function debuggerCatches(eval:Eval, v:Value):Bool {
			return switch ctx.debug.exceptionMode {
				case CatchAll: true;
				case CatchUncaught: !(isCaught(eval, v));
				case CatchNone: false;
			}
		}
		/* Checks if we hit a breakpoint, runs the code if not. */
		function runCheckBreakpoint(env:Env):Value {
			var eval = env.envEval;
			try {
				var h = ctx.debug.breakpoints.find(env.envInfo.pfileUnique);
				var breakpoint = h.find(env.envDebug.line);
				switch breakpoint.bpstate {
					case BPEnabled if (columnMatches(breakpoint) && conditionHolds(env, breakpoint)):
						breakpoint.bpstate = BPHit;
						eval.breakpoint = breakpoint; /* TODO: per-thread... */
						conn.bpStop(ctx.debug);
						eval.debugState = DbgWaiting;
						return runLoop(runCheckBreakpoint, env);
					case _:
						throw NotFound.raise();
				}
			} catch (_:NotFound) {
				try {
					return f(env);
				} catch (exc:RunTimeException) {
					var v = exc.value;
					if (debuggerCatches(env.envEval, v) && !physEq(eval.caughtException, v)) {
						eval.caughtException = v;
						conn.excStop(ctx.debug, v, e.epos);
						eval.debugState = DbgWaiting;
						return runLoop(runCheckBreakpoint, env);
					}
					throw exc;
				} catch (_:BreakHere) {
					conn.bpStop(ctx.debug);
					eval.debugState = DbgWaiting;
					return runLoop(_ -> VNull, env);
				} catch (exc:Return) {
					eval.lastReturn = exc.value;
					throw exc;
				}
				/* | Return _ | Break | Continue | Sys_exit _ | RunTimeException _ as exc ->
					raise exc
				| exc ->
					throw (EvalString.vstring (EvalString.create_ascii (Printexc.to_string exc))) e.epos; */
			}
		}
		/* Sets the environmental debug data, then executes the debug loop. */
		function runSet(env:Env):Value {
			env.envDebug.scopes = scopes;
			env.envDebug.line = line;
			env.envDebug.debugPos = e.epos;
			env.envDebug.debugExpr = EvalValueTools.sExprPretty(e);
			return runLoop(runCheckBreakpoint, env);
		}
		return runSet;
	}
}
