package core.ds;
import Type as StdType;
/** Structural comparison for the finite records, tuples and lists used as OCaml map keys. */
class Key {
 public static function compare(a:Dynamic,b:Dynamic):Int {
  if(a==b) return 0;
  if(a==null) return -1;if(b==null) return 1;
  if(Std.isOfType(a,Array)&&Std.isOfType(b,Array)) {
   var aa:Array<Dynamic>=a,bb:Array<Dynamic>=b,n=Std.int(Math.min(aa.length,bb.length));
   for(i in 0...n) {var c=compare(aa[i],bb[i]);if(c!=0) return c;}return Reflect.compare(aa.length,bb.length);
  }
  return switch [StdType.typeof(a),StdType.typeof(b)] {
   case [TEnum(_),TEnum(_)]:var c=Reflect.compare(StdType.enumIndex(a),StdType.enumIndex(b));c!=0 ? c : compare(StdType.enumParameters(a),StdType.enumParameters(b));
   case [TObject,TObject]:var names=Reflect.fields(a),other=Reflect.fields(b);names.sort(Reflect.compare);other.sort(Reflect.compare);var c=compare(names,other);if(c!=0) c;else {var result=0;for(name in names) {result=compare(Reflect.field(a,name),Reflect.field(b,name));if(result!=0) break;}result;}
   case [TFunction,_],[_,TFunction]:throw new haxe.Exception("compare: functional value");
   case _:Reflect.compare(a,b);
  }
 }
}
