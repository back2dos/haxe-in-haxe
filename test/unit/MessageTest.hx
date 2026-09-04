package unit;

import core.Globals;
import core.Message;
import core.Message.CompilerMessageKind;
import core.Message.MessageKind;
import core.Message.MessageSeverity;
import core.Message.WarningCode as Warning;
import core.Json.JsonValue;

class MessageTest {
	static function assertEquals<T>(expected:T, actual:T):Void {
		if (expected != actual) throw 'Expected $expected, got $actual';
	}

	public static function main():Void {
		var error = Message.makeMessage(false, "broken", Globals.nullPos, 2, MKError);
		assertEquals("broken", error.cmMessage);
		assertEquals(2, error.cmDepth);
		assertEquals(MessageSeverity.Error, Message.severity(error));
		assertEquals(null, Message.code(error));

		var warning = Message.makeDiagnostic(true, DKParserError, JString("details"), Globals.nullPos, 0, MKWarning(WDeprecated, []));
		assertEquals("", warning.cmMessage);
		assertEquals(MessageSeverity.Warning, Message.severity(warning));
		assertEquals("WDeprecated", Message.code(warning));
		assertEquals(4, Message.diagnosticsKindToInt(DKParserError));
	}
}
