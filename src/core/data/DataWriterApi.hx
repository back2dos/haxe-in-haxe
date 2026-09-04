package core.data;

// Mechanical translation of haxe/src/core/data/dataWriterApi.ml. Draft; not compiled or tested.
typedef DataWriterApi<Data> = {
	var writeOptional:Null<Data>->Data;
	var writeObject:Array<{name:String,value:Data}>->Data;
	var writeArray:Array<Data>->Data;
	var writeString:String->Data;
	var writeBool:Bool->Data;
	var writeInt:Int->Data;
}
