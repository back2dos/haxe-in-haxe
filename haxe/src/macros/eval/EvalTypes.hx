package macros.eval;

class SysExit extends haxe.Exception {
	public final code:Int;

	public function new(code:Int) {
		super("Sys_exit");
		this.code = code;
	}
}
