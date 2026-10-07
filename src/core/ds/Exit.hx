package core.ds;
/** Shared exception used for the OCaml Exit control flow. */
class Exit extends haxe.Exception {
 // Shared instance; see NotFound.
 public static final instance = new Exit();
 public function new() super("Exit");
}
