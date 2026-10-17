// haxe.zip.InflateImpl and Uncompress on hxmc (hxmc/std/haxe/zip): a zlib
// stream of dynamic blocks (node's zlib, level 9), stored blocks past
// InflateImpl's 32 KiB window (built here), a raw deflate stream with bytes
// after it, each from a BytesInput (inflated whole) and from another Input
// (byte by byte, as upstream), the same; the input left past each stream;
// a wrong checksum and a cut stream refused. Its expected output is
// --interp's (Eval: upstream's InflateImpl).
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.zip.InflateImpl;

// (any Input but a BytesInput: the streaming path)
class Bytewise extends haxe.io.Input {
	final b:Bytes;
	public var pos = 0;

	public function new(b:Bytes)
		this.b = b;

	override public function readByte():Int {
		if (pos >= b.length) throw new haxe.io.Eof();
		return b.get(pos++);
	}
}

class Inflate {
	static final ZLIB = "eNp13V3OdMeVXOF7j4JDyIjM3Ln3cGRYsBtW/wDuvvHojbLaRveJxRtB/EhJzJTEd7HqnHj+9g//9Nc/1h9/+du//I+//P0f/8vffr+kP/71f/" +
		"z1X//yx3/967/++6/4//7zP/76L//rH/72z//091/bf/zDP//rX/74n3/5l3/59z/q/PHf//KP//iXP/7bX//2//6F9++//49/+re//3b9/Xf+" +
		"8be//ON//W///se8f/+t//SL/f/+w/7/v3T++Md/+4//1lp//O+//uc/AemPf/q3//xnKf/xn4+iDQc+cWJdOLIqzqyXh1Z/Tq2BY3vRua04uP" +
		"05uXec3CdO7vs5uStP7pf/XTec3BMn3ytPvvU5+TacfG86+T5x8n0/J98VJ98vTr77c/I9efKz4uRHcPLj/N/5zpOf8zn5uXDyU3Ty8+Lkpz8n" +
		"PxMnvytOfvU5+XWe/O44+T1w8nvj5Lfg/+Lvc/LbcPI7dPJacfLS5+TlOHntOHmdz8nr5smr4uT14OTVcfKaPPlbn5M/0V/eTCd/O07+zufk78" +
		"bJX8XJ3/uc/HWe/E2cvBecvBUnb+fJe39O3gdO3hf/yl5x8n6fk3fHyXvi5LM+Jx/lycdx8tlw8jlx8rl58qnPyefByafp5DNxcq0VP9aUP9eW" +
		"8wfb2t+fbOvAj7Z182fbKvrhtl7+dFsNP97WfH++acElSKJb0O9H8vcatL/XoAM/3m9eg+p7DXpwDeq8Bg1dg1degwXXYH+vwZuuwQev4ffz+X" +
		"sNru81+OU1uCFzJjqHym5n22lT3Wln32lD4Wl/G0+bKk8bO087S087Wu9A7B2ovRO5d7D3IPgOFt+B5DvUfCei71D16WL26Wb36X7DTzfLTzfT" +
		"T/fbfroQf7oPupfyTzf7TwUBqPoWoIoSUIUNqMoIVH0rUJUZqMoOVH1DUAUlqJcpqEctqGf4GwCoQb1vDupRD+phEOplEep9k1Avm1CdUaj+Vq" +
		"EaslCdXaimMFRnGaqL/kbo24ZqikM11qEm81Dz7UNNBqImC1HzTUQNNKImI1FDlajJTNRAJ3p9Q9FL+HeEmIpe2Ype31j0ylr0ylz0+vaiFwSj" +
		"VxajRcloZTNaEI3Wtxotykbr8t8ZZzha33K0Mh2tbEf7G4821KOd+WhTP9oZkDYUpP1NSJsa0saItLMivVd8RJAV6Z0V6f2tSG+oSO+sSG+qSO" +
		"+sSG+oSO9vRfpQRfpgRfpkRfp8K9LnwEclWZE+34r0gYr0yYr0oYr0zYr0hYr0/VakL1WkL1akb1ak77cifbMifRs+Mpr4zAgq0gWfEBZVpCsr" +
		"0gUV6fpWpIsq0oUV6cqKdH0r0i8r0i8r0u9bkX6bPjvLivSjivTLivSDivT7VqQffnbY/OFhw6eHHR8fNnx+2PABYscniE0fITZ9hogfInZWpA" +
		"cq0vOtSA9VpAcr0pMV6flWpCcr0pMV6flWpAcqcq+syL2oIvcyfJgKFbnXtyL3oorcCytyr6zIvb4VuVdW5FZW5Na3IregIreyIreoIreyIreK" +
		"PlT+VuQWVeQWVuR2VuT2tyK3syK3syK3vxW5DRW5nRW5TRW5nRW5DRW597ci9xZ+uo4VuXdW5N7fitw7K3LvrMi9vxW5N1Tk3lmR+1BF7pMVuQ" +
		"9U5D7fityHKnKfy98yZEXu863IfbIi98mK3PdbkftCRe6bFbkvVeS+WZH7QkXu+63Ifaki98WK3DcrcteKr1uyIndlRe76VuQuqMhdWZG7qCJ3" +
		"ZUXugorc9a3I/agi98OK3C8rcr9vRe534GunrMj9vhW5H1TkflmR+1FF7s6K3A0VuftbkbupIndjRe7Oitz9rcjdWZG7G75+m/j+DSpyT1bkHv" +
		"ymebIi90BF7vlW5B6qyD1YkXuyIvd8K/KsrMizsiLP+lbkWZu+h8yKPIsq8qysyLOgIs/6VuRZVJFHWJFHWZFH34o8yoo8yoo8+lbkEVTk0YPv" +
		"Y6kij7Iij6Eij78VeUwVeYwVeZwVefytyOOsyOOsyONvRR7Tt9Ibvpbe+L30pi+m6ZvpHV9Nb/xuevOX0xu+nd7x9fTOijwnK/Kcb0WeAxV5Tl" +
		"bkOVSR52RFnlP0Bf23Is+hijwHK/LcrMhzvxV5blbkuVmR534r8lyoyHOzIs+lijw3K/JcqMhT34o8JXxSASvyVFbkqW9FnsqKPJUVeepbkaeg" +
		"Ik9lRZ5HFXleVuR5UJHnfSvyPKrI8y4/sZEVed63Is/LijwvK/L0tyJPQ0Wezoo8TRV5OivyNFTk6W9FnqaKPI0VeTor8syKR1eyIs9kRZ75Vu" +
		"QZqMgzWZFnqCLPZEWegYo8863Iu6gi78KKvCsr8q5vRd514BGerMi7vhV5F1TkXVmRd1FFXmVFXkFFXn0r8ooq8gor8ior8upbkVdZkVcNjzJN" +
		"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" +
		"kNeVKaAKU0KEppmJTSgCmlCVRKA6qUBlgpTbhSGoKlNCBLaZCW0oAtpSFcShO6lAZ5KQ37UhoApjQhTGmAmNKAMaUJZEpDypQGmCkNOlMagKY0" +
		"JE1pgprSoDWlYWxKA9qUJrgpDXhTGgCnNCFOaYic0oA5pUF0SgPqlIbYKU24UxqEpzQsT2mAntKEPaUBfEoD+pQm+CkN+VMaAKg0KFBpgKDSkE" +
		"GlCYRKgwqVhhkqDThUmoCoNCBRaYCi0oRFpSGMSgMalQY5Kg14VBoCqTQhUmmQpNKwSaUBlEoTKpUGWCoNuFSagKk0JFNpgKbSoE2lAZxKQzqV" +
		"JngqDfpUGgaqNCBUaYKo0oBR5QVIlVcoVV7EVHmBU+WFUJUXSFVeRFV5hVXlhViVF2tVXsBVeYVX5QVglReIVV5BVnmRWeUFaJUXqlVewFZ5kV" +
		"vlFXCVF8pVXkxXeYFd5RV4lRfoVV7AV3mFX+VFgJUXCFZeSFh5gWHlRYiVVyhWXshYebFj5QWQlVdIVl5AWXmBZeUVmJUXaVZewFl5oWflBaCV" +
		"F4lWXkFaeaFp5cWolReoVl7BWnmBa+UFsJVXyFZeRFt5gW3lhbiVF+hWXsRbeYVv5YXAlRcLV15AXHmFceUFyJUXKFdewVx5kXPlBdCVF0pXXk" +
		"BdeZF15RXYlRdqV17MXXmBd+UV4JUXiFdeQF55hXnlReiVF6hXXsheeYF75UXwlVfIV15IX3mxfeUF+JVX6FdewF95gX/lFQCWFwlYXkBgeaGB" +
		"5QUIlhcpWF7BYHmhg2UxhGWBhGUFhWWBhWUBhmWFhmURh2WBh2UhiGWBiGURiWWFiWUhimWximUBi2WFi2UBjGWBjGUFjWWRjWUBjmWhjmUBj2" +
		"WRj2UFkGWhkGUxkWWBkWUFkmWBkmUBk2WFk2URlGWBlGUhlWWBlWURlmWFlmUhl2Wxl2UBmGWFmGUBmWWBmWUFmmWRmmUBm2Whm2UBnGWRnGUF" +
		"nWWhnWUxnmWBnmUFn2WBn2UBoGWFoGURoWWBoWUhomWBomURo2WFo2UhpGWxpGUBpWWFpWUBpmWBpmUFp2WRp2UBqGWhqGUBqWWRqWUFqmWhqm" +
		"Uxq2WBq2UFrGWBrGUBrWWFrWURrmWBrmUhr2WBr2URsGWFsGUhsWWxsWUBsmWFsmUBs2WBs2UFtGWRtGUBtWWhtWUDtmWTtmUHt2Wjt2UzuGWD" +
		"uGUHuWWDuWUDumWHumUTu2WDu2UjvGWDvGUTvWWHvWUjvmWzvmUDv2WHv2UDwGWDwGUHwWWTwWUDwmWjwmUDw2WTw2UHxGWjxGUzxWWDxWUHxm" +
		"WDxmUDx2WHx2UTyGWDyGUjyWWDyWUTymWHymUjy2Wzy2UDzGWHzGUDzWWDzWUHzmWTzmUDz2Wjz2UD0GWT0GUH0WWj0WUz0mWD0mUH02WD02UD" +
		"1GWH1GUT1WWD1WUj1mWD1mUT12WH12Uj2GWz2GUD2WWH2WUD2mWD2mUH22WT22UD3GWj3GUD3WWT3WUH3mWj3mUz32WD32UH4GWD4GUD4WWH4W" +
		"UT4mWD4mUj42WD42UT5GWH5GUj5WWz5WUD5mWH5mUD52WD5+Udnpc3eV7e4Hl5o+flDZ6XN3le3uF5eaPn5c2elzd4Xt7heXmD5+UNnpd3eF7e" +
		"5Hl5g+fljZ6XN3he3uR5eYfn5Y2elzd7Xt7geXmH5+UNnpc3eF7e4Xl5k+flDZ6XN3pe3uB5eZPn5R2elzd6Xt7seXmD5+Udnpc3eF7e4Hl5h+" +
		"flTZ6XN3he3uh5eYPn5U2el3d4Xt7oeXmz5+UNnpd3eF7e4Hl5g+flHZ6XN3le3uB5eaPn5Q2elzd5Xt7heXmj5+XNnpc3eF7e4Xl5g+flDZ6X" +
		"d3he3uR5eYPn5Y2elzd4Xt7keXmH5+WNnpc3e17e4Hl5h+flDZ6XN3he3uF5eZPn5Q2elzd6Xt7geXmT5+Udnpc3el7e7Hl5g+flHZ6XN3he3u" +
		"B5eYfn5U2elzd4Xt7oeXmD5+VNnpd3eF7e6Hl5s+flA56XT3hePuB5+YDn5ROelw95Xj7gefmg5+UDnpcPeV4+4Xn5oOflw56XD3hePuF5+YDn" +
		"5QOel094Xj7kefmA5+WDnpcPeF4+5Hn5hOflg56XD3tePuB5+YTn5QOelw94Xj7hefmQ5+UDnpcPel4+4Hn5kOflE56XD3pePux5+YDn5ROelw" +
		"94Xj7gefmE5+VDnpcPeF4+6Hn5gOflQ56XT3hePuh5+bDn5QOel094Xj7gefmA5+UTnpcPeV4+4Hn5oOflA56XD3lePuF5+aDn5cOelw94Xj7h" +
		"efmA5+UDnpdPeF4+5Hn5gOflg56XD3hePuR5+YTn5YOelw97Xj7gefmE5+UDnpcPeF4+4Xn5kOflA56XD3pePuB5+ZDn5ROelw96Xj7sefmA5+" +
		"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";
	static final RAW = "bdZLblpREITheVZxl3Cqus9rOVhBsRXAlmJPsvrIwY7irpoguDz/Bm5/l6fb+WjH6fLyeLpffru8H8Lx+nh+PR0P59ePI/x7/Ti//Hq6PN/ux+" +
		"J4en49HT9PLy8fj8rjx+l6PR3fz5fPJ/b7/cft7X573O88Lqfrw/ePx8yPW18Ors83+/fUfVzf/n9ptOP3+esHAI7b29dPCR5fUxAmOKUY3SRj" +
		"SDOmRmOVamyTzea6CQknSzlDyplSzl7KObScU7/rZcq5pTyalgdKedCUR7jySCmPXspjSHlMKY9VymNreTYpT5jypP7OQ8szS3l2U57DleeU8l" +
		"ylPLeU9yblHaW8U8t7SHlPU967lPdh/uKzlPdlyvt25aNJ+UApH5TyEVI+spSPruVjSPmYpnwsKR9by2cr5RPu9EZXPkPKZ5by2aV8Dimfs5TP" +
		"peVzS/lqpnxByhe1fEUpX2nKV7dn9iHla5bytaR8bSnfrZRvaPmmlO8w5TulfHct36OU72nK93Lle0s5WpO1Bt1rjbrYWtTN1tKsttZ1t7Xhll" +
		"ubut3aMuut7brf0MwQALgp4H0l1zEg6hiQZr13HQNGHQOmGQOWjgHbjYFNx0CYMZB1DAw3BqYdw/t+rmPgqGPg1DFwGeZscY6TXajtEE53CPUd" +
		"wggPUY2HcMpDWOchVHoIsV4a7KXRXgr30nrPgC+t+NKQL535UtCXTn3oln3o6j70Cj90lR+60g+92g/d4A9d9Yfu+Ieu/sMwAMSoAsRwBMSwBs" +
		"RQBGJUBWIoAzHUgRgVghhGgphKQUxnQUzFIKbRIGblIKbzIKYFIaaKELOSEFNNiKUoxKoqxDIsxFIXYjkYYqkMsQwNsaoNsRwOsawOsZWH2NWH" +
		"2ApEbBUidiUitjEitiIR2ykRW5mIbZzIVqHI5qTIZqnIplZkq1hkUy2yKRfZqhfZDBjZVIyEIyOhZiQMGomqRsKxkbBuJBSORJUjoXQk1I5kxS" +
		"Np9EgqH0nnR1IBSRpBkpWQpDMkaRFJqiIZVZEMVSRDFcmoimQYRTJUkQynSIYqkmEUyaiKZDpFMq0imapIZlUkUxXJVEUyqyKZRpFMVSTTKZJd" +
		"FcluFMnO4w8=";

	static function text():String {
		var words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu"];
		var b = new StringBuf();
		for (i in 0...3000)
			b.add("line " + i + " " + words[(i * 7) % 13] + " " + words[(i * i) % 13] + "\n");
		return b.toString();
	}

	// a zlib stream of stored blocks of the given sizes over data
	static function stored(data:Bytes, sizes:Array<Int>):Bytes {
		var o = new haxe.io.BytesOutput(), at = 0;
		o.writeByte(0x78);
		o.writeByte(0x01);
		for (k in 0...sizes.length) {
			var n = sizes[k];
			o.writeByte(k == sizes.length - 1 ? 1 : 0);
			o.writeUInt16(n);
			o.writeUInt16(0xFFFF - n);
			o.writeFullBytes(data, at, n);
			at += n;
		}
		var a = haxe.crypto.Adler32.make(data);
		o.bigEndian = true;
		o.writeInt32(a);
		return o.getBytes();
	}

	static function sum(b:Bytes):String
		return b.length + " bytes, adler " + StringTools.hex(haxe.crypto.Adler32.make(b), 8);

	static function both(name:String, z:Bytes, ?bufsize:Int) {
		var a = InflateImpl.run(new BytesInput(z), bufsize == null ? 65536 : bufsize);
		var s = InflateImpl.run(new Bytewise(z), bufsize == null ? 65536 : bufsize);
		Sys.println(name + ": " + sum(a) + (a.compare(s) == 0 ? ", the same byte by byte" : ", byte by byte: " + sum(s)));
	}

	static function main() {
		var t = Bytes.ofString(text());
		var z = haxe.crypto.Base64.decode(ZLIB);
		both("dynamic blocks", z);
		Sys.println("the text: " + (InflateImpl.run(new BytesInput(z)).compare(t) == 0));
		// (gfx's Png: 32 KiB at a time)
		both("in 32 KiB reads", z, 32768);
		Sys.println("Uncompress.run: " + sum(haxe.zip.Uncompress.run(z)));
		var big = t.sub(0, 60000);
		var st = stored(big, [40000, 15000, 5000, 0]);
		both("stored blocks", st, 32768);
		Sys.println("stored, the text: " + (InflateImpl.run(new BytesInput(st), 32768).compare(big) == 0));
		// raw deflate, then bytes the inflater must leave
		var raw = haxe.crypto.Base64.decode(RAW);
		var after = Bytes.alloc(raw.length + 3);
		after.blit(0, raw, 0, raw.length);
		after.set(raw.length, 0xAB);
		after.set(raw.length + 1, 0xCD);
		after.set(raw.length + 2, 0xEF);
		var bi = new BytesInput(after), bw = new Bytewise(after);
		var out = Bytes.alloc(8000), out2 = Bytes.alloc(8000);
		var n = new InflateImpl(bi, false, false).readBytes(out, 0, 8000);
		var n2 = new InflateImpl(bw, false, false).readBytes(out2, 0, 8000);
		Sys.println("raw: " + n + " bytes, then " + StringTools.hex(bi.readByte(), 2) + "; byte by byte " + n2 + ", then " + StringTools.hex(bw.readByte(), 2)
			+ ", same " + (out.sub(0, n).compare(out2.sub(0, n2)) == 0));
		// a wrong checksum, a cut stream
		var bad = z.sub(0, z.length);
		bad.set(bad.length - 1, bad.get(bad.length - 1) ^ 1);
		for (input in [new BytesInput(bad), (new Bytewise(bad) : haxe.io.Input)])
			Sys.println("wrong checksum: " + (try {
				InflateImpl.run(input);
				"accepted";
			} catch (e:Dynamic) Std.string(e)));
		var cut = z.sub(0, z.length >> 1);
		for (input in [new BytesInput(cut), (new Bytewise(cut) : haxe.io.Input)])
			Sys.println("cut: " + (try {
				InflateImpl.run(input);
				"accepted";
			} catch (e:haxe.io.Eof) "Eof" catch (e:Dynamic) Std.string(e)));
	}
}
