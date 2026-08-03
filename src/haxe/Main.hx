package haxe;

import compiler.Args;

/**
 * Bootstrap entry point for the Haxe implementation of the compiler.
 *
 * Compiler subsystems will be ported from haxe/src in small, traceable steps.
 */
class Main {
	static function main():Void {
		Args.parseArgs(Sys.args());
	}
}
