package haxeshim.sys;

class Os {

  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';

  static public var DELIMITER(default, null):String = if (IS_WINDOWS) ';' else ':';

  static public var EXECUTABLE_EXTENSION(default, null):String = if (IS_WINDOWS) '.exe' else '';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
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
        switch [Sys.systemName(), machine] {
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
