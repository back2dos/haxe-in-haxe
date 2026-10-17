import hxmc.esx.*;
import hxmc.esx.Template;

// hxmc.esx's tests, on Eval (make esx-check):
//
//   <tool> -cp packages/esx/src -cp packages/esx/test --run EsxTest
//
// templates (their structure, one per literal, the same object each time
// it runs), values, JSX's whitespace and entities, nesting through
// expressions, components (props checked by Haxe, children), HTML; and
// the programs the macro rejects (test/reject, "// expect:" lines)
class EsxTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		structure();
		values();
		text();
		nesting();
		components();
		html();
		var tool = Sys.args()[0];
		if (tool != null) rejects(tool, "packages/esx/test/reject");
		Sys.println('EsxTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('EsxTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// a template as a compact string: element(attrs)[children]
	static function shape(n:TNode):String
		return switch n.kind {
			case Text: '"' + n.text + '"';
			case Hole: "{" + n.hole + "}";
			case Component: n.name + "#" + n.hole;
			case Fragment: "<>[" + [for (c in n.children) shape(c)].join(",") + "]";
			case Element:
				n.name + "(" + [
					for (a in n.attrs)
						switch a.kind {
							case Static: a.name + "=" + a.value;
							case Dynamic: a.name + "={" + a.hole + "}";
							case Flag: a.name;
							case Spread: "...{" + a.hole + "}";
						}
				].join(" ") + ")[" + [for (c in n.children) shape(c)].join(",") + "]";
		}

	static function item(label:String):Esx
		return <li class="item">{label}</li>;

	static function structure() {
		var e = <div id="main" class='a b' hidden data-x={1 + 1}>
			<span>static</span>
			{"dynamic"}
		</div>;
		check("structure", shape(e.template.root) == 'div(id=main class=a b hidden data-x={0})[span()["static"],{1}]', shape(e.template.root));
		check("structure: holes", e.template.holes == 2 && e.values.length == 2);
		check("structure: source", StringTools.startsWith(e.template.source, "EsxTest.hx:"), e.template.source);
		var a = item("one"), b = item("two");
		check("identity: one template per literal", a.template == b.template && a.values[0] == "one" && b.values[0] == "two");
		check("identity: another literal, another template", a.template != e.template);
		var f = <>
			<b/>
			<i/>
		</>;
		check("fragment", shape(f.template.root) == "<>[b()[],i()[]]", shape(f.template.root));
		var spread = {title: "t", tabindex: 2};
		var s = <a {...spread} href="#"/>;
		check("spread", shape(s.template.root) == "a(...{0} href=#)[]" && s.values[0] == spread, shape(s.template.root));
	}

	static function values() {
		var n = 0;
		var e = <p onclick={() -> n++} count={n}>{n}</p>;
		var click:Void->Int = e.values[0];
		click();
		check("values: evaluated when the literal runs", e.values[1] == 0 && e.values[2] == 0 && n == 1);
		var e2 = <p onclick={() -> n++} count={n}>{n}</p>;
		check("values: each run its own", e2.values[1] == 1 && e2.template == e2.template);
	}

	static function text() {
		var e = <p>
			Hello,
			world!   Two  spaces stay
		</p>;
		check("text: JSX's whitespace", shape(e.template.root) == 'p()["Hello, world!   Two  spaces stay"]', shape(e.template.root));
		var name = "Ann";
		var g = <p>Hi {name}, you have {3} new</p>;
		check("text: around holes", shape(g.template.root) == 'p()["Hi ",{0},", you have ",{1}," new"]', shape(g.template.root));
		var ent = <p title="a &amp; b">&lt;tag&gt; &#65;&#x42; &lbrace;x&rbrace;</p>;
		check("text: entities", shape(ent.template.root) == 'p(title=a & b)["<tag> AB {x}"]', shape(ent.template.root));
		var c = <p>{/* a comment */}text</p>;
		check("text: an empty expression is no child", shape(c.template.root) == 'p()["text"]', shape(c.template.root));
	}

	static function nesting() {
		var items = ["a", "b", "c"];
		var e = <ul>{[for (i in items) <li>{i}</li>]}</ul>;
		var list:Array<Esx> = e.values[0];
		check("nesting: markup inside an expression", list.length == 3 && list[0].template == list[2].template && list[1].values[0] == "b");
		var deep = <div>{items.length > 2 ? <b>{"many " + items.join("")}</b> : <i>few</i>}</div>;
		var inner:Esx = deep.values[0];
		check("nesting: a ternary of markup", shape(inner.template.root) == "b()[{0}]" && inner.values[0] == "many abc");
	}

	static function Button(props:{label:String, ?primary:Bool, ?onClick:Void->Void, ?children:Esx}):Esx
		return <button class={props.primary == true ? "primary" : "plain"}>{props.label}{props.children}</button>;

	static function components() {
		var clicked = false;
		var e = <div><Button label="OK" primary onClick={() -> clicked = true}/></div>;
		check("component: a factory in the template", shape(e.template.root) == "div()[Button#0]", shape(e.template.root));
		var make:Void->Any = e.values[0];
		var out:Esx = make();
		check("component: called with its props", out.values[0] == "primary" && out.values[1] == "OK");
		var withKids = <Button label="Go"><i>now</i></Button>;
		var o2:Esx = (withKids.values[0] : Void->Any)();
		var kids:Esx = o2.values[2];
		check("component: children as an Esx", kids != null && shape(kids.template.root) == "<>[i()[\"now\"]]", kids == null ? "null" : shape(kids.template.root));
		var dotted = <EsxTest.Button label="dot"/>;
		check("component: a dotted path", shape(dotted.template.root) == "EsxTest.Button#0");
	}

	static function html() {
		var name = "<Ann>";
		var e = <div class="card" hidden={false} checked={true}>
			<h1>Hello {name}</h1>
			<br/>
			<Button label="OK"/>
		</div>;
		var h = e.toHtml();
		check("html", h == '<div class="card" checked><h1>Hello &lt;Ann&gt;</h1><br><button class="plain">OK</button></div>', h);
	}

	static function rejects(tool:String, dir:String) {
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".hx")) f];
		files.sort(Reflect.compare);
		for (f in files) {
			var expect = [
				for (l in sys.io.File.getContent('$dir/$f').split("\n"))
					if (StringTools.startsWith(l, "// expect: ")) StringTools.trim(l.substr(11))
			];
			var p = new sys.io.Process(tool, ["-cp", "packages/esx/src", "-cp", dir, "-main", f.substr(0, f.length - 3), "--interp", "--no-output"]);
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			var missing = [for (e in expect) if (out.indexOf(e) < 0) e];
			check('reject/$f', code != 0 && expect.length > 0 && missing.length == 0,
				code == 0 ? "compiled, but must be rejected" : "missing: " + missing.join("; ") + "\n" + out);
		}
	}
}
