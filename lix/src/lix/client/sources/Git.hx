package lix.client.sources;

class Git {

  var scope:Scope;

  public function schemes() return ['git'];

  public function new(scope)
    this.scope = scope;

  static public function strip(name:String)
    return
      if (name.endsWith('.git')) name.withoutExtension();
      else name;

  static function cli(cwd:String) {
    Fs.ensureDir(cwd.addTrailingSlash());
    return {
      call: function (args:Array<String>) {
        switch Exec.sync('git', cwd, args).sure() {
          case 0:
          case code: throw new Error(code, 'git ${args[0]} failed');
        }
      },
      eval: function (args:Array<String>):String {
        var o = Exec.eval('git', cwd, args, true).sure();
        return switch o {
          case { status: 0 }: o.stdout;
          default: throw new Error(o.status, 'git ${args[0]} failed');
        }
      }
    }
  }

  public function processUrl(raw:Url):ArchiveJob {
    var url = Url.parse(raw.payload);
    var origin = url.resolve(Url.parse('')).toString(),
        version = switch url.hash {
          case null | '': 'HEAD';
          case v: v;
        };

    var git = cli('.');

    var sha =
      if (version.length != 40)
        switch git.eval(['ls-remote', origin, version]).trim() {
          case '': throw new Error('Cannot resolve version $version');
          case v: v.substr(0, 40);
        }
      else
        version;

    return {
      url: raw,
      normalized: Url.parse(raw.scheme + ':' + url.resolve(Url.parse('#$sha')).toString()),
      dest: Computed(l -> return [l.name, l.version, 'git', sha]),
      lib: { name: null, version: null },
      kind: Custom(function (ctx) return {
        var repo = Path.join([scope.libCache, '.gitrepos', DownloadedArchive.escape(origin)]);
        var git = cli(repo);
        git.call(
          if ('$repo/.git'.exists()) ['fetch']
          else ['clone', origin, '.']
        );
        git.call(['-c', 'advice.detachedHead=false', 'checkout', sha]);
        git.call(['submodule', 'update', '--init', '--recursive']);
        Fs.copy(repo, ctx.dest, function (name) return name != '$repo/.git');
        ctx.dest;
      })
    };
  }
}
