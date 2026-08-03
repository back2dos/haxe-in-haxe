package unit.moduleload;

class ResolverHelper {
	public function new() {}
	public function value():Int { return 1; }
	public static function create():ResolverHelper { return new ResolverHelper(); }
}
