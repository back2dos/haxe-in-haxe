package unit;

import compiler.Helper;

class HelperTest {
	public static function main():Void {
		var environment = new Map<String, String>();
		environment.set("PROJECT_ROOT", "project");
		if (Helper.expandEnv("%PROJECT_ROOT%/%UNKNOWN%", environment) != "project/%UNKNOWN%") throw "Environment expansion failed";
		if (Helper.unquote("'value'") != "value" || Helper.unquote("plain") != "plain") throw "Unquoting failed";

		var parsed = Helper.parseHxmlData('  # comment\n-cp src\n-D "feature=value"\nMain\n"-js out.js"\n');
		if (parsed.join("|") != "-cp|src|-D|feature=value|Main|-js|out.js") throw 'Unexpected HXML parsing: ${parsed.join("|")}';
	}
}
