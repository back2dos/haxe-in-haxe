package pack;

/** Other docs. **/
class Other {
	public static function value() return 42;

	public var field:Int = 1;
}

typedef T = {a:Int, ?b:String};

enum E {
	A;
	B(x:Int);
}

abstract Abs(Int) from Int {
	public function get() return this;
}
