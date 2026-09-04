package context;

/** Runtime boundaries for milestones explicitly excluded by AGENTS.md. */
class DeferredServices {
	public static function display<T>():T throw new haxe.Exception("Display services are outside the source-only HXB milestone");
	public static function macros<T>():T throw new haxe.Exception("Macro execution is outside the source-only HXB milestone");
}
