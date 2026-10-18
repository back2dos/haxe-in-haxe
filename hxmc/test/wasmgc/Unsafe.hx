// what the hybrid module covers (-D hxmc.wasm-gc with a linear memory for
// hxmc.unsafe and what crosses to the host), printed: compared with the
// native build's output (GcCheck)
import hxmc.unsafe.*;

@:hxmc.struct final class V2 {
	public final x:Float;
	public final y:Float;

	public inline function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
}

class Item {
	public var pos:V2;
	public var name:String;

	public function new(pos, name) {
		this.pos = pos;
		this.name = name;
	}
}

class Unsafe {
	static function sum(a:V2, b:V2):V2
		return new V2(a.x + b.x, a.y + b.y);

	static function count<A>(it:Iterable<A>, f:A->Bool):Int {
		var n = 0;
		for (x in it)
			if (f(x)) n++;
		return n;
	}

	static function main() {
		// malloc'd memory, loads and stores of every width
		var p = LibC.malloc(64);
		Mem.setI8(p, 0, -5);
		Mem.setI16(p, 2, 40000);
		Mem.setI32(p, 4, 0x12345678);
		Mem.setI64(p, 8, (1 : hxmc.I64) << 40);
		Mem.setF32(p, 16, 1.5);
		Mem.setF64(p, 24, Math.PI);
		Sys.println([Mem.getI8(p, 0), Mem.getU8(p, 0), Mem.getI16(p, 2), Mem.getU16(p, 2), Mem.getI32(p, 4)].join(" "));
		Sys.println(Std.string(Mem.getI64(p, 8)) + " " + Mem.getF32(p, 16) + " " + Mem.getF64(p, 24));
		for (i in 0...8)
			Mem.setI32At(p, 32, i, i * i);
		var s = 0;
		for (i in 0...8)
			s += Mem.getI32At(p, 32, i);
		Sys.println("squares " + s);
		LibC.free(p);
		// a frame area
		var f = Mem.stack(16);
		Mem.setI32(f, 0, 7);
		Mem.setI32(f, 4, 8);
		Sys.println("frame " + (Mem.getI32(f, 0) * Mem.getI32(f, 4)));
		// C strings: literals, an arena's copies, back to Haxe strings
		var lit:CString = (Mem.cstr("héllo") : Ptr<UInt8>);
		Sys.println("literal " + lit.toString() + " " + lit.length());
		Arena.scoped(a -> {
			var c = a.cstring("a ünïcode string, déjà vu");
			Sys.println(c.toString() + " " + c.length());
		});
		// Bytes through the linear memory
		var b = haxe.io.Bytes.ofString("bytes to C and back");
		var r = haxe.io.Bytes.alloc(b.length);
		BytesPtr.copyIn(r, 0, BytesPtr.of(b, 0, b.length), b.length);
		Sys.println(r.toString());
		// struct values whose fields are final (objects under WasmGC)
		var v = sum(new V2(1, 2), new V2(3, 4.5));
		var items = [new Item(v, "a"), new Item(new V2(-1, 0), "b")];
		Sys.println(v.x + " " + v.y + " " + items[0].pos.y + " " + items[1].pos.x);
		// Arrays and Strings through structural types (Iterable<T>)
		Sys.println(count([1.0, Math.NaN, 3.0], Math.isNaN) + " " + count([1, 2, 3, 4], x -> x % 2 == 0) + " " + Lambda.exists(["x", "y"], s -> s == "y"));
		var it:Iterable<String> = ["p", "q"];
		var out = [];
		for (x in it)
			out.push(x);
		Sys.println(out.join(","));
	}
}
