package lix.client.sources;

class GitHub {

  static function isArchive(p:Url)
    return switch p.pathParts() {
      case [_, _, 'archive', _]: true;
      default: false;
    }

  public function intercept(url:Url):Null<Void->ArchiveJob>
    return
      if (url.scheme == 'https' && url.host != null && url.host.name == 'github.com' && !isArchive(url))
        () -> processUrl(url);
      else
        null;

  public function schemes()
    return ['github', 'gh'];

  // `user:token`, or null
  var credentials:Null<String>;
  public function new(?credentials)
    this.credentials = credentials;

  static function auth(credentials:Null<String>)
    return if (credentials == null) '' else '$credentials@';

  public function grabCommit(owner, project, version):String
    return switch credentials {
      case null if (version == '' || !lix.client.haxe.UserVersion.isHash(version)): // short hashes will have to be resolved via API
        var s =
          try Download.bytes('https://github.com/$owner/$project.git/info/refs?service=git-upload-pack')
          catch (e:Error)
            throw switch e.code {
              case 401:
                new Error(e.code, e.message + ' - Possible typo in "$owner/$project"');
              default:
                e;
            }

        if (version == '')
          return s.toString().split(' HEAD')[0].substr(-40);

        var buf = new StringBuf();

        for (i in 0...s.length)
          switch s.get(i) {
            case 0:
            case v: buf.addChar(v);
          }


        for (l in buf.toString().split('\n')) {
          switch l.split(' ') {
            case [_.substr(-40) => sha, ref] if (sha.length == 40 && ref.endsWith('/$version')):
              return sha;
            default:
          }
        }
        throw new Error('Failed to lookup sha for github:$owner/$project$s');
      default:
        var s = Download.text('https://${auth(credentials)}api.github.com/repos/$owner/$project/commits?sha=$version');
        try
          return(s.parse()[0].sha:String)
        catch (e:Dynamic) {
          var s = switch version {
            case null | '': '';
            case v: '#$v';
          }

          throw new Error('Failed to lookup sha for github:$owner/$project$s');
        }
    }


  public function getArchive(owner:String, project:String, ?commitish:String, ?credentials:String):ArchiveJob {
    function doGet(sha)
      return getArchive(owner, project, sha, credentials);
    return switch commitish {
      case null:
        doGet(grabCommit(owner, project, ''));
      case sha if (sha.length == 40):
        return ({
          normalized: Url.parse('gh://${auth(credentials)}github.com/$owner/$project#$sha'),
          dest: Computed(function (l) return [l.name, l.version, 'github', sha]),
          url: Url.parse('https://${auth(credentials)}github.com/$owner/$project/archive/$sha.tar.gz'),
          lib: { name: project, version: null },
        } : ArchiveJob);
      case v:
        doGet(grabCommit(owner, project, v));
    }
  }

  public function processUrl(url:Url):ArchiveJob
    return switch url.pathParts() {
      case [owner, project]:
        getArchive(owner, Git.strip(project), url.hash, url.auth);
      default: throw new Error('invalid github url $url');
    }
}
