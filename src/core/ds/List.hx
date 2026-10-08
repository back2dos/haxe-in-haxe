package core.ds;

/** Array-backed OCaml list operations; paired operations reject unequal lengths. */
class List {
 static function sameLength<A,B>(a:Array<A>,b:Array<B>):Void {if(a.length!=b.length) throw new haxe.exceptions.ArgumentException("lists","different lengths");}
 public static function iter2<A,B>(f:A->B->Void,a:Array<A>,b:Array<B>):Void {sameLength(a,b);for(i in 0...a.length) f(a[i],b[i]);}
 public static function forAll2<A,B>(f:A->B->Bool,a:Array<A>,b:Array<B>):Bool {var n=Std.int(Math.min(a.length,b.length));for(i in 0...n) if(!f(a[i],b[i])) return false;sameLength(a,b);return true;}
 public static function exists2<A,B>(f:A->B->Bool,a:Array<A>,b:Array<B>):Bool {var n=Std.int(Math.min(a.length,b.length));for(i in 0...n) if(f(a[i],b[i])) return true;sameLength(a,b);return false;}
 public static function map2<A,B,C>(f:A->B->C,a:Array<A>,b:Array<B>):Array<C> {sameLength(a,b);return [for(i in 0...a.length) f(a[i],b[i])];}
 public static function foldLeft<A,B>(f:A->B->A,acc:A,l:Array<B>):A {for(v in l) acc=f(acc,v);return acc;}
 public static function foldRight<A,B>(f:A->B->B,l:Array<A>,acc:B):B {var i=l.length;while(i>0) acc=f(l[--i],acc);return acc;}
 public static function find<A>(f:A->Bool,l:Array<A>):A {for(v in l) if(f(v)) return v;throw NotFound.raise();}
 public static function hd<A>(l:Array<A>):A {if(l.length==0) throw new haxe.Exception("hd");return l[0];}
 public static function tl<A>(l:Array<A>):Array<A> {if(l.length==0) throw new haxe.Exception("tl");return l.slice(1);}
 public static function rev<A>(l:Array<A>):Array<A> {var out=l.copy();out.reverse();return out;}
 public static function exists<A>(f:A->Bool,l:Array<A>):Bool return Lambda.exists(l,f);
 public static function forAll<A>(f:A->Bool,l:Array<A>):Bool return Lambda.foreach(l,f);
}
