// hxmc: haxe/upstream/std/eval/_std/haxe/NativeStackTrace.hx without native stack traces

package haxe;

import haxe.CallStack.StackItem;

@:noCompletion
class NativeStackTrace {
	@:ifFeature('haxe.NativeStackTrace.exceptionStack')
	static public inline function saveStack(exception:Any):Void {}

	static public function callStack():Any
		return null;

	static public function exceptionStack():Any
		return null;

	static public function toHaxe(native:Any, skip:Int = 0):Array<StackItem>
		return [];
}
