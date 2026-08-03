package core;

// Port of haxe/src/core/stringError.ml.
class StringError {
	public static function levenshtein(first:String, second:String):Int {
		if (first.length == 0) return second.length;
		if (second.length == 0) return first.length;
		var matrix:Array<Array<Int>> = [];
		for (row in 0...first.length + 1) {
			var values:Array<Int> = [];
			for (column in 0...second.length + 1) values.push(row == 0 ? column : column == 0 ? row : 0);
			matrix.push(values);
		}
		for (row in 1...first.length + 1) {
			for (column in 1...second.length + 1) {
				var cost = first.charCodeAt(row - 1) == second.charCodeAt(column - 1) ? 0 : 1;
				matrix[row][column] = minimum(matrix[row - 1][column] + 1, matrix[row][column - 1] + 1, matrix[row - 1][column - 1] + cost);
			}
		}
		return matrix[first.length][second.length];
	}

	public static function getSimilar(input:String, candidates:Array<String>):Array<String> {
		if (candidates.length == 0) return [];
		var distances = candidates.map(function(candidate) return {candidate: candidate, distance: levenshtein(input, candidate)});
		distances.sort(function(a, b) return a.distance - b.distance);
		var similar:Array<String> = [];
		for (entry in distances) {
			if (entry.distance <= Std.int((input.length < entry.candidate.length ? input.length : entry.candidate.length) / 3)) similar.push(entry.candidate);
			else break;
		}
		return similar;
	}

	public static function stringError(input:String, candidates:Array<String>, message:String):String {
		if (candidates.length == 0) return message;
		var similar = getSimilar(input, candidates);
		return switch (similar.length) {
			case 0: message;
			case 1: '$message (Suggestion: ${similar[0]})';
			case _: '$message (Suggestions: ${similar.join(", ")})';
		};
	}

	static inline function minimum(first:Int, second:Int, third:Int):Int {
		return first < second ? (first < third ? first : third) : (second < third ? second : third);
	}
}
