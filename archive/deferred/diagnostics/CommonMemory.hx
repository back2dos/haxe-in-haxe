package deferred.diagnostics;

// haxe/src/context/common.ml, mem_size. Object-size diagnostics are deferred.
class CommonMemory {
 public static function memSize(v:Dynamic):Int return Objsize.sizeWithHeaders(Objsize.objsize(v,[],[]));
}
