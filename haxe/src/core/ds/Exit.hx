package core.ds;

// port: OCaml Exit, used for control flow.
class Exit extends haxe.Exception {
	// port: shared instance; see NotFound.
	public static final instance = new Exit();

	// port: throw site helper: `throw X.raise()`. On HashLink the shared instance is
	// thrown with rethrow, which skips libhl's native stack capture per throw.
	public static inline function raise():Exit {
		#if hl hl.Api.rethrow(instance); #end
		return instance;
	}

	// port: Printexc.to_string Exit
	public function new() super("Stdlib.Exit");
}
