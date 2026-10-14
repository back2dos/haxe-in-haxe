package core.ds;

// port: the host natives of hxc (hxc/std) or of hxmc (hxmc/std, the machine-code target)
#if (target.name == "hxmc")
import hxmc.Native;
#elseif (target.name == "hxc")
import hxc.Native;
#end

class StrTools {
	// port: string equality for non-null strings; on HashLink `==` calls
	// String.__compare, so lengths are compared first.
	public static inline function eq(a:String, b:String):Bool {
		#if hl
		return a.length == b.length && a == b;
		#else
		return a == b;
		#end
	}

	// port: OCaml's physical inequality `!=` on strings. HashLink compares the
	// character buffers, the JVM and hxc (hxc/) references; other hosts have no
	// string identity and fall back to structural inequality (positions are then
	// encoded more compactly than upstream when a macro rebuilt a file name).
	public static inline function physNeq(a:Null<String>, b:Null<String>):Bool {
		#if hl
		return a == null || b == null ? a != b : @:privateAccess ((a.bytes : hl.Bytes) != (b.bytes : hl.Bytes));
		#elseif jvm
		return !jvm.Jvm.referenceEquals(a, b);
		#elseif (target.name == "hxc" || target.name == "hxmc")
		return !Native.refEq(a, b);
		#else
		return a != b;
		#end
	}

	// port: whether physNeq/physEq observe string identity on this host.
	public static inline final hasIdentity:Bool = #if (hl || jvm || target.name == "hxc" || target.name == "hxmc") true #else false #end;

	// port: OCaml's physical equality `==` on strings (see physNeq).
	public static inline function physEq(a:Null<String>, b:Null<String>):Bool return !physNeq(a, b);

	// port: `s.substring(start, end)` for 0 <= start <= end <= s.length. On HashLink
	// substring's optional end index is boxed on every call.
	public static inline function sub(s:String, start:Int, end:Int):String {
		#if hl
		return subHl(s, start, end - start);
		#else
		return s.substring(start, end);
		#end
	}

	#if hl
	static function subHl(s:String, pos:Int, len:Int):String @:privateAccess {
		if (len <= 0) return "";
		var bytes:hl.Bytes = s.bytes;
		if (len == 1) return String.__char__(bytes.getUI16(pos << 1));
		var b = new hl.Bytes((len + 1) << 1);
		b.blit(0, bytes, pos << 1, len << 1);
		b.setUI16(len << 1, 0);
		return String.__alloc__(b, len);
	}
	#end
}
