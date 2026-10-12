package shim;

// port: tink.semver.Version (tink_semver): `major.minor.patch` with an optional
// `-alpha`, `-beta` or `-rc` preview and preview number, and its ordering
class SemVer {
	public final major:Int;
	public final minor:Int;
	public final patch:Int;
	public final preview:Null<String>;
	public final previewNum:Int;

	function new(major, minor, patch, preview, previewNum) {
		this.major = major;
		this.minor = minor;
		this.patch = patch;
		this.preview = preview;
		this.previewNum = previewNum;
	}

	/** The version, or null when `s` is not one. **/
	static public function parse(s:String):Null<SemVer> {
		// per call: an EReg's match state is not shared between threads (Libraries.prefetch)
		var FORMAT = ~/^\s*([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)(\.([0-9]+))?)?\s*$/;
		return
			if (s == null || !FORMAT.match(s)) null;
			else new SemVer(
				Std.parseInt(FORMAT.matched(1)),
				Std.parseInt(FORMAT.matched(2)),
				Std.parseInt(FORMAT.matched(3)),
				FORMAT.matched(5),
				FORMAT.matched(7) == null ? -1 : Std.parseInt(FORMAT.matched(7))
			);
	}

	static function idx(p:Null<String>)
		return switch p {
			case null: 100;
			case 'alpha': 1;
			case 'beta': 2;
			case _: 3;
		}

	public function compare(that:SemVer):Int {
		for (d in [
			major - that.major,
			minor - that.minor,
			patch - that.patch,
			idx(preview) - idx(that.preview),
			previewNum - that.previewNum
		])
			if (d != 0)
				return d > 0 ? 1 : -1;
		return 0;
	}

	public function toString() {
		var ret = '$major.$minor.$patch';
		if (preview != null) {
			ret += '-$preview';
			if (previewNum != -1)
				ret += '.$previewNum';
		}
		return ret;
	}
}
