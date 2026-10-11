package core.ds;

// port: OCaml Invalid_argument.
class InvalidArgument extends haxe.Exception {
	public function new(message:String) super(message);
}
