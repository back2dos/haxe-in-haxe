# @hxmc/esx

JSX-like markup for Haxe, on every target, after WebReflection's
[ESX proposal](https://gist.github.com/WebReflection/2d64f34cf58daa812ec876242c91a97c).
Haxe already parses inline markup (`<div>...</div>` in an expression); this
package compiles it:

```haxe
import hxmc.esx.*;

class App implements Markup {
	static function Greeting(props:{name:String, ?children:Esx}):Esx
		return <p class="greeting">Hello {props.name}! {props.children}</p>;

	static function view(items:Array<String>):Esx
		return <div id="app">
			<Greeting name="Ann"><b>welcome</b></Greeting>
			<ul>{[for (i in items) <li>{i}</li>]}</ul>
		</div>;
}
```

Every literal becomes `new Esx(template, values)`:

- `template` is the literal's static part (elements, attributes, text),
  built once: a static final of a class generated for the literal. Its
  identity is the literal's, so a renderer can compile a template once,
  keyed by the object, and from then on only read values.
- `values` are the literal's holes in source order: `{expr}` children and
  attribute values, `{...spread}` attributes, and components.

Lowercase names are intrinsic elements: the renderer's (strings).
Capitalized or dotted names are components: `<Greeting name="Ann"/>`
compiles to a factory `() -> Greeting({name: "Ann"})`, so Haxe checks the
props against the component's argument (a wrong type or an unknown prop is
an error at the attribute). A component's content is its `children` prop,
an `Esx`.

Text follows JSX's rule: lines are trimmed, blank lines dropped, the rest
joined with spaces; entities (`&amp;`, `&#65;`, `&lbrace;`) are decoded.
Attributes are `name="text"`, `name={expr}`, `name` alone (true) or
`{...expr}`. Expressions inside markup are parsed at their place in the
file, so errors point into the markup, and markup nests through them.

Compile literals in a class that `implements Markup` (every field), or one
at a time with `Esx.esx(<...>)`. `Esx.toHtml()` renders intrinsic trees as
HTML (tests, server output).

## The template

```haxe
class Template { root:TNode; holes:Int; source:String; }
class TNode { kind:TKind; name:String; attrs:Array<TAttr>; children:Array<TNode>; hole:Int; }
// TKind: Element, Component (hole: its factory), Fragment, Text (name: the text), Hole
class TAttr { kind:TAttrKind; name:String; value:String; hole:Int; }
// TAttrKind: Static (value), Dynamic (hole), Flag (true), Spread (hole)
```

`@hxmc/ui`'s `Render` is one consumer (Solid-like: each part created once,
bound to what it reads); a React-like renderer would diff values per
template instead.

Tests: `make esx-check` (`test/EsxTest.hx`, `test/reject`).
