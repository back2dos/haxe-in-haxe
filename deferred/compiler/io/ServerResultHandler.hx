// Deferred server-pipe result handler from haxe/src/compiler/io/compilerOutput.ml.
 public static function createServerResultHandler(io:CompilerIoData):ResultHandler {
  function sendMessage(sev:Dynamic,output:String):Void switch sev {
   case Error:CompilerIo.writeErr(io,output+"\n");ServerMessage.message(output);
   case Warning|Information|Hint:CompilerIo.writeOut(io,output+"\n");
  };
  return {sendResult:function(_) {},sendResultRaise:function(_) throw "send_result_raise called in non-JSON-RPC mode",sendError:function(errors) {for (je in errors) CompilerIo.writeErr(io,extractErrorMessage(je)+"\n");},sendErrorRaise:function(_) throw "send_error_raise called in non-JSON-RPC mode",
   flushMessages:function(hasError,com) {var messages=com.partScope.messages.copy();messages.reverse();MessageReporting.displayMessagesFrom(com.defines,messages,function() {hasError=true;com.partScope.hasError=true;},sendMessage);com.sctx.wasCompilation=com.display.dmsFullTyping;
    if (hasError) {com.timerCtx.measureTimes=No;CompilerIo.signalError(io);}else if (com.timerCtx.measureTimes==Yes) sendTimerReport(io,com.timerCtx);
   },setCom:function(_) return NoCompletionPointFound};
 }
