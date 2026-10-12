package haxeshim.sys;

class Os {

  /**
    The system lix runs on: Windows, Mac, BSD or Linux.
  **/
  // port: node's process.platform; a Cosmopolitan binary's Sys.systemName() is "Linux" everywhere
  static public var SYSTEM(default, null):String = #if (target.name == "hxc") hxc.NativeSys.hostSystem() #else Sys.systemName() #end;

  static public var IS_WINDOWS(default, null):Bool = SYSTEM == 'Windows';

  // port: a Cosmopolitan binary on Windows sees POSIX paths (/C/dir, and PATH
  // separated by `:`), which the Windows programs it runs do not understand
  static public var IS_POSIX_ON_WINDOWS(default, null):Bool = IS_WINDOWS && Sys.systemName() != 'Windows';

  static public var DELIMITER(default, null):String = if (IS_WINDOWS && !IS_POSIX_ON_WINDOWS) ';' else ':';

  static public var EXECUTABLE_EXTENSION(default, null):String = if (IS_WINDOWS) '.exe' else '';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
      else path;

  static final POSIX_DRIVE = ~/^\/([A-Za-z])(\/|$)/;
  static final WINDOWS_DRIVE = ~/^([A-Za-z]):([\\\/]|$)/;

  /**
    `path` as the Windows programs lix runs see it: `/C/dir` is `C:/dir` (on a
    Cosmopolitan binary on Windows; elsewhere unchanged).
  **/
  static public function hostPath(path:String):String
    return
      if (IS_POSIX_ON_WINDOWS && path != null && POSIX_DRIVE.match(path))
        POSIX_DRIVE.matched(1).toUpperCase() + ':/' + POSIX_DRIVE.matchedRight();
      else path;

  /**
    A path from Windows (an environment variable) as lix's own: `C:\dir` is `/C/dir`
    (on a Cosmopolitan binary on Windows; elsewhere unchanged).
  **/
  static public function fromHostPath(path:String):String
    return
      if (IS_POSIX_ON_WINDOWS && path != null && WINDOWS_DRIVE.match(path))
        '/' + WINDOWS_DRIVE.matched(1).toUpperCase() + '/' + WINDOWS_DRIVE.matchedRight().replace('\\', '/');
      else path;

  static public var platform(get, null):Platform;
    static function get_platform() {
      return platform ??= {
        // port: node's process.platform/process.arch, from the OS and libuv's uname (the
        // non-node branch upstream reads the program's header, which an APE binary misleads)
        var machine = switch hxc.NativeUv.uname() {
          case null: '';
          case u: u[3].toLowerCase();
        }
        switch [SYSTEM, machine] {
          case ['Linux', 'x86_64' | 'amd64']: Linux64;
          case ['Linux', 'i386' | 'i486' | 'i586' | 'i686']: Linux32;
          case ['Linux', 'aarch64' | 'arm64']: LinuxArm64;
          case ['Linux', m] if (m.startsWith('arm')): LinuxArm;
          case ['Linux', 'riscv64']: LinuxRiscV;
          case ['Windows', 'x86_64' | 'amd64']: Win64;
          case ['Windows', 'i386' | 'i686' | 'x86']: Win32;
          case ['Mac', 'x86_64']: Mac64;
          case ['Mac', 'arm64' | 'aarch64']: MacArm;
          default: Unknown;
        }
      }
    }
}
