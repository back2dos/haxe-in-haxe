package hxmc.esx;

// The static part of a markup literal, built once per literal (a static
// final of a generated class): its identity is the literal's, so a
// renderer may compile it once (keyed by the Template) and afterwards only
// read the values of each Esx made from it. Holes are indices into
// Esx.values, in source order.
class Template {
	public final root:TNode;
	// the number of values
	public final holes:Int;
	// where the literal is: file:line (for messages)
	public final source:String;

	public function new(root:TNode, holes:Int, source:String) {
		this.root = root;
		this.holes = holes;
		this.source = source;
	}

	public function toString():String
		return 'Template($source)';
}

enum abstract TKind(Int) {
	// <name attrs>children</name>: an intrinsic element (a lowercase name)
	var Element;
	// <Name props>children</Name>: a component; hole is its factory, a
	// () -> Any that calls it with its props (children included)
	var Component;
	// <>children</>
	var Fragment;
	// static text (entities decoded, whitespace as JSX trims it)
	var Text;
	// {expr} among the children: the value at hole
	var Hole;
}

class TNode {
	public final kind:TKind;
	// Element, Component: the name as written; Text: the text
	public final name:String;
	public final attrs:Array<TAttr>;
	public final children:Array<TNode>;
	// Hole: the value's index; Component: its factory's
	public final hole:Int;

	public function new(kind:TKind, name:String, attrs:Array<TAttr>, children:Array<TNode>, hole:Int) {
		this.kind = kind;
		this.name = name;
		this.attrs = attrs;
		this.children = children;
		this.hole = hole;
	}

	public var text(get, never):String;

	inline function get_text()
		return name;
}

enum abstract TAttrKind(Int) {
	// name="text"
	var Static;
	// name={expr}: the value at hole
	var Dynamic;
	// name alone: true
	var Flag;
	// {...expr}: the fields of the value at hole
	var Spread;
}

class TAttr {
	public final kind:TAttrKind;
	public final name:String;
	// Static: the text
	public final value:String;
	public final hole:Int;

	public function new(kind:TAttrKind, name:String, value:String, hole:Int) {
		this.kind = kind;
		this.name = name;
		this.value = value;
		this.hole = hole;
	}
}
