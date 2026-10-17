// A prop the component does not take is an error.
// expect: EsxUnknownProp.hx:9: characters
// expect: has extra field colour
class EsxUnknownProp implements hxmc.esx.Markup {
	static function Label(props:{text:String}):hxmc.esx.Esx
		return <span>{props.text}</span>;

	static function main() {
		var e = <div><Label text="a" colour="red"/></div>;
	}
}
