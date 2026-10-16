// An attribute's value is "text" or {expr}.
// expect: EsxAttribute.hx:6: characters 22-23
// expect: markup: an attribute value
class EsxAttribute implements hxmc.esx.Markup {
	static function main() {
		var e = <div class=main/>;
	}
}
