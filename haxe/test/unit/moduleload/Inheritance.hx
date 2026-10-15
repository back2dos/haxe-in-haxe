package unit.moduleload;

class Base {
	public function baseValue():Int return 1;
}

interface IThing {
	public function thingValue():Int;
}

class Derived extends Base implements IThing {
	public function thingValue():Int return baseValue();
}
