// Checks the mbedtls natives (sys.ssl) of a build of the port against a local
// TLS server, e.g. `openssl s_server -accept 4433 -cert cert.pem -key key.pem -www`
// with a certificate for "localhost" signed by ca.pem. Run in the port's Eval:
//   <port> -cp backend/bench/natives --run Tls 4433 ca.pem [host]
// or build it for the hxc target. Prints "tls: ok" when every check passed. With a
// host name, also GETs https://<host>/
// (verified with the system CA certificates, Certificate.loadDefaults).
import sys.net.Host;
import sys.ssl.Certificate;
import sys.ssl.Socket;

class Tls {
	static var failures = 0;

	static function check(what:String, ok:Bool) {
		Sys.println((ok ? "ok   " : "FAIL ") + what);
		if (!ok) failures++;
	}

	// GET / over TLS; returns the first response line or the error
	static function get(port:Int, verify:Bool, ?ca:Certificate, hostname = "localhost"):String {
		var s = new Socket();
		try {
			s.verifyCert = verify;
			if (ca != null) s.setCA(ca);
			s.setHostname(hostname);
			s.connect(new Host("127.0.0.1"), port);
			s.write("GET / HTTP/1.0\r\n\r\n");
			var line = s.input.readLine();
			var peer = s.peerCertificate();
			var rest = s.input.readAll().toString();
			s.close();
			return line + " (peer " + (peer == null ? "none" : peer.commonName) + ", " + (rest.length > 0 ? "body" : "no body") + ")";
		} catch (e:Dynamic) {
			try s.close() catch (_:Dynamic) {}
			return "error: " + Std.string(e);
		}
	}

	static function main() {
		var args = Sys.args();
		var port = Std.parseInt(args[0]);
		var ca = Certificate.loadFile(args[1]);
		check("ca loaded: " + ca.commonName, ca.commonName != null);

		var r = get(port, false);
		Sys.println("  no verification: " + r);
		check("handshake and GET without verification", StringTools.startsWith(r, "HTTP/1.0 200"));

		r = get(port, true, ca);
		Sys.println("  verified with the CA: " + r);
		check("handshake verified with the CA", StringTools.startsWith(r, "HTTP/1.0 200") && r.indexOf("peer localhost") >= 0);

		r = get(port, true, ca, "wrong.example");
		Sys.println("  wrong host name: " + r);
		check("wrong host name rejected", StringTools.startsWith(r, "error"));

		r = get(port, true, Certificate.fromString(sys.io.File.getContent(args[1])), "localhost");
		check("CA from a PEM string", StringTools.startsWith(r, "HTTP/1.0 200"));

		var defaults = Certificate.loadDefaults();
		var n = 0;
		var c = defaults;
		while (c != null) {
			n++;
			c = c.next();
		}
		// an empty chain is one blank node
		if (n == 1 && defaults.commonName == null && defaults.subject("O") == null) n = 0;
		Sys.println("  system CA certificates: " + n);
		check("system CA certificates loaded", n > 0);

		r = get(port, true, defaults);
		Sys.println("  verified with the system CAs: " + r);
		check("local CA not trusted by the system CAs", StringTools.startsWith(r, "error"));

		if (args.length > 2) {
			// a GET verified with the system CAs (DEFAULT_CA, Certificate.loadDefaults)
			// written out: the hxc target can't assign haxe.Http's dynamic methods yet
			var host = args[2];
			var s = new Socket();
			var status = "";
			try {
				s.connect(new Host(host), 443);
				s.write('GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
				status = s.input.readLine();
				var body = s.input.readAll();
				status += ', ${body.length} more bytes';
				s.close();
			} catch (e:Dynamic) {
				status = "error: " + Std.string(e);
			}
			Sys.println('  GET https://$host/: $status');
			check("https GET verified with the system CAs", StringTools.startsWith(status, "HTTP/1.1 200") || StringTools.startsWith(status, "HTTP/1.0 200"));
		}
		Sys.println(failures == 0 ? "tls: ok" : 'tls: $failures failure(s)');
	}
}
