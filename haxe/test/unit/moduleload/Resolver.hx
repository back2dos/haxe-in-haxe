package unit.moduleload;

class Resolver {
	public var count:Int;
	public var ratio:Float;
	public var enabled:Bool;
	public var label:String;
	public var nothing:Void;
	public var anything:Dynamic;
	public var helper:ResolverHelper;
	public function run():Int {
		var value:ResolverHelper = new ResolverHelper();
		return value.value();
	}
	public function fromStatic():ResolverHelper { return ResolverHelper.create(); }
}
