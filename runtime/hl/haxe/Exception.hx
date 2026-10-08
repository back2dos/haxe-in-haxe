// Copy of haxe/std/hl/_std/haxe/Exception.hx for the compiler's HashLink build;
// changes: the captureStack switch, used by the constructor and thrown().
package haxe;

@:coreApi
class Exception {
	public var message(get,never):String;
	public var stack(get,set):CallStack;
	public var previous(get,never):Null<Exception>;
	public var native(get,never):Any;

	@:noCompletion var __exceptionMessage:String;
	@:noCompletion var __exceptionStack:Null<CallStack>;
	@:noCompletion var __nativeStack:hl.NativeArray<#if (hl_ver >= "1.12.0") haxe.NativeStackTrace.Symbol #else hl.Bytes #end>;
	@:noCompletion @:ifFeature("haxe.Exception.get_stack") var __skipStack:Int = 0;
	@:noCompletion var __nativeException:Any;
	@:noCompletion var __previousException:Null<Exception>;
	@:noCompletion var __customStack:Null<String>;

	static function caught(value:Any):Exception {
		// Std.downcast is a single type check; Std.isOfType goes through a Dynamic class
		var e:Null<Exception> = Std.downcast(cast value, Exception);
		if(e != null) {
			return e;
		} else {
			var e = new ValueException(value, null, value);
			// Undo automatic __shiftStack()
			e.__unshiftStack();
			return e;
		}
	}

	static function thrown(value:Any):Any {
		var result:Any;
		var ex:Null<Exception> = Std.downcast(cast value, Exception);
		if(ex != null) {
			result = ex.native;
		} else {
			var e = new ValueException(value);
			e.__shiftStack();
			result = e;
		}
		// `throw v` compiles to `throw Exception.thrown(v)`: throwing here with
		// rethrow skips libhl's native stack capture for the throw.
		if(!captureStack) hl.Api.rethrow(result);
		return result;
	}

	// Like OCaml, only record backtraces when OCAMLRUNPARAM contains "b": the
	// compiler throws exceptions for ordinary control flow.
	static final captureStack:Bool = {
		var v = Sys.getEnv("OCAMLRUNPARAM");
		v != null && v.indexOf("b") >= 0;
	}

	public function new(message:String, ?previous:Exception, ?native:Any) {
		__exceptionMessage = message;
		__previousException = previous;
		if(native != null) {
			if(captureStack) __nativeStack = NativeStackTrace.exceptionStack();
			__nativeException = native;
		} else {
			if(captureStack) __nativeStack = NativeStackTrace.callStack();
			__nativeException = this;
		}
	}

	function unwrap():Any {
		return __nativeException;
	}

	public function toString():String {
		return message;
	}

	public function details():String {
		return inline CallStack.exceptionToString(this);
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	inline function __shiftStack():Void {
		__skipStack++;
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	inline function __unshiftStack():Void {
		__skipStack--;
	}

	function get_message():String {
		return __exceptionMessage;
	}

	function get_previous():Null<Exception> {
		return __previousException;
	}

	final function get_native():Any {
		return __nativeException;
	}

	function get_stack():CallStack {
		return switch __exceptionStack {
			case null: __exceptionStack = __nativeStack == null ? [] : NativeStackTrace.toHaxe(__nativeStack, __skipStack);
			case s: s;
		}
	}

	function set_stack(stack:CallStack) {
		__customStack = CallStack.toString(stack);
		return __exceptionStack = stack;
	}
}
