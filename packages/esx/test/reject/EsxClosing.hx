// A closing tag names the element it closes.
// expect: EsxClosing.hx:6: characters 23-27
// expect: markup: </i> closes <b>
class EsxClosing implements hxmc.esx.Markup {
	static function main() {
		var e = <div><b>bold</i></div>;
	}
}
