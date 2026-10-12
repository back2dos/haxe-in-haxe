package shim;

// port: tink.core.Outcome (tink_core)
enum Outcome<T, E> {
	Success(data:T);
	Failure(failure:E);
}

class OutcomeTools {
	static public function sure<T, E>(o:Outcome<T, E>):T
		return switch o {
			case Success(v): v;
			case Failure(e): throw e;
		}
}
