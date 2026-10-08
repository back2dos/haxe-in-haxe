package core.ds;
import Type as StdType;
/** Structural comparison for the finite records, tuples and lists used as OCaml map keys. */
class Key {
 public static function compare(a:Dynamic,b:Dynamic):Int {
  if(a==b) return 0;
  if(a==null) return -1;if(b==null) return 1;
  // Fast paths for the common scalar keys; same result as Reflect.compare.
  if((a is String) && (b is String)) return (a:String) > (b:String) ? 1 : -1;
  if((a is Int) && (b is Int)) return (a:Int) > (b:Int) ? 1 : -1;
  // Type paths compare like the {name, pack} record they replace (fields in name order).
  if((a is core.Globals.GlobalTypePath) && (b is core.Globals.GlobalTypePath)) {
   var pa:core.Globals.GlobalTypePath=a,pb:core.Globals.GlobalTypePath=b;
   var c=compare(pa.name,pb.name);
   return c!=0 ? c : compare(pa.pack,pb.pack);
  }
  if(Std.isOfType(a,Array)&&Std.isOfType(b,Array)) {
   var aa:Array<Dynamic>=a,bb:Array<Dynamic>=b,n=Std.int(Math.min(aa.length,bb.length));
   for(i in 0...n) {var c=compare(aa[i],bb[i]);if(c!=0) return c;}return Reflect.compare(aa.length,bb.length);
  }
  return switch [StdType.typeof(a),StdType.typeof(b)] {
   case [TEnum(_),TEnum(_)]:var c=Reflect.compare(StdType.enumIndex(a),StdType.enumIndex(b));c!=0 ? c : compare(StdType.enumParameters(a),StdType.enumParameters(b));
   case [TObject|TClass(core.Globals.GlobalTypePath),TObject|TClass(core.Globals.GlobalTypePath)]:var names=Reflect.fields(a),other=Reflect.fields(b);names.sort(Reflect.compare);other.sort(Reflect.compare);var c=compare(names,other);if(c!=0) c;else {var result=0;for(name in names) {result=compare(Reflect.field(a,name),Reflect.field(b,name));if(result!=0) break;}result;}
   case [TFunction,_],[_,TFunction]:throw new haxe.Exception("compare: functional value");
   case _:Reflect.compare(a,b);
  }
 }

 /**
  A string that is equal for two keys exactly when `compare` returns 0, used to
  index hash tables. Returns null for keys outside the plain-data subset
  (class instances, functions, large values): tables then fall back to a
  linear scan with `compare`.
 **/
 public static function canonical(value:Dynamic):Null<String> {
  if(value is String) return "s" + (value:String);
  var buf=new StringBuf(),budget=64;
  function visit(v:Dynamic):Bool {
   if(--budget<0) return false;
   if(v==null) {buf.add("n");return true;}
   if(v is String) {var s:String=v;buf.add("s");buf.add(s.length);buf.add(":");buf.add(s);return true;}
   if(v is Int) {buf.add("i");buf.add((v:Int));buf.add(";");return true;}
   if(Std.isOfType(v,Array)) {var a:Array<Dynamic>=v;buf.add("a");buf.add(a.length);buf.add("[");for(x in a) if(!visit(x)) return false;return true;}
   if(v is core.Globals.GlobalTypePath) {var tp:core.Globals.GlobalTypePath=v;buf.add("o24:name");if(!visit(tp.name)) return false;buf.add("4:pack");return visit(tp.pack);}
   return switch StdType.typeof(v) {
    case TBool:buf.add((v:Bool) ? "T" : "F");true;
    case TEnum(_):
     var params=StdType.enumParameters(v);buf.add("e");buf.add(StdType.enumIndex(v));buf.add("(");buf.add(params.length);
     for(x in params) if(!visit(x)) return false;true;
    case TObject:
     var names=Reflect.fields(v);names.sort(Reflect.compare);buf.add("o");buf.add(names.length);
     for(name in names) {buf.add(name.length);buf.add(":");buf.add(name);if(!visit(Reflect.field(v,name))) return false;}true;
    case _:false; // floats, class instances and functions keep the linear path
   }
  }
  return visit(value) ? buf.toString() : null;
 }
}
