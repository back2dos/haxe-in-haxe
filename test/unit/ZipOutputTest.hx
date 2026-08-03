package unit;

import core.ZipOutput;
import haxe.zip.Reader;
import sys.FileSystem;
import sys.io.File;

class ZipOutputTest {
	public static function main():Void {
		var path = Sys.getCwd() + "/.tmp-zip-output-test.zip";
		if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		var output = new ZipOutput(path, 0);
		output.addEntry("hello", "example.txt");
		output.close();
		output.close();
		var input = File.read(path, true);
		var entries = new Reader(input).read();
		input.close();
		FileSystem.deleteFile(path);
		if (entries.length != 1) throw "ZIP output entry count failed";
		var entry = entries.first();
		if (entry.fileName != "example.txt" || entry.compressed || entry.data.toString() != "hello") throw "ZIP output entry failed";

		var compressedPath = Sys.getCwd() + "/.tmp-zip-output-compressed-test.zip";
		if (FileSystem.exists(compressedPath)) FileSystem.deleteFile(compressedPath);
		var compressedOutput = new ZipOutput(compressedPath, 6);
		compressedOutput.addEntry("A long enough entry to be compressed repeatedly. A long enough entry to be compressed repeatedly.", "compressed.txt");
		compressedOutput.close();
		var compressedInput = File.read(compressedPath, true);
		var compressedEntries = new Reader(compressedInput).read();
		compressedInput.close();
		FileSystem.deleteFile(compressedPath);
		var compressedEntry = compressedEntries.first();
		if (compressedEntry.compressed || compressedEntry.data.toString().indexOf("A long enough") != 0) throw "Compressed ZIP output entry failed";
	}
}
