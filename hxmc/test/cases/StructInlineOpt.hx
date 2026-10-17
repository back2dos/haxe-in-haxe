// StructInline with the analyzer's optimizations (copy propagation, the
// fusion of user variables): its main, inline, is inlined here, so the same
// golden output.
@:analyzer(optimize)
class StructInlineOpt {
	static function main()
		StructInline.main();
}
