package core.ds;
/** Persistent ordered lookup for non-string upstream keys. */
class PersistentMap<K,V> {
 final entries:Array<{key:K,value:V}>;
 public function new(?entries:Array<{key:K,value:V}>) this.entries=entries==null ? [] : entries;
 public static function empty<K,V>():PersistentMap<K,V> return new PersistentMap();
 public function add(key:K,value:V):PersistentMap<K,V> {
  var out=entries.copy(),i=0;while(i<out.length && Key.compare(out[i].key,key)<0) i++;
  if(i<out.length && Key.compare(out[i].key,key)==0) out[i]={key:key,value:value};else out.insert(i,{key:key,value:value});return new PersistentMap(out);
 }
 public function remove(key:K):PersistentMap<K,V> return new PersistentMap(entries.filter(function(e) return Key.compare(e.key,key)!=0));
 public function find(key:K):V {for(e in entries) if(Key.compare(e.key,key)==0) return e.value;throw new NotFound();}
 public function findOpt(key:K):Null<V> {for(e in entries) if(Key.compare(e.key,key)==0) return e.value;return null;}
 public function mem(key:K):Bool {for(e in entries) if(Key.compare(e.key,key)==0) return true;return false;}
 public function iter(f:K->V->Void):Void for(e in entries) f(e.key,e.value);
 public function foldi<A>(f:K->V->A->A,acc:A):A {for(e in entries) acc=f(e.key,e.value,acc);return acc;}
 public function keys():Iterator<K> return entries.map(function(e) return e.key).iterator();
 public function iterator():Iterator<V> return entries.map(function(e) return e.value).iterator();
}
