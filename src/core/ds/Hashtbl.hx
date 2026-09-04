package core.ds;
import Type as StdType;
/** Structurally keyed table. Binding stacks preserve OCaml add/find/remove behavior.
    Iteration is deterministic insertion order; callers must not use it as binary pool order. */
class Hashtbl<K,V> {
 // Bounded structural hashing for grouping tables; hash values are not serialized.
 public static function hash(value:Dynamic):Int {
  var budget=100,meaningful=10,result=0;
  function mix(v:Int):Void result=(result*65599+v)|0;
  function visit(v:Dynamic):Void {
   if(budget--<=0 || meaningful<=0) return;
   if(v==null) {mix(0);meaningful--;return;}
   if(Std.isOfType(v,Array)) {var a:Array<Dynamic>=v;mix(a.length);for(x in a) visit(x);return;}
   switch StdType.typeof(v) {
    case TInt:mix(v);meaningful--;
    case TFloat:var f:Float=v;var bytes=haxe.io.Bytes.alloc(8);bytes.setDouble(0,f);for(i in 0...8) mix(bytes.get(i));meaningful--;
    case TBool:mix(v ? 1 : 0);meaningful--;
    case TClass(c) if(c==String):var text:String=v;for(i in 0...text.length) mix(text.charCodeAt(i));meaningful--;
    case TEnum(_):mix(StdType.enumIndex(v));for(x in StdType.enumParameters(v)) visit(x);
    case TObject,TClass(_):var fields=Reflect.fields(v);fields.sort(Reflect.compare);for(f in fields) visit(Reflect.field(v,f));
    case _:mix(0);
   }
  }
  visit(value);return result & 0x3fffffff;
 }

 var entries:Array<{key:K,value:V}>=[];
 public function new(size:Int=0) {}
 public function add(key:K,value:V):Void entries.unshift({key:key,value:value});
 public function replace(key:K,value:V):Void {for(i in 0...entries.length) if(Key.compare(entries[i].key,key)==0) {entries[i]={key:key,value:value};return;}add(key,value);}
 public function remove(key:K):Void {for(i in 0...entries.length) if(Key.compare(entries[i].key,key)==0) {entries.splice(i,1);return;}}
 public function find(key:K):V {for(e in entries) if(Key.compare(e.key,key)==0) return e.value;throw new NotFound();}
 public function findOpt(key:K):Null<V> {for(e in entries) if(Key.compare(e.key,key)==0) return e.value;return null;}
 public function mem(key:K):Bool {for(e in entries) if(Key.compare(e.key,key)==0) return true;return false;}
 public function iter(f:K->V->Void):Void for(e in entries) f(e.key,e.value);
 public function fold<A>(f:K->V->A->A,acc:A):A {for(e in entries) acc=f(e.key,e.value,acc);return acc;}
 public function clear():Void entries=[];
}
