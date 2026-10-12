package lix.client;

import haxeshim.scope.Scope.*;
import haxeshim.sys.Exec;
import lix.client.Archives;

using haxe.Json;

class Libraries {

  public final scope:Scope;

  final urlToJob:Url->ArchiveJob;

  public final logger:Logger;
  public final force:Bool;

  // port: the unused `resolver` argument of upstream (lix.api, never implemented) is gone
  public function new(scope, urlToJob, logger, force) {
    this.scope = scope;
    this.urlToJob = urlToJob;
    this.logger = logger;
    this.force = force;
  }

  public function downloadUrl(url:Url, ?options)
    return downloadArchive(urlToJob(url), options);

  public function downloadArchive(a:ArchiveJob, ?options:{ ?into:String }):DownloadedArchive {
    var cacheFile = null,
        into = options?.into;

    if (into == null)
      switch a.dest {
        case Fixed(path):
          into = DownloadedArchive.path(path);
        case Computed(_):
          cacheFile = '${scope.libCache}/.cache/libNames/${DownloadedArchive.escape(a.normalized.toString())}';
          if (cacheFile.exists())
            into = cacheFile.getContent();
      }

    var exists = into != null && '${scope.libCache}/$into'.exists();
    return
      if (exists && !force) {
        logger.success('already downloaded: ${a.normalized}');
        DownloadedArchive.existent(into, scope.libCache, a);
      }
      else {
        logger.info('${if (exists) "forcedly redownloading" else "downloading"} ${a.normalized}');
        final dest = '${scope.haxeshimRoot}/downloads/download@${Math.floor(Date.now().getTime())}_${uv.Uv.Loop.pid()}';
        var dir = switch a.kind {
          case null: Download.archive(a.url.toString(), 0, dest, logger);
          case Zip: Download.zip(a.url.toString(), 0, dest, logger);
          case Tar: Download.tar(a.url.toString(), 0, dest, logger);
          case Custom(load):
            load({ dest: dest, logger: logger, source: a.normalized, scope: scope });
        }
        var arch = DownloadedArchive.fresh(dir, scope.libCache, into, a);
        if (cacheFile != null)
          Fs.save(cacheFile, arch.relRoot);
        arch;
      }
  }

  public function installUrl(url:Url, ?as:LibVersion, ?options)
    installArchive(urlToJob(url), as, options);

  function installFromLibHxml(lib:String, srcPath:String):Array<String> {
    var hxml = scope.libHxml(lib);
    Fs.copy(srcPath, '${scope.scopeLibDir}/$lib.hxml');
    switch scope.getDirectives(lib)['install'] {
      case null | []:
        throw new Error('No install directive in $srcPath');
      case directives:
        for (d in directives) {
          logger.info(d);
          Exec.shell(d, scope.scopeDir).sure();
        }
    }
    var content = Fs.get(srcPath);
    var args = switch Args.fromMultilineString(content, hxml, scope.getVar) {
      case Success(args): [for (a in args) a.val];
      case Failure(r):
        var e = r.errors[0];
        throw new Error(e.code ?? 500, e.message);
    }
    return [for (i => a in args) if (a == '-lib' && Args.getNdll(args[i + 1]) == null) args[i + 1]];
  }


  public function dev(lib:String, path:String) {

    var isAbsolute = path.isAbsolute();

    var absPath =
      if (isAbsolute) path;
      else Path.join([scope.scopeDir, path]);

    var usedPath =
      if (isAbsolute) path;
      else '$${SCOPE_DIR}/$path';

    switch (try Success(absPath.readDirectory()) catch (e:Dynamic) Failure(e)) {
      case Success(files) if (files.indexOf('haxelib.json') != -1):

        var manifest = '$absPath/haxelib.json';
        var s = Fs.get(manifest);
        var info:{ ?name:String, ?version:String, ?classPath:String, ?main:String, ?dependencies:haxe.DynamicAccess<String> } =
          try haxe.Json.parse(s)
          catch (e:Dynamic) throw new Error('cannot parse $manifest');

        var lines = [];

        if (info.main != null || '$absPath/run.n'.exists()) {
          var runName = switch info.name {
            case null | '': lib;
            case name: name;
          };
          lines.push('# @run: haxelib run-dir $runName "$usedPath"');
        }

        if (info.dependencies != null)
          for (k => v in info.dependencies)
            lines.push('-lib $k');

        lines.push('-cp ' + switch info.classPath {
          case null: path;
          case v: '$usedPath/$v';
        });
        lines.push('-D $lib='+ switch info.version {
          case null: 'dev';
          case v: v;
        });

        var line = lines.length;

        if (files.indexOf('extraParams.hxml') != -1)
          lines.push('$usedPath/extraParams.hxml');

        lines.push('--macro Sys.println("haxe_libraries/$lib.hxml:$line: [Warning] Using dev version of library $lib")');
        Fs.save(scope.libHxml(lib), lines.join('\n'));
      case Success(_):
        throw new Error('$absPath does not contain haxelib.json');
      default:
        throw new Error('$absPath is not a readable directory');
    }
  }

  public function installArchive(
      job:ArchiveJob,
      ?as:LibVersion,
      ?options:{
        ?alreadyInstalled:Map<String, Bool>,
        ?flat:Bool,
      }
    ) {

    var a = downloadArchive(job);
    var extra =
      switch '${a.absRoot}/extraParams.hxml' {
        case found if (found.exists()):
          found.getContent();
        default: null;
      }

    if (as == null)
      as = { name: null, version: null };

    var infos:ArchiveInfos = a.infos;

    options ??= {};
    options.alreadyInstalled ??= new Map();

    var name = as.name ?? infos.name,
        version = as.version ?? infos.version;

    if (name == null)
      throw new Error('Could not determine library name for ${a.job.normalized}');

    var hxml = scope.libHxml(name);

    var DOWNLOAD_LOCATION = '$${$LIBCACHE}/${a.relRoot}';

    function interpolate(s)
      return scope.interpolate(s, v -> switch v {
        case 'DOWNLOAD_LOCATION': DOWNLOAD_LOCATION;
        default: null;
      });

    function exec(hook:String, cmd:Null<String>, ?cwd:String)
      if (cmd != null) {

        cmd = interpolate(cmd);

        if (cwd == null)
          cwd = scope.cwd;

        logger.info('Running $hook hook:');
        logger.info('> $cmd');

        // port: upstream maps the outcome to Noise, i.e. a failing hook is ignored
        Exec.shell(
          cmd,
          scope.interpolate(cwd),
          scope.haxeInstallation.env
        );
      }

    function saveHxml() {
      var directives = [
        '# @$INSTALL: lix --silent download "${a.job.normalized}" into ${a.relRoot}',
      ];

      switch infos.postDownload {
        case null:
        case v: directives.push('# @$POST_INSTALL: cd $DOWNLOAD_LOCATION && ${interpolate(v)}');
      }

      switch infos.runAs({ libRoot: scope.interpolate(DOWNLOAD_LOCATION) }) {
        case null:
        case v:
          directives.push('# @run: ' + Args.interpolate(v, v -> switch v {
            case 'DOWNLOAD_LOCATION': DOWNLOAD_LOCATION;
            case v: '$${$v}';
          }).sure());
      }

      function lines(a:Array<String>)
        return [for (l in a) if (l != null) l].join('\n');

      Fs.save(
        hxml,
        lines(
          directives
            .concat([for (lib in infos.dependencies) '-lib ${lib.name}'])
            .concat([
              '-cp $DOWNLOAD_LOCATION/${infos.classPath}',
              '-D $name=$version',
              extra,
              if (infos.hasNdll) '-lib ' + Args.makeNdll('$DOWNLOAD_LOCATION/ndll/') else null,
            ])
        )
      );
      options.alreadyInstalled[name] = true;
    };

    function installDependencies()
      if (!options.flat) {
        final errors = [];
        for (d in infos.dependencies) {
          var lib = d.name,
              dep = d.value;
          try
            if ('${scope.scopeLibDir}/$lib.hxml'.exists() && options.alreadyInstalled[lib]) //TODO: this should be in some function
              {}
            else switch [dep, infos.haxeshimDependencies[lib]] {
              case [FromUrl(url), null]:
                installUrl(url, { name: lib, version: null }, options);
                options.alreadyInstalled[lib] = true;
              case [FromHxml(path), _] | [_, path]:
                function install(lib, path)
                  if (!options.alreadyInstalled[lib]) {
                    var deps = installFromLibHxml(lib, path);
                    options.alreadyInstalled[lib] = true;
                    for (name in deps)
                      install(name, infos.haxeshimDependencies[name]);
                  }

                install(lib, path);
            }
          catch (e:Dynamic)
            errors.push(Error.of(e));
        }
        switch errors {
          case []:
          case errors: throw Error.withData('Failed to install dependencies of $name :\n  ' + errors.map(e -> e.message).join('\n  '), errors);
        }
      }

    saveHxml();
    logger.success('-> mounted as $name#$version');
    installDependencies();
    if (!a.alreadyDownloaded) exec('post download', infos.postDownload, DOWNLOAD_LOCATION);
    saveHxml();
    exec('post install', infos.postInstall);
  }
}
