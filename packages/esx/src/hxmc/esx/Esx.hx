package hxmc.esx;

import haxe.macro.Expr;
import hxmc.esx.Template;

// A markup literal's value: its Template (the same object every time the
// literal runs) and the values of its holes, evaluated now. Write markup
// in a class that implements Markup (every literal in it is compiled), or
// through esx(<...>):
//
//   class App implements Markup {
//     static function view(name:String, items:Array<String>)
//       return <div class="list">
//         <h1>Hello {name}!</h1>
//         {[for (i in items) <li>{i}</li>]}
//         <Button label="OK" onClick={() -> trace("ok")}/>
//       </div>;
//   }
//
// Lowercase names are intrinsic elements (a renderer's: strings), others
// components: Button(props) called by the factory at the Component's hole,
// props an object of its attributes (and children: the content, as an
// Esx), checked against Button's argument by Haxe. Text is trimmed as JSX
// trims it; {expr} children and attribute values are holes.
class Esx {
	public final template:Template;
	public final values:Array<Any>;

	public function new(template:Template, values:Array<Any>) {
		this.template = template;
		this.values = values;
	}

	// compiles a markup literal: esx(<div>{x}</div>)
	public static macro function esx(e:Expr):Expr
		return hxmc.esx.MarkupMacro.transform(e);

	// HTML for the intrinsic elements (components called, their results
	// rendered the same way when Esx; holes as text): tests, server output
	public function toHtml():String {
		var b = new StringBuf();
		html(template.root, b);
		return b.toString();
	}

	function html(n:TNode, b:StringBuf) {
		switch n.kind {
			case Text:
				b.add(escape(n.text));
			case Hole:
				value(values[n.hole], b);
			case Fragment:
				for (c in n.children)
					html(c, b);
			case Component:
				var f:Void->Any = values[n.hole];
				value(f(), b);
			case Element:
				b.add("<" + n.name);
				for (a in n.attrs)
					switch a.kind {
						case Static: b.add(' ${a.name}="${escape(a.value)}"');
						case Flag: b.add(' ${a.name}');
						case Dynamic:
							var v:Dynamic = values[a.hole];
							if (v == null || v == false || Reflect.isFunction(v)) continue;
							b.add(v == true ? ' ${a.name}' : ' ${a.name}="${escape(Std.string(v))}"');
						case Spread:
							var o:Dynamic = values[a.hole];
							for (f in Reflect.fields(o))
								b.add(' $f="${escape(Std.string(Reflect.field(o, f)))}"');
					}
				if (n.children.length == 0 && VOID.contains(n.name)) {
					b.add(">");
					return;
				}
				b.add(">");
				for (c in n.children)
					html(c, b);
				b.add("</" + n.name + ">");
		}
	}

	static final VOID = ["br", "hr", "img", "input", "meta", "link"];

	static function value(v:Dynamic, b:StringBuf) {
		if (v == null || v == false || v == true) return;
		if (Std.isOfType(v, Esx)) b.add((v : Esx).toHtml()) else if (Std.isOfType(v, Array)) for (x in (v : Array<Dynamic>))
			value(x, b) else b.add(escape(Std.string(v)));
	}

	static function escape(s:String):String
		return StringTools.htmlEscape(s, true);
}
