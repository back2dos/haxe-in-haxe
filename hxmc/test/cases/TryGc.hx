// exceptions with collections around them: catch variables and locals
// assigned in try bodies must survive the second return of setjmp and the
// collections of the catch tests (haxe.Exception.caught wraps native values)
class Err {
	public var msg:String;

	public function new(m:String)
		msg = m;
}

class Other {
	public function new() {}
}

class TryGc {
	static var sink:Array<Dynamic> = [];

	static function churn(n:Int) {
		var a = [];
		for (i in 0...n)
			a.push({i: i, s: "x" + i});
		sink = a;
	}

	static function inner(k:Int):Int {
		var acc = [k];
		try {
			churn(200);
			acc.push(k * 2);
			if (k % 3 == 0) throw new Err("e" + k);
			if (k % 3 == 1) throw "str" + k;
			acc.push(1);
		} catch (o:Other) {
			acc.push(-1);
		}
		return acc.length;
	}

	static function main() {
		var total = 0;
		var msgs = [];
		for (k in 0...60) {
			var label = "k" + k;
			try {
				total += inner(k);
				churn(50);
			} catch (e:Err) {
				churn(100);
				msgs.push(label + ":" + e.msg);
			} catch (e:String) {
				churn(100);
				msgs.push(label + ":" + e);
			} catch (e:haxe.Exception) {
				msgs.push(label + ":exc " + e.message);
			}
		}
		trace(total);
		trace(msgs.join(","));
	}
}
