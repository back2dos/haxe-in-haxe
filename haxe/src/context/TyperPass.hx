package context;

enum TyperPass {
	PBuildModule; // build the module structure and setup module type parameters
	PBuildClass; // build the class structure
	PConnectField; // handle associated fields, which may affect each other. E.g. a property and its getter
	PTypeField; // type the class field, allow access to types structures
	PCheckConstraint; // perform late constraint checks with inferred types
	PForce; // usually ensure that lazy have been evaluated
	PFinal; // not used, only mark for finalize
}

class TyperPassTools {
	public static final allTyperPasses:Array<TyperPass> = [
		PBuildModule,
		PBuildClass,
		PConnectField,
		PTypeField,
		PCheckConstraint,
		PForce,
		PFinal
	];
	public static final allTyperPassesLength = allTyperPasses.length;
}
