package core.display;

import core.Globals;
import core.Globals.Pos;
import core.Path.UniqueKey;

// port: from haxe/src/core/display/displayPosition.ml.
class DisplayPosition {
	public static final displayPosition = new DisplayPositionContainer();

	public static function enclosesPosition(target:Pos,
			p:Pos):Bool return target.pmin != -1 && target.pmax != -1 && p.pmin <= target.pmin && p.pmax >= target.pmax;

	public static function enclosesPositionGt(target:Pos,
			p:Pos):Bool return target.pmin != -1 && target.pmax != -1 && p.pmin <= target.pmin && p.pmax > target.pmax;
}

class DisplayPositionContainer {
	/** Current display position **/
	var pos:Pos = Globals.nullPos;
	var fileKey:Null<String> = null;
	var fileKeys:Array<String> = [];
	/**
		Display position value which was set with the latest `display_position#set p` call.
		Kept even after `display_position#reset` call.
	**/
	var lastPos:Pos = Globals.nullPos;

	public function new() {}

	/**
		Set current display position
	**/
	public function set(p:Pos):Void {
		pos = p;
		lastPos = p;
		fileKey = null;
		fileKeys = p.pfile == core.Path.getFullPath("? input") ? [] : [UniqueKey.create(p.pfile)];
	}

	public function setFiles(files:Array<String>):Void fileKeys = files;

	public function getFiles():Array<String> return fileKeys;

	/**
		Get current display position
	**/
	public function get():Pos return pos;

	/**
		Get current display position
	**/
	public function getFileKey():String {
		if (fileKey == null) fileKey = UniqueKey.create(pos.pfile);
		return fileKey;
	}

	/**
		Clears current display position.
	**/
	public function reset():Void {
		pos = Globals.nullPos;
		fileKey = null;
		fileKeys = [];
	}

	/**
		Check if `p` contains current display position
	**/
	public function enclosedIn(p:Pos):Bool return DisplayPosition.enclosesPosition(pos, p);

	/**
		Check if a file with `file_key` contains current display position
	**/
	public function isInFile(key:String):Bool return (pos.pfile != "?" && getFileKey() == key) || hasFile(key);

	/**
		This is a hack; currently used by Diagnostics.collect_diagnostics when sending multiple files
		to run diagnostics on via json rpc
	**/
	public function hasFile(key:String):Bool return fileKeys.contains(key);

	/**
		Cut `p` at the position of the latest `display_position#set pos` call.
	**/
	public function cut(p:Pos):Pos return {pfile: p.pfile, pmin: p.pmin, pmax: lastPos.pmax};

	/**
		Temporarily reset display position, run `fn` and then restore display position.
	**/
	public function runOutside<T>(fn:Void->T):T {
		var saved = get();
		reset();
		try {
			var result = fn();
			set(saved);
			return result;
		} catch (error:haxe.Exception) {
			set(saved);
			throw error;
		}
	}

	/**
		Creates a new position with the file of [p] and the min/max of the display position.
	**/
	public function withPos(p:Pos):Pos return {pfile: p.pfile, pmin: lastPos.pmin, pmax: lastPos.pmax};
}
