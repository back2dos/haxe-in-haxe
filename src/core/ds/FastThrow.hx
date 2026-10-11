package core.ds;

// port: `throw FastThrow.of(e)`: on HashLink, throwing an exception object directly
// makes libhl capture a native backtrace (expensive when exceptions are control
// flow, as OCaml's are). Rethrow skips the capture; elsewhere this is `throw e`.
class FastThrow {
	public static inline function of<E>(e:E):E {
		#if hl hl.Api.rethrow(e); #end
		return e;
	}
}
