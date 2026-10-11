package core.ds;

// port: OCaml Int32.of_string (runtime/ints.c), as OcamlInt64.parse with 32 bits.
class OcamlInt32 {
	public static function ofString(value:String):Int return OcamlInt64.parse(value, 32).low;
}
