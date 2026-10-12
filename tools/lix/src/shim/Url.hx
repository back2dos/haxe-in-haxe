package shim;

using StringTools;

// port: tink.Url (tink_url): the parsing, resolution and printing of URLs that
// lix relies on, including its non-hierarchical forms (`haxelib:name#version`,
// `gh:owner/repo`, `git:<url>`, whose payload is everything after the scheme)
class Url {
	public final scheme:Null<String>;
	public final payload:String;
	public final hosts:Array<Host>;
	public final auth:Null<String>;
	public final path:String;
	public final query:Null<String>;
	public final hash:Null<String>;

	function new(scheme, payload, hosts, auth, path, query, hash) {
		this.scheme = scheme;
		this.payload = payload;
		this.hosts = hosts;
		this.auth = auth;
		this.path = path;
		this.query = query;
		this.hash = hash;
	}

	public var host(get, never):Null<Host>;

	function get_host()
		return hosts[0];

	/** `user:password@`, or the empty string. **/
	public var authString(get, never):String;

	function get_authString()
		return auth == null ? '' : '$auth@';

	/** The non-empty segments of the path, URL-decoded. **/
	public function pathParts():Array<String>
		return [for (p in path.split('/')) if (p != '') try p.urlDecode() catch (e:Dynamic) ''];

	/** The query's parameters (raw values). **/
	public function queryMap():Map<String, String> {
		var ret = new Map();
		if (query != null)
			for (part in query.split('&')) {
				var eq = part.indexOf('=');
				var name = eq == -1 ? part : part.substr(0, eq);
				var value = eq == -1 ? '' : part.substr(eq + 1);
				ret[try name.trim().urlDecode() catch (e:Dynamic) ''] = try value.trim().urlDecode() catch (e:Dynamic) '';
			}
		return ret;
	}

	public function resolve(that:Url):Url
		return
			if (that.scheme != null) that;
			else if (that.host != null)
				new Url(scheme, that.payload, that.hosts, that.auth, that.path, that.query, that.hash);
			else
				make({
					path: joinPath(path, that.path),
					scheme: scheme,
					query: that.query,
					auth: auth,
					hosts: hosts,
					hash: that.hash
				});

	public function toString():String
		return scheme == null ? payload : '$scheme:$payload';

	static public function make(parts:{?path:String, ?query:String, hosts:Array<Host>, ?auth:String, ?scheme:String, ?hash:String}):Url {
		var path = parts.path == null ? null : normalize(parts.path);
		var payload = '';
		switch [parts.hosts, parts.auth] {
			case [[], null]:
			case [v, null]: payload += '//' + v.join(',');
			case [[], auth]: payload += '//$auth';
			case [v, auth]: payload += '//$auth' + v.join(',');
		}
		if (path != null)
			payload += path;
		if (parts.query != null)
			payload += '?' + parts.query;
		if (parts.hash != null)
			payload += '#' + parts.hash;
		return new Url(parts.scheme, payload, parts.hosts, parts.auth, path, parts.query, parts.hash);
	}

	static public function parse(s:String):Url {
		if (s == null)
			s = '';
		s = s.trim();
		if (s.startsWith('data:'))
			return new Url('data', s.substr(5), [], null, null, null, null);

		var FORMAT = ~/^(([a-zA-Z][a-zA-Z0-9\-+.]*):)?((\/\/(([^@\/]+)@)?([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?)$/;
		var HOST = ~/^(\[(.*)\]|([^:]*))(:(.*))?$/;
		FORMAT.match(s);

		var hosts = switch FORMAT.matched(7) {
			case null: [];
			case v:
				[for (host in v.split(',')) {
					HOST.match(host);
					var name = switch [HOST.matched(3), HOST.matched(2)] {
						case [ipv4, null]: ipv4;
						case [null, ipv6]: '[$ipv6]';
						case _: null;
					}
					var port = switch HOST.matched(5) {
						case null: null;
						case v: Std.parseInt(v);
					}
					new Host(name, port);
				}];
		}
		var path = FORMAT.matched(8);
		if (path == null)
			path = '';
		if (hosts.length > 0 && path.charAt(0) != '/')
			path = '/$path';

		return new Url(FORMAT.matched(2), FORMAT.matched(3), hosts, FORMAT.matched(6), normalize(path), FORMAT.matched(10), FORMAT.matched(12));
	}

	// tink.url.Path.join
	static function joinPath(a:String, b:String):String
		return
			if (b == null || b == '') a;
			else if (b.charAt(0) == '/') b;
			else if (a.charAt(a.length - 1) == '/') normalize(a + b);
			else switch a.lastIndexOf('/') {
				case -1: b;
				case v: a.substr(0, v + 1) + b;
			}

	// tink.url.Path.normalize
	static public function normalize(s:String):String {
		s = s.replace('\\', '/').trim();
		if (s == '.')
			return './';

		var isDir = s.endsWith('/..') || s.endsWith('/') || s.endsWith('/.');

		var parts = [],
			isAbsolute = s.startsWith('/'),
			up = 0;

		for (part in s.split('/'))
			switch part.trim() {
				case '':
				case '.':
				case '..':
					if (parts.pop() == null) up++;
				case v: parts.push(v);
			}

		if (isAbsolute)
			parts.unshift('');
		else
			for (i in 0...up)
				parts.unshift('..');

		if (isDir)
			parts.push('');

		return parts.join('/');
	}
}

// port: tink.url.Host
class Host {
	public final name:Null<String>;
	public final port:Null<Int>;

	public function new(name:Null<String>, ?port:Int) {
		this.name = name;
		this.port = port;
	}

	/** `name[:port]` as typed by a user, e.g. `--haxelib-url`. **/
	static public function ofString(s:Null<String>):Null<Host>
		return
			if (s == null) null;
			else switch s.lastIndexOf(':') {
				case -1: new Host(s);
				case v: new Host(s.substr(0, v), Std.parseInt(s.substr(v + 1)));
			}

	public function toString():String
		return port == null ? name : '$name:$port';
}
