package lix.client.sources;

class GitLab {

  public function intercept(url:Url):Null<Void->ArchiveJob>
    return
      if (url.scheme == 'https' && url.host != null && url.host.name == 'gitlab.com' && url.pathParts()[0] != 'api')
        () -> processUrl(url);
      else
        null;

  public function schemes()
    return ['gitlab'];

  var privateToken:String;
  public function new(?privateToken:String = '') {
    this.privateToken = switch privateToken.trim() {
      case '': '';
      case v: 'private_token=$v';
    }
  }

  static function host(?options:{ ?host:String })
    return switch options {
      case null | { host: null }: 'gitlab.com';
      case { host: v }: v;
    }

  public function grabCommit(owner, project, version, ?options:{ ?host:String }):String {
    var s = Download.text('https://${host(options)}/api/v4/projects/$owner%2F$project/repository/commits/$version?$privateToken');
    return
      try {
        var parsed:Dynamic = s.parse();
        if(version == '') parsed = parsed[0];
        (parsed.id:String);
      } catch (e:Dynamic) {
        var s = switch version {
          case null | '': '';
          case v: '#$v';
        }

        throw new Error('Failed to lookup sha for gitlab:$owner/$project$s');
      }
  }

  public function getArchive(owner:String, project:String, ?commitish:String, ?options:{ ?host:String }):ArchiveJob
    return switch commitish {
      case null:
        getArchive(owner, project, grabCommit(owner, project, '', options), options);
      case sha if (sha.length == 40):
        var url = 'https://${host(options)}/api/v4/projects/$owner%2F$project/repository/archive.zip?sha=$sha&${privateToken}';
        return ({
          normalized: Url.parse(url),
          dest: Computed(function (l) return [l.name, l.version, 'gitlab', sha]),
          url: Url.parse(url),
          lib: { name: project, version: null },
        } : ArchiveJob);
      case v:
        getArchive(owner, project, grabCommit(owner, project, v, options), options);
    }

  public function processUrl(url:Url):ArchiveJob
    return switch url.pathParts() {
      case [owner, project]: getArchive(owner, Git.strip(project), url.hash, { host: url.host == null ? null : url.host.toString() });
      default: throw new Error('invalid gitlab url $url');
    }
}
