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

  // where an archive goes (relative to the library cache), the file caching that
  // for computed destinations, and whether it is there already
  function target(a:ArchiveJob, into:Null<String>) {
    var cacheFile = null;
    if (into == null)
      switch a.dest {
        case Fixed(path):
          into = DownloadedArchive.path(path);
        case Computed(_):
          cacheFile = '${scope.libCache}/.cache/libNames/${DownloadedArchive.escape(a.normalized.toString())}';
          if (cacheFile.exists())
            into = cacheFile.getContent();
      }
    return { into: into, cacheFile: cacheFile, exists: into != null && '${scope.libCache}/$into'.exists() };
  }

  // downloads and unpacks `a` into the library cache
  function fetch(a:ArchiveJob, into:Null<String>, cacheFile:Null<String>, logger:Logger):DownloadedArchive {
    // port: and a random number, as prefetches run in parallel within this process
    final dest = '${scope.haxeshimRoot}/downloads/download@${Math.floor(Date.now().getTime())}_${uv.Uv.Loop.pid()}_${Std.random(0x3FFFFFFF)}';
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
    return arch;
  }

  public function downloadArchive(a:ArchiveJob, ?options:{ ?into:String }):DownloadedArchive {
    var t = target(a, options?.into);
    return
      if (t.exists && !force) {
        switch prefetched[a.normalized.toString()] {
          case null:
            logger.success('already downloaded: ${a.normalized}');
            DownloadedArchive.existent(t.into, scope.libCache, a);
          case p:
            // downloaded by `prefetch` just now: reported as the download it was
            prefetched.remove(a.normalized.toString());
            logger.info('downloading ${a.normalized}');
            logger.success('-> Done!');
            p.archive;
        }
      }
      else {
        logger.info('${if (t.exists) "forcedly redownloading" else "downloading"} ${a.normalized}');
        fetch(a, t.into, t.cacheFile, logger);
      }
  }

  public function installUrl(url:Url, ?as:LibVersion, ?options)
    installArchive(switch prefetched[url.toString()] {
      case null: urlToJob(url);
      case p: p.job;
    }, as, options);

  /**
    The archives `prefetch` downloaded, by URL (of the dependency) and by
    normalized URL (of the job), until `downloadArchive` reports them.
  **/
  final prefetched = new Map<String, { job:ArchiveJob, archive:DownloadedArchive }>();

  /**
    Resolves and downloads the archives of `urls`, and transitively those of
    their dependencies, in parallel, `Scope.jobs()` at a time, ahead of their
    sequential installation, which then finds them (`downloadArchive`,
    `installUrl`). Libraries the scope has already are left out. What fails is
    left to that installation, which reports it.
  **/
  // port: upstream installs dependencies one by one (Future.inSequence)
  function prefetch(urls:Array<Url>) {
    var jobs = Scope.jobs();
    if (urls.length == 0 || jobs < 2 || force)
      return;
    shim.Http.prepare();
    var mutex = new sys.thread.Mutex(),
        done = new sys.thread.Lock(),
        queue:Array<String> = [],
        seen = new Map<String, Bool>(),
        claimed = new Map<String, Bool>(),// targets being downloaded: one download each
        active = 0,
        silent = Logger.get(true);
    // with the mutex held
    function enqueue(url:String)
      if (!seen.exists(url) && !prefetched.exists(url)) {
        seen[url] = true;
        queue.push(url);
      }
    for (u in urls) enqueue(u.toString());
    if (queue.length < 2)
      return;
    function work() {
      while (true) {
        mutex.acquire();
        if (queue.length == 0) {
          var finished = active == 0;
          mutex.release();
          if (finished) break;
          Sys.sleep(.01);// another worker may still queue dependencies
          continue;
        }
        var url = queue.shift();
        active++;
        mutex.release();
        var archive = null,
            job = null;
        try {
          job = urlToJob(Url.parse(url));
          var t = target(job, null);
          mutex.acquire();
          var key = if (t.into == null) job.normalized.toString() else t.into;
          var mine = !t.exists && !claimed.exists(key);
          claimed[key] = true;
          mutex.release();
          if (mine)
            archive = fetch(job, t.into, t.cacheFile, silent);
        }
        catch (e:Dynamic) {}
        mutex.acquire();
        if (archive != null) {
          prefetched[url] = { job: job, archive: archive };
          prefetched[job.normalized.toString()] = { job: job, archive: archive };
          for (d in archive.infos.dependencies)
            switch [d.value, archive.infos.haxeshimDependencies[d.name]] {
              case [FromUrl(u), null] if (!'${scope.scopeLibDir}/${d.name}.hxml'.exists()):
                enqueue(u.toString());
              default:
            }
        }
        active--;
        mutex.release();
      }
      done.release();
    }
    for (_ in 0...jobs)
      sys.thread.Thread.create(work);
    for (_ in 0...jobs)
      done.wait();
  }

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
        prefetch([for (d in infos.dependencies) switch [d.value, infos.haxeshimDependencies[d.name]] {
          case [FromUrl(url), null] if (!('${scope.scopeLibDir}/${d.name}.hxml'.exists() && options.alreadyInstalled[d.name])): url;
          default: continue;
        }]);
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
