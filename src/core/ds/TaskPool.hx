package core.ds;

import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Lock;

// Runtime substitute for Domainslib.Task. Workers are scoped to each parallelFor
// call (including nested calls), rather than retained work-stealing domains.
// Indexed results and propagation of worker exceptions are preserved.
class TaskPool {
 public final workers:Int;
 var closed=false;
 public function new(workers:Int) {
  if (workers<0) throw new haxe.exceptions.ArgumentException("workers");
  this.workers=workers;
 }
 public static function recommendedDomainCount():Int {
  var count=Sys.getEnv("NUMBER_OF_PROCESSORS");
  if (count==null && Sys.systemName()!="Windows") {
   try {
    var process=new sys.io.Process("getconf",["_NPROCESSORS_ONLN"]);
    count=process.stdout.readAll().toString();
    process.exitCode();process.close();
   } catch (_:Dynamic) {}
  }
  var parsed=count==null?null:Std.parseInt(StringTools.trim(count));
  return parsed==null || parsed<1 ? 1 : parsed;
 }
 public function run<A>(f:Void->A):A {
  if (closed) throw new haxe.Exception("Task pool is closed");
  return f();
 }
 public function close():Void {closed=true;}
 public function parallelFor(first:Int,last:Int,f:Int->Void,chunkSize:Int=0):Void {
  if (closed) throw new haxe.Exception("Task pool is closed");
  if (last<first) return;
  var count=last-first+1;
  var threads=Std.int(Math.min(workers,count-1));
  if (threads==0) {for (i in first...last+1) f(i);return;}
  var chunk=chunkSize>0 ? chunkSize : Std.int(Math.max(1,count/(8*(threads+1))));
  var mutex=new Mutex(),done=new Lock();
  var next=first,failed=false;
  var failure:Dynamic=null;
  function work():Void {
   while (true) {
    mutex.acquire();
    var start=next;
    if (failed || start>last) {mutex.release();break;}
    next+=chunk;mutex.release();
    try {for (i in start...Std.int(Math.min(start+chunk,last+1))) f(i);}
    catch (e:Dynamic) {mutex.acquire();if (!failed) {failed=true;failure=e;}mutex.release();break;}
   }
  }
  var spawned=0;
  try {
   for (_ in 0...threads) {Thread.create(function() {work();done.release();});spawned++;}
   work();
  } catch (e:Dynamic) {mutex.acquire();if (!failed) {failed=true;failure=e;}mutex.release();}
  for (_ in 0...spawned) done.wait();
  if (failed) throw failure;
 }
}
