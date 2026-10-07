package core.ds;

/** Shared representation of OCaml Not_found. */
class NotFound extends haxe.Exception {
 // Thrown as a shared instance: constructing a haxe.Exception captures a stack
 // trace, and lookups throw Not_found tens of thousands of times per build.
 public static final instance = new NotFound();
 public function new() super("Not_found");
}
