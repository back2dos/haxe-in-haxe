package core.ds;

/** The lazy, counted token stream operations used by OCaml's Stream parsers. */
class Stream<T> {
	final produce:Int->Null<T>;
	final buffered:Array<T> = [];
	var consumed = 0;
	var produced = 0;
	var ended = false;
	public function new(produce:Int->Null<T>) this.produce = produce;
	public static function from<T>(produce:Int->Null<T>):Stream<T> return new Stream(produce);
	public static function ofList<T>(values:Array<T>):Stream<T> return from(function(i) return i < values.length ? values[i] : null);
	public function count():Int return consumed;
	inline function fill(n:Int):Void {
		while (!ended && buffered.length < n) {
			var value = produce(produced);
			if (value == null) ended = true;
			else { buffered.push(value); produced++; }
		}
	}
	public function npeek(n:Int):Array<T> {
		fill(n);
		return buffered.slice(0, n);
	}
	// Without the npeek copy: the parser peeks at every token.
	public function peek():Null<T> {
		fill(1);
		return buffered.length > 0 ? buffered[0] : null;
	}
	public function junk():Void {
		if (peek() != null) { buffered.shift(); consumed++; }
	}
	public function next():T {
		var value = peek();
		if (value == null) throw StreamFailure.raise();
		junk();
		return value;
	}
	public function empty():Void if (peek() != null) throw StreamFailure.raise();
	public function iter(f:T->Void):Void while (peek() != null) f(next());
}

class StreamFailure extends haxe.Exception {
	// Shared instance; see NotFound. The parser backtracks through this constantly.
	public static final instance = new StreamFailure();

 // Throw site helper: `throw X.raise()`. On HashLink the shared instance is
 // thrown with rethrow, which skips libhl's native stack capture per throw.
 public static inline function raise():StreamFailure {
  #if hl hl.Api.rethrow(instance); #end
  return instance;
 }
	public function new() super("Stream.Failure");
}

class StreamError extends haxe.Exception {}
