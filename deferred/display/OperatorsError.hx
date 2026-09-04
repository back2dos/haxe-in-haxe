// haxe/src/typing/operators.ml: check_error diagnostic recovery; deferred display services.
 public static function checkError(ctx:Dynamic,err:Dynamic):Void switch err.errMessage{case ModuleNotFound({pack:[],name:name}) if(Diagnostics.errorInDiagnosticsRun(ctx.com,err.errPos)):DisplayToplevel.handleUnresolvedIdentifier(ctx,name,err.errPos,true);case _:raiseOrDisplayError(ctx,err);};
