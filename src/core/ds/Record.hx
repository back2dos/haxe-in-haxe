package core.ds;

import haxe.macro.Expr;

/** OCaml record updates are shallow copies, retaining every unchanged field. */
class Record {
	#if macro
	static var nextId = 0;
	#end
	public static macro function withFields(record:Expr,updates:Expr):Expr {
		var fields = switch updates.expr {
			case EObjectDecl(fields): fields;
			case _: haxe.macro.Context.error("Expected a record field update", updates.pos);
		};
		var name="__hihRecordUpdate"+(nextId++);
		var ref:Expr={expr:EConst(CIdent(name)),pos:record.pos};
		var result:Array<Expr>=[{expr:EVars([{name:name,expr:macro Reflect.copy($record)}]),pos:record.pos}];
		for(field in fields) result.push({expr:EBinop(OpAssign,{expr:EField(ref,field.field),pos:field.expr.pos},field.expr),pos:field.expr.pos});
		result.push(ref);
		return {expr:EBlock(result),pos:record.pos};
	}
}
