package deferred.native;
// haxe/src/compiler/args.ml, gen_hx_classes branch, deferred native-library milestone.
class ArgsNativeClasses {
 public static function configure(com:Dynamic,actx:Dynamic):Void {
  actx.forceTyping=true;
  actx.preCompilation.unshift(function() {
   function processLib(lib:Dynamic):Void if(!lib.hasFlag(FlagIsStd))for(path in (cast lib.listModules():Array<core.Globals.GlobalTypePath>))if(path.pack.join(".")!="java.lang"||path.name!="String")actx.classes.unshift(path);
   for(lib in (cast com.nativeLibs.swfLibs:Array<Dynamic>))processLib(lib);
   for(lib in (cast com.nativeLibs.javaLibs:Array<Dynamic>))processLib(lib);
  });
  actx.xmlOut="hx";
 }
}
