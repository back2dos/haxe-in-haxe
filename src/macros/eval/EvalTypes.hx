package macros.eval;

/** haxe/src/macro/eval/evalTypes.ml. **/
class SysExit extends haxe.Exception {
	public final code:Int;

	public function new(code:Int) {
		super("Sys_exit");
		this.code = code;
	}
}
