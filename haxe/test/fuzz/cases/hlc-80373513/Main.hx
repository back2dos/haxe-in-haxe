// seed 80373513, diff:hlc, reduced. hl2c names types in the order of extlib's
// PMap.mapi, a post-order walk of the tree: the native array of (String,String):String
// takes the short digest (`t$array_t$fun_2e5590a`) before the function type itself,
// which gets the full one; in sorted order the names were swapped.

import H;
import p.M1;

abstract class C28 extends C21 {}

class Main {
	public static function fn53(a54:String, a55:Bool):String {
		var v211:Array<(String, String) -> String> = (a55 ? ([] : Array<(String, String) -> String>) : ([] : Array<(String, String) -> String>));
		return "";
	}
	public static function fn56(a57:() -> Int, a58:Array<String>):Int {
		return 0;
	}
	public static function main():Void {
		H.out("start");
	}
}
