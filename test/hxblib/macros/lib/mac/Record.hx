package mac;

@:build(mac.Macros.addGetters())
class Record {
	var name:String;
	var count:Int;

	public function new(name, count) {
		this.name = name;
		this.count = count;
	}
}

@:autoBuild(mac.Macros.addGetters())
interface AutoGetters {}
