// hxc: haxe/std/eval/_std/sys/ssl/Mbedtls.hx (the shared mbedtls state of
// sys.ssl) over hxc.NativeSsl (rt_ssl.c) instead of the mbedtls.* classes

package sys.ssl;

import hxc.NativeSsl;

class Mbedtls {
	static var entropy:Dynamic;
	static var ctr:Dynamic;

	static public function getDefaultEntropy():Dynamic {
		if (entropy == null) {
			entropy = NativeSsl.entropyInit();
		}
		return entropy;
	}

	static public function getDefaultCtrDrbg():Dynamic {
		if (ctr == null) {
			ctr = NativeSsl.ctrDrbgInit();
			NativeSsl.ctrDrbgSeed(ctr, getDefaultEntropy());
		}
		return ctr;
	}

	static public function loadDefaultCertificates(certificate:Dynamic) {
		if (NativeSsl.certLoadDefaults(certificate) == 0) {
			return;
		}
		var defPaths = switch (Sys.systemName()) {
			case "Linux":
				[
					"/etc/ssl/certs/ca-certificates.crt", // Debian/Ubuntu/Gentoo etc.
					"/etc/pki/tls/certs/ca-bundle.crt", // Fedora/RHEL
					"/etc/ssl/ca-bundle.pem", // OpenSUSE
					"/etc/pki/tls/cacert.pem", // OpenELEC
					"/etc/ssl/certs", // SLES10/SLES11
					"/system/etc/security/cacerts" // Android
				];
			case "BSD":
				[
					"/usr/local/share/certs/ca-root-nss.crt", // FreeBSD/DragonFly
					"/etc/ssl/cert.pem", // OpenBSD
					"/etc/openssl/certs/ca-certificates.crt", // NetBSD
				];
			case "Android":
				["/system/etc/security/cacerts"];
			default:
				[];
		}
		for (path in defPaths) {
			if (sys.FileSystem.exists(path)) {
				if (sys.FileSystem.isDirectory(path))
					NativeSsl.x509CrtParsePath(certificate, path);
				else
					NativeSsl.x509CrtParseFile(certificate, path);
			}
		}
	}
}
