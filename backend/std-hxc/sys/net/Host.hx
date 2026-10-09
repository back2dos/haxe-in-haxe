package sys.net;

import hxc.NativeNet;

// hxc target (backend/): IPv4 host names through hxc.NativeNet, as the Eval
// natives (haxe/std/eval/_std/sys/net/Host.hx) do. `ip` is the host-order IPv4.
class Host {
	public var host(default, null):String;
	public var ip(default, null):Int;

	public function new(name:String) {
		host = name;
		var r = NativeNet.resolve(name);
		if (r == null) throw "Unresolved host " + name;
		ip = r[0];
	}

	public function toString():String {
		return [(ip >>> 24) & 0xFF, (ip >>> 16) & 0xFF, (ip >>> 8) & 0xFF, ip & 0xFF].join(".");
	}

	public function reverse():String {
		var r = NativeNet.reverse(ip);
		if (r == null) throw "Host not found " + toString();
		return r;
	}

	public static function localhost():String {
		var r = NativeNet.gethostname();
		if (r == null) throw "Could not get the host name";
		return r;
	}
}
