package lix.client.sources;

import lix.client.sources.haxelib.*;
import shim.SemVer;

class Haxelib {
  static inline var OFFICIAL = 'https://lib.haxe.org/';

  public var isOfficial(get, null):Null<Bool>;
    function get_isOfficial() return this.isOfficial ??= OFFICIAL == baseURL;

  final baseURL:String;

  public function new(baseURL = OFFICIAL) {
    this.baseURL = baseURL;
  }

  function getBaseUrl(?options:{ host: Null<shim.Url.Host> }):Url
    return switch options {
      case null | { host: null }: Url.parse(baseURL);
      case { host: h }: Url.parse('${if (h.port == null) 'https' else 'http'}://$h/');
    }

  function resolve(url:String, ?options:{ host: Null<shim.Url.Host> }):Url
    return getBaseUrl(options).resolve(Url.parse(url));

  public function schemes():Array<String>
    return ['haxelib'];

  public function processUrl(url:Url):ArchiveJob
    return
      switch url.queryMap()['url'] {
        case v if (v == null || v == baseURL):
          switch url.pathParts() {
            case [v]: getArchive(v, url.hash, { host: url.host });
            default: throw new Error('invalid haxelib url $url');
          }
        case v:
          new Haxelib(v).processUrl(url);
      }

  static inline function esc(s:String)
    return s.replace('.', ',');

  function getArchive(name:String, ?version:String, ?options:{ host: Null<shim.Url.Host> }):ArchiveJob {
    var infos = getInfos(name, options);
    var host = switch options {
      case null | { host: null }: null;
      case { host: h }: h;
    }

    var isCustom = !(host == null && isOfficial);
    var name = infos.name;
    if (version == null) {
      function getVersions(?filter:SemVer->Bool) {
        var ret = [for (v in infos.versions) switch SemVer.parse(v.name) {
          case null: continue;
          case v if (filter == null || filter(v)): v;
          default: continue;
        }];
        ret.sort((a, b) -> b.compare(a));
        return ret;
      }

      version =
        switch getVersions(v -> v.preview == null) {
          case []:
            getVersions()[0].toString();
          case v: v[0].toString();
        }
    }
    else {
      var found = false;
      for (v in infos.versions)
        if (v.name == version) {
          found = true;
          break;
        }
      if (!found)
        throw new Error('Library $name has no version $version');
    }
    return ({
      url: resolve('/files/3.0/${esc(name)}-${esc(version)}.zip', options),
      normalized: Url.make({
        scheme: 'haxelib',
        hosts: if (host == null) [] else [host],
        path: '/$name',
        hash: version,
        query: if (isCustom) 'url=' + baseURL.urlEncode() else null,
      }),
      dest: Fixed([name, version, 'haxelib' + if (isCustom) '@' + getBaseUrl(options).toString().urlEncode() else '']),
      kind: Zip,
      lib: { name: name, version: version }
    } : ArchiveJob);
  }

  // port: haxe.remoting.HttpAsyncConnection (gone from std since Haxe 4): a
  // POST of the serialized call to the haxelib server's remoting endpoint
  function getInfos(name:String, ?options):ProjectInfos {
    var url = this.resolve('/api/3.0/index.n', options).toString();
    try {
      var s = new haxe.Serializer();
      s.serialize(['api', 'infos']);
      s.serialize([name]);
      var res = shim.Http.request(url, {
        method: 'POST',
        headers: [
          { name: 'X-Haxe-Remoting', value: '1' },
          { name: 'Content-Type', value: 'application/x-www-form-urlencoded' },
        ],
        body: Bytes.ofString('__x=' + s.toString().urlEncode()),
      });
      var data = res.body.toString();
      if (data.substr(0, 3) != 'hxr')
        throw 'Invalid response : \'$data\'';
      return new haxe.Unserializer(data.substr(3)).unserialize();
    }
    catch (e:Dynamic)
      throw Error.withData('Failed to get version information from haxelib because ${Std.isOfType(e, haxe.Exception) ? (e:haxe.Exception).message : Std.string(e)}', e);
  }

}
