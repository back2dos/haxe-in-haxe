package context;

import core.Globals;
import core.Ast;
import core.Meta;
import core.data.MetaDataApi;
import core.Error;

/**
	Determines how the core API check is performed for a class.
	- On: Always perform the core API check.
	- Off: Never check. Can be set explicitly to override an Implied check.
	- Implied: Check only if a core definition type exists, otherwise ignore.
**/
enum CoreApiCheck {
	On;
	Off;
	Implied;
}

@:structInit class CoreApiConfiguration {
	public var check:CoreApiCheck;

	public inline function new(check:CoreApiCheck) {
		this.check = check;
	}

	public inline function clone():CoreApiConfiguration return new CoreApiConfiguration(check);
}

class CoreApiConfigReader {
	final api:Dynamic;

	public function new(api:Dynamic) this.api = api;

	public function readCoreApiCheck(data:Dynamic):CoreApiCheck return switch api.readIdent(data) {
		case "On": On;
		case "Off": Off;
		case "Implied": Implied;
		case s: Error.raiseTypingError("Unknown value for check: " + s + " (expected On, Off, or Implied)", Globals.nullPos);
	};

	public function readCoreApiConfig(config:CoreApiConfiguration, data:Dynamic):Void {
		function read(data:Dynamic):Void {
			var fields:Array<Dynamic> = api.readObject(data);
			for (field in fields) switch field.name {
				case "check":
					config.check = readCoreApiCheck(field.value);
				case s:
					Error.raiseTypingError("Unknown key for coreApi config: " + s, Globals.nullPos);
			}
		}
		api.readOptional(data, read);
	}
}

class CoreApiConfig {
	public static function defaultCoreApiConfig():CoreApiConfiguration return {check: On};

	public static function ofCoreApiMetadataEntry(entry:MetadataEntry):CoreApiConfiguration {
		var config = defaultCoreApiConfig();
		new CoreApiConfigReader(MetaReaderApi).readCoreApiConfig(config, MetaDataApi.ofMetadataEntry(entry));
		return config;
	}

	/**
		Returns true if the given file path is in an implied core API location:
		- Directly in a `_std/` directory (non-recursive, e.g. `_std/Array.hx`)
		- In `_std/haxe/` (recursive)
		- In `_std/sys/` (recursive)
	**/
	public static function isImpliedCoreApiFile(filePath:String):Bool {
		// Normalize path separators to forward slashes
		var normalizedPath = filePath.split("\\").join("/");
		var marker = "/_std/";
		var index = normalizedPath.indexOf(marker);
		if (index == -1) return false;
		var afterStd = normalizedPath.substr(index + marker.length);
		// Implied for: direct file in _std/, or files in _std/haxe/ or _std/sys/ subdirectories
		return afterStd.indexOf("/") == -1 || StringTools.startsWith(afterStd, "haxe/") || StringTools.startsWith(afterStd, "sys/");
	}

	/**
		Determines the core_api_check value for a class based on its metadata and file location.
	**/
	public static function getCoreApiCheck(meta:Metadata, filePath:String):CoreApiCheck {
		var entry = try Meta.get(Meta.CoreApi, meta) catch (_:core.Meta.MetaNotFound) null;
		return entry != null ? ofCoreApiMetadataEntry(entry).check : isImpliedCoreApiFile(filePath) ? Implied : Off;
	}

	public static function sCoreApiCheck(value:CoreApiCheck):String return switch value {
		case On: "On";
		case Off: "Off";
		case Implied: "Implied";
	};
}
