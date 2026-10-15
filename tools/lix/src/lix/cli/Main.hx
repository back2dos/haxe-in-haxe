package lix.cli;

/**
  One binary for the four commands of the lix npm package (`lix`, `haxe`, `haxelib`, `neko`):
  the command is the name it is invoked by (a link to it), or the first argument when that
  is `--run-as <command>`.
**/
class Main {
  static function main() {
    var args = Sys.args();
    var name = invokedAs();
    if (args[0] == '--run-as' && args.length > 1) {
      args.shift();
      name = args.shift();
    }
    switch name {
      case 'haxe': HaxeCmd.main(args);
      case 'haxelib': HaxelibCmd.main(args);
      case 'neko': NekoCmd.main(args);
      default: Cli.main(args);
    }
    Sys.exit(0);
  }

  static function invokedAs():String {
    var path = #if (target.name == "hxmc") hxmc.NativeSys.argv0() #else null #end;
    if (path == null) return 'lix';
    var name = haxe.io.Path.withoutDirectory(path.split('\\').join('/'));
    var ext = name.lastIndexOf('.');
    if (ext > 0) name = name.substr(0, ext);
    return name.toLowerCase();
  }
}
