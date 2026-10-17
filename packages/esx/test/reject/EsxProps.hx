// A component's props are checked against its argument, at the attribute.
// expect: EsxProps.hx:9: characters
// expect: Int should be String
class EsxProps implements hxmc.esx.Markup {
	static function Label(props:{text:String}):hxmc.esx.Esx
		return <span>{props.text}</span>;

	static function main() {
		var e = <div><Label text={42}/></div>;
	}
}
