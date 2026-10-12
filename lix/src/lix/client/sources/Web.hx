package lix.client.sources;

class Web {

  var interceptors:Array<Url->Null<Void->ArchiveJob>>;
  public function new(interceptors)
    this.interceptors = interceptors;

  public function schemes()
    return ['http', 'https'];

  public function processUrl(url:Url):ArchiveJob {

    for (i in interceptors)
      switch i(url) {
        case null:
        case p: return p();
      }

    return ({
      url: url,
      dest: Computed(function (l) return [l.name, l.version, url.toString()]),
      normalized: url,
      lib: null,
    } : ArchiveJob);
  }
}
