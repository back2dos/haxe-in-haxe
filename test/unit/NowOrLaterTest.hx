package unit;

import core.ds.NowOrLater;

class NowOrLaterTest {
	public static function main():Void {
		var scheduler = new NowOrLater();
		var steps:Array<String> = [];
		scheduler.tryNow(function() {
			steps.push("now");
			scheduler.tryNow(function() steps.push("later"));
		});
		if (steps.join(",") != "now") throw "Nested callback must be deferred";
		scheduler.handleLater();
		if (steps.join(",") != "now,later") throw "Deferred callback was not handled";
	}
}
