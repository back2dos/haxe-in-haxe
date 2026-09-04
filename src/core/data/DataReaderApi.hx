package core.data;

// Mechanical translation of haxe/src/core/data/dataReaderApi.ml. Draft; not compiled or tested.
// An OCaml module signature is represented as a structural record of functions.
typedef DataReaderApi<Data> = {
	var readOptional:Data->(Data->Void)->Void;
	var readObject:Data->Array<{name:String,value:Data}>;
	var readArray:Data->Array<Data>;
	var readString:Data->String;
	var readIdent:Data->String;
	var readBool:Data->Bool;
	var readInt:Data->Int;
	var dataToString:Data->String;
}
