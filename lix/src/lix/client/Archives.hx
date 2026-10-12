package lix.client;

import haxeshim.scope.Scope;

using sys.io.File;
using haxe.Json;

enum ArchiveKind {
  Zip;
  Tar;
  Custom(load:CustomLoader);
}

typedef CustomLoader = CustomLoaderContext->String;
typedef CustomLoaderContext = { source:Url, dest:String, logger:Logger, scope:Scope };

enum ArchiveDestination {
  Fixed(path:Array<String>);
  Computed(f:ArchiveInfos->Array<String>);
}

typedef ArchiveJob = {

  var normalized(default, null):Url;
  var url(default, null):Url;
  var lib(default, null):LibVersion;
  var dest(default, null):ArchiveDestination;

  @:optional var kind(default, null):Null<ArchiveKind>;
}

enum ArchiveDependency {
  FromUrl(u:Url);
  FromHxml(path:String);
}

typedef HxmlPath = String;

typedef Named<T> = { final name:String; final value:T; }

@:structInit @:publicFields
class ArchiveInfos {
  final name:String;
  final version:String;
  final classPath:String;
  final hasNdll:Bool;
  final runAs:{ libRoot: String }->Null<String>;
  final dependencies:ArchiveDependencies;
  final haxeshimDependencies:HaxeshimDependencies;
  @:optional final postDownload:String;
  @:optional final postInstall:String;
}


abstract HaxeshimDependencies(Null<Map<String, HxmlPath>>) from Map<String, HxmlPath> {
  @:arrayAccess public inline function get(libName:String):Null<HxmlPath>
    return switch this {
      case null: null;
      case v: v[libName];
    }

  public function keyValueIterator():KeyValueIterator<String, HxmlPath>
    return switch this {
      case null: new Map<String, HxmlPath>().keyValueIterator();
      case v: v.keyValueIterator();
    }
}

@:forward(iterator)
abstract ArchiveDependencies(Array<Named<ArchiveDependency>>) {
  inline function new(deps:Array<Named<ArchiveDependency>>) {
    this = deps;
    // port: Reflect.compare on JS strings: UTF-16 code unit order
    this.sort((a, b) -> Reflect.compare(a.name, b.name));
  }

  @:from static function ofHaxeshim(d:HaxeshimDependencies)
    return new ArchiveDependencies([for (lib => hxml in d) { name: lib, value: FromHxml(hxml) }]);

  @:from static function ofMap(m:Map<String, ArchiveDependency>)
    return new ArchiveDependencies([for (lib => dep in m) { name: lib, value: dep }]);
}

class DownloadedArchive {

  /**
   * The job the archive originated from
   */
  public final job:ArchiveJob;

  public var alreadyDownloaded(default, null):Bool = true;

  var storageRoot:String;

  /**
   * The root directory of this archive, relative to the library cache
   */
  public var relRoot(default, null):String;
  /**
   * The absolute path to the root of the downloaded archive
   */
  public var absRoot(get, never):String;
    inline function get_absRoot()
      return getAbsRoot(storageRoot, relRoot);

  static function getAbsRoot(storageRoot, relRoot)
    return '$storageRoot/$relRoot'.removeTrailingSlashes();

  static var RESERVED = "!#$&'()*+,/:;=?@[]";

  static public function escape(s:String) {
    if (s == null) return null;
    for (i in 0...RESERVED.length)
      s = s.replace(RESERVED.charAt(i), '_');
    return s;
  }

  static public function path(parts:Array<String>)
    return parts.map(escape).join('/');

  public var infos(default, null):ArchiveInfos;

  static public function fresh(tmpLoc:String, storageRoot:String, targetLoc:String, job:ArchiveJob) {
    var curRoot = '$tmpLoc/${seekRoot(tmpLoc)}';
    var infos = readInfos(curRoot, job.lib);
    var relRoot =
      if (targetLoc == null)
        path(switch job.dest {
          case Fixed(path): path;
          case Computed(f): f(infos);
        });
      else targetLoc;

    var ret = new DownloadedArchive(relRoot, storageRoot, job, infos);
    ret.alreadyDownloaded = false;

    var absRoot = ret.absRoot;
    if (infos.haxeshimDependencies != null) {
      var curRootLength = curRoot.removeTrailingSlashes().length;
      ret.infos = {
        name: infos.name,
        version: infos.version,
        classPath: infos.classPath,
        hasNdll: infos.hasNdll,
        runAs: infos.runAs,
        dependencies: infos.dependencies,
        haxeshimDependencies: [for (name => path in infos.haxeshimDependencies)
          name => absRoot + path.substr(curRootLength)
        ],
        postDownload: infos.postDownload,
        postInstall: infos.postInstall
      };
    }

    var archive = null,
        old = ret.absRoot;
    if (Fs.exists(old))
      Fs.move(old, archive = '$old-archived@${Date.now().getTime()}');
    Fs.move(curRoot, ret.absRoot);
    Fs.delete(archive);
    Fs.delete(tmpLoc);
    return ret;
  }

  static public function existent(path:String, storageRoot:String, job:ArchiveJob)
    return new DownloadedArchive(path, storageRoot, job, readInfos(getAbsRoot(storageRoot, path), job.lib));

  function new(relRoot, storageRoot, job, infos) {

    this.storageRoot = storageRoot;
    this.relRoot = relRoot;

    this.job = job;
    this.infos = infos;
  }

  static function seekRoot(path:String)
    return switch path.readDirectory() {
      case [v] if ('$path/$v'.isDirectory()):
        '$v/' + seekRoot('$path/$v');
      default:
        '';
    }

  static function readInfos(root:String, lib:LibVersion):ArchiveInfos {

    var files = root.readDirectory();

    function guessClassPath()
      return
        if (files.indexOf('src') != -1) 'src';
        else if (files.indexOf('Sources') != -1) 'Sources';
        else if (files.indexOf('hx') != -1) 'hx';
        else '';

    if (lib == null)
      lib = LibVersion.UNDEFINED;

    var haxeshimDependencies:HaxeshimDependencies =
      if (files.contains('.haxerc') && files.contains('haxe_libraries')) {
        var libs = '$root/haxe_libraries';
        [for (f in libs.readDirectory())
          if (f.extension() == 'hxml')
            f.withoutExtension() => '$libs/$f'
        ];
      }
      else null;

    var hasNdll = files.contains('ndll');

    var ret:ArchiveInfos =
      if (files.contains('haxelib.json')) {
        //TODO: there's a lot of errors to be caught here
        var info:{
          name: String,
          version:String,
          ?dependencies:haxe.DynamicAccess<String>,
          ?classPath:String,
          ?main:String,
          ?postInstall: String,
          ?postDownload: String,
        } = '$root/haxelib.json'.getContent().parse();

        {
          name: info.name,
          version: info.version,
          classPath: switch info.classPath {
            case null: '';
            case v: v;
          },
          runAs: function (ctx) return
            if ('${ctx.libRoot}/run.n'.exists() || info.main != null)
              'haxelib run-dir ${info.name} "$${DOWNLOAD_LOCATION}"';
            else
              null
          ,
          dependencies: switch info.dependencies {
            case null: new Map<String, ArchiveDependency>();//haxeshimDependencies; - maybe the best default
            case deps:
              [for (name => value in deps)
                name => FromUrl(
                  switch value {
                    case '' | '*': Url.parse('haxelib:$name');
                    case version if (Url.parse(version).scheme == null): Url.parse('haxelib:$name#$version');
                    case Url.parse(_) => u if (u.scheme == 'git' && isForgeHttps(Url.parse(u.payload))):
                      Url.parse(u.payload);
                    case u: Url.parse(u);
                  })
              ];
          },
          hasNdll: hasNdll,
          haxeshimDependencies: haxeshimDependencies,
          postInstall: info.postInstall,
          postDownload: info.postDownload,
        }
      }
      else if (files.contains('package.json')) {
        var info:{ name: String, version:String, } = '$root/package.json'.getContent().parse();
        {
          name: info.name,
          version: info.version,
          classPath: guessClassPath(),
          hasNdll: hasNdll,
          runAs: _ -> null,
          dependencies: haxeshimDependencies,
          haxeshimDependencies: null,
        }
      }
      else {
        {
          name: lib.name ?? 'untitled',
          version: lib.version ?? '0.0.0',
          classPath: guessClassPath(),
          hasNdll: hasNdll,
          runAs: _ -> null,
          dependencies: haxeshimDependencies,
          haxeshimDependencies: null,
        }
      }
    return ret;
  }

  // `git:https://github.com/...` or gitlab.com, which lix gets as archives
  static function isForgeHttps(url:Url)
    return url.scheme == 'https' && url.host != null && (url.host.name == 'github.com' || url.host.name == 'gitlab.com');
}
