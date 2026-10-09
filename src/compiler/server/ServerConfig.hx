package compiler.server;

// haxe/src/compiler/server/serverConfig.ml
class ServerConfig {
	public static var doNotCheckModules = false;

	public static var maxCompletionItems = 0;

	/**
		Maximum age in seconds for unused context caches before they are removed.
		10 minutes is long enough to survive bursts of display requests with
		varying defines, while still cleaning up contexts that are truly abandoned.
		If set to -1, the feature is disabled.
	**/
	public static final defaultStaleContextMaxAge = 600;

	public static var staleContextMaxAgeSeconds = defaultStaleContextMaxAge;

	public static function reset():Void {
		doNotCheckModules = false;
		maxCompletionItems = 0;
		staleContextMaxAgeSeconds = defaultStaleContextMaxAge;
	}
}
