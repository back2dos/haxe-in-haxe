package context;
import core.Timer;
import sys.thread.Mutex;
// haxe/src/context/parallel.ml — mechanical draft; not compile-validated.
// Domainslib/Domain are explicit unresolved runtime adapters, not sequential fallbacks.
typedef ManagedPoolData = {var setup:Void->Dynamic; var pool:Null<Dynamic>; var mutex:Mutex;}
class Parallel {
 public static var enable=true;
 public static function runParallelFor(numDomains:Int,length:Int,f:Int->Void,chunkSize:Int=0):Void {
  if (!enable) {for (i in 0...length) f(i); return;}
  var pool=Domainslib.Task.setupPool(numDomains-1);
  Domainslib.Task.run(pool,function() Domainslib.Task.parallelFor(pool,0,length-1,f,chunkSize));
  Domainslib.Task.teardownPool(pool);
 }
 public static function runInNewPool<A>(timerCtx:Dynamic,f:Null<Dynamic>->A):A {
  if (!enable) return f(null);
  var pool=Timer.time(timerCtx,["domainslib","setup"],function() return Domainslib.Task.setupPool(Domain.recommendedDomainCount()-1));
  function cleanup():Void Timer.time(timerCtx,["domainslib","teardown"],function() Domainslib.Task.teardownPool(pool));
  var result:A;
  try result=Domainslib.Task.run(pool,function() return f(pool)) catch (e:Dynamic) {cleanup(); throw e;}
  cleanup(); return result;
 }
 public static function runWithPool<A>(mp:ManagedPoolData,f:Null<Dynamic>->A):A {
  if (!enable) return f(null);
  var pool=ManagedPool.acquire(mp); return Domainslib.Task.run(pool,function() return f(pool));
 }
}
class ParallelArray {
 public static function iter<A>(pool:Null<Dynamic>,f:A->Void,a:Array<A>):Void {
  if (pool==null) for (value in a) f(value);
  else Domainslib.Task.parallelFor(pool,0,a.length-1,function(i) f(a[i]));
 }
 public static function map<A,B>(pool:Null<Dynamic>,f:A->B,a:Array<A>,x:B):Array<B> {
  if (pool==null) return a.map(f);
  var output=[for (_ in a) x]; Domainslib.Task.parallelFor(pool,0,a.length-1,function(i) output[i]=f(a[i])); return output;
 }
}
class ParallelSeq {
 public static function iter<A>(pool:Null<Dynamic>,f:A->Void,seq:Iterator<A>):Void ParallelArray.iter(pool,f,[for (a in seq) a]);
}
class ManagedPool {
 public static function create(setup:Void->Dynamic):ManagedPoolData return {setup:setup,pool:null,mutex:new Mutex()};
 static function protect<A>(mp:ManagedPoolData,f:Void->A):A {
  mp.mutex.acquire(); var result:A; try result=f() catch (e:Dynamic) {mp.mutex.release(); throw e;}
  mp.mutex.release(); return result;
 }
 public static function acquire(mp:ManagedPoolData):Dynamic return protect(mp,function() {if (mp.pool==null) mp.pool=mp.setup(); return mp.pool;});
 public static function release(mp:ManagedPoolData):Void protect(mp,function() {if (mp.pool!=null) {Domainslib.Task.teardownPool(mp.pool); mp.pool=null;} return null;});
 public static function isActive(mp:ManagedPoolData):Bool return protect(mp,function() return mp.pool!=null);
}
