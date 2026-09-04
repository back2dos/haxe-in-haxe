package compiler.io;
import haxe.io.Input;
import haxe.io.Output;
// haxe/src/compiler/io/compilerIo.ml — mechanical draft; not compile-validated.
// Pipe/thread adapters remain explicit unresolved runtime dependencies.
typedef CompilerIoData={var stdout:Output;var stderr:Output;var stdin:Input;var getch:Bool->Int;var writeOut:String->Void;var writeErr:String->Void;var writeResult:String->Void;var signalError:Void->Void;var flush:Void->Void;var close:Void->Void;}
class CompilerIo {
 public static function makeOutputPipe(writeFn:String->Void):{output:Output,thread:Dynamic} {
  var pipe=Unix.pipe(true),out=Unix.outChannelOfDescr(pipe.write),input=Unix.inChannelOfDescr(pipe.read);
  var thread=Threads.create(function() {
   var buf=haxe.io.Bytes.alloc(1024);
   try {while (true) {var n=input.readBytes(buf,0,1024);if (n==0) break;writeFn(buf.getString(0,n));}}
   catch (_:haxe.io.Eof) {} catch (_:UnixError) {}
   try input.close() catch (_:Dynamic) {}
  });return {output:out,thread:thread};
 }
 public static function getchFromChannel(input:Input,output:Output,echo:Bool):Int {var c=try input.readByte() catch (_:haxe.io.Eof) -1;if (echo&&c>=0) {output.writeByte(c);output.flush();}return c;}
 public static function writeOut(io:CompilerIoData,s:String):Void io.writeOut(s);
 public static function writeErr(io:CompilerIoData,s:String):Void io.writeErr(s);
 public static function writeResult(io:CompilerIoData,s:String):Void io.writeResult(s);
 public static function signalError(io:CompilerIoData):Void io.signalError();
 public static function getStdout(io:CompilerIoData):Output return io.stdout;
 public static function getStderr(io:CompilerIoData):Output return io.stderr;
 public static function getStdin(io:CompilerIoData):Input return io.stdin;
 public static function getch(io:CompilerIoData,echo:Bool):Int return io.getch(echo);
 public static function flush(io:CompilerIoData):Void io.flush();
 public static function close(io:CompilerIoData):Void io.close();
 public static function create(writeOut:String->Void,writeErr:String->Void,writeResult:String->Void,signalError:Void->Void,stdin:Input):CompilerIoData {
  var out=makeOutputPipe(writeOut),err=makeOutputPipe(writeErr),closed=false;
  return {stdout:out.output,stderr:err.output,stdin:stdin,getch:function(echo) return getchFromChannel(stdin,out.output,echo),writeOut:writeOut,writeErr:writeErr,writeResult:writeResult,signalError:signalError,
   flush:function() {out.output.flush();err.output.flush();},close:function() {if (!closed) {closed=true;out.output.flush();try out.output.close() catch (_:Dynamic) {} Threads.join(out.thread);err.output.flush();try err.output.close() catch (_:Dynamic) {} Threads.join(err.thread);try stdin.close() catch (_:Dynamic) {}}}};
 }
 public static function createStdioIo():CompilerIoData return {stdout:Sys.stdout(),stderr:Sys.stderr(),stdin:Sys.stdin(),getch:Sys.getChar,writeOut:function(s) {Sys.print(s);Sys.stdout().flush();},writeErr:function(s) Sys.stderr().writeString(s),writeResult:function(s) Sys.stderr().writeString(s),signalError:function() {},flush:function() Sys.stdout().flush(),close:function() {}};
}
