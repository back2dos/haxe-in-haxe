package typing;

import core.TType;
import core.TPrinting;

// haxe/src/typing/fieldCallCandidate.ml — mechanical draft; not compile-validated.
typedef FieldCallCandidateData<A> = {
	var fcArgs:Array<TExpr>;
	var fcRet:T;
	var fcType:T;
	var fcField:TClassField;
	var fcMonos:Array<T>;
	var fcData:A;
}

class FieldCallCandidate {
	public static function makeFieldCallCandidate<A>(args:Array<TExpr>, ret:T, monos:Array<T>, t:T, cf:TClassField, data:A):FieldCallCandidateData<A> {
		return {fcArgs:args, fcType:t, fcField:cf, fcData:data, fcRet:ret, fcMonos:monos};
	}

	public static function sFieldCallCandidate<A>(fcc:FieldCallCandidateData<A>):String {
		var pctx = TPrinting.printContext();
		var se = function(e) return TPrinting.sExprPretty(false, "", false, function(t) return TPrinting.sType(pctx, t), e);
		return Printer.sRecordFields("", [
			{name:"fc_args", value:fcc.fcArgs.map(se).join(", ")},
			{name:"fc_type", value:TPrinting.sType(pctx, fcc.fcType)},
			{name:"fc_field", value:fcc.fcField.cfName + ": " + TPrinting.sType(pctx, fcc.fcField.cfType)}
		]);
	}
}
