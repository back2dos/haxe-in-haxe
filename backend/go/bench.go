// EXPERIMENTAL: backend/bench/Bench.hx translated by hand the way a Haxe ->
// Go generator would emit it (bench/WASM-BACKEND.md §2.10): Haxe Int is
// int32 (wrapping), enums are interface values with one struct per
// constructor, classes are structs with a vtable pointer, throw is panic and
// try/catch is a closure with recover.
package main

import (
	"fmt"
	"os"
)

var retain = os.Getenv("RETAIN") != ""

type Expr interface{ tag() int32 }
type Num struct{ v int32 }
type Var struct{ i int32 }
type Add struct{ a, b Expr }
type Mul struct{ a, b Expr }
type Neg struct{ e Expr }

func (Num) tag() int32 { return 0 }
func (Var) tag() int32 { return 1 }
func (*Add) tag() int32 { return 2 }
func (*Mul) tag() int32 { return 3 }
func (*Neg) tag() int32 { return 4 }

type HArray[T any] struct{ data []T }

func (a *HArray[T]) push(v T) { a.data = append(a.data, v) }
func (a *HArray[T]) get(i int32) T {
	var z T
	if i >= 0 && int(i) < len(a.data) {
		return a.data[i]
	}
	return z
}

type Rect struct {
	vt   *rectVt
	w, h int32
}
type rectVt struct{ area func(*Rect) int32 }

func rectArea(r *Rect) int32 { return r.w * r.h }

var rectVtbl = &rectVt{area: rectArea}
var squareVtbl = &rectVt{area: func(r *Rect) int32 { return rectArea(r) + 1 }}

type Fail struct{ code int32 }
type haxeException struct{ v any }

type Rng struct{ state int32 }

func hmod(a, b int32) int32 {
	if b == 0 {
		return 0
	}
	return a % b
}
func (r *Rng) next(n int32) int32 {
	r.state = hmod(r.state*75+74, 65537)
	return hmod(r.state>>3, n)
}

func build(rng *Rng, depth int32) Expr {
	if depth == 0 {
		if rng.next(4) == 0 {
			return Var{rng.next(8)}
		}
		return Num{rng.next(10)}
	}
	switch rng.next(6) {
	case 0, 1:
		a := build(rng, depth-1)
		return &Add{a, build(rng, depth-1)}
	case 2:
		a := build(rng, depth-1)
		return &Mul{a, build(rng, depth-1)}
	case 3:
		return &Neg{build(rng, depth-1)}
	case 4:
		return &Add{Num{0}, build(rng, depth-1)}
	default:
		return &Mul{build(rng, depth-1), Num{1}}
	}
}

func simplify(e Expr) Expr {
	switch x := e.(type) {
	case *Add:
		a, b := simplify(x.a), simplify(x.b)
		if n, ok := a.(Num); ok && n.v == 0 {
			return b
		}
		if n, ok := b.(Num); ok && n.v == 0 {
			return a
		}
		if n, ok := a.(Num); ok {
			if m, ok := b.(Num); ok {
				return Num{(n.v + m.v) & 0xFFFF}
			}
		}
		return &Add{a, b}
	case *Mul:
		a, b := simplify(x.a), simplify(x.b)
		if n, ok := a.(Num); ok && n.v == 0 {
			return Num{0}
		}
		if n, ok := b.(Num); ok && n.v == 0 {
			return Num{0}
		}
		if n, ok := a.(Num); ok && n.v == 1 {
			return b
		}
		if n, ok := b.(Num); ok && n.v == 1 {
			return a
		}
		if n, ok := a.(Num); ok {
			if m, ok := b.(Num); ok {
				return Num{(n.v * m.v) & 0xFFFF}
			}
		}
		return &Mul{a, b}
	case *Neg:
		switch y := simplify(x.e).(type) {
		case *Neg:
			return y.e
		case Num:
			return Num{(-y.v) & 0xFFFF}
		default:
			return &Neg{y}
		}
	}
	return e
}

func eval(e Expr, env *HArray[int32]) int32 {
	switch x := e.(type) {
	case Num:
		return x.v
	case Var:
		return env.get(x.i)
	case *Add:
		return (eval(x.a, env) + eval(x.b, env)) & 0xFFFF
	case *Mul:
		return (eval(x.a, env) * eval(x.b, env)) & 0xFFFF
	case *Neg:
		return (-eval(x.e, env)) & 0xFFFF
	}
	return 0
}

func size(e Expr) int32 {
	switch x := e.(type) {
	case *Add:
		return 1 + size(x.a) + size(x.b)
	case *Mul:
		return 1 + size(x.a) + size(x.b)
	case *Neg:
		return 1 + size(x.e)
	}
	return 1
}

func check(v int32) int32 {
	if hmod(v, 7) == 3 {
		panic(haxeException{&Fail{v}})
	}
	return v
}

func hmap(a *HArray[int32], f func(int32) int32) *HArray[int32] {
	r := &HArray[int32]{}
	for _, x := range a.data {
		r.push(f(x))
	}
	return r
}

func main() {
	iters, depth := int32(60), int32(24)
	env := &HArray[int32]{}
	for _, x := range []int32{1, 4, 7, 10, 13, 16, 19, 22} {
		env.push(x)
	}
	var total, failures int32
	shapes := &HArray[*Rect]{}
	shapes.push(&Rect{rectVtbl, 2, 3})
	shapes.push(&Rect{squareVtbl, 4, 4})
	shapes.push(&Rect{rectVtbl, 5, 1})
	kept := &HArray[Expr]{}
	for i := int32(0); i < iters; i++ {
		rng := &Rng{i + 1}
		e := build(rng, depth)
		s := simplify(e)
		if retain {
			kept.push(e)
			kept.push(s)
		}
		k := i & 3
		env = hmap(env, func(x int32) int32 { return (x*5 + k) & 0xFF })
		v := eval(s, env)
		func() { // try/catch
			defer func() {
				if r := recover(); r != nil {
					if he, ok := r.(haxeException); ok {
						if f, ok := he.v.(*Fail); ok {
							failures++
							total = (total + f.code) & 0xFFFFFF
							return
						}
					}
					panic(r)
				}
			}()
			total = (total*31 + check(v)) & 0xFFFFFF
		}()
		sh := shapes.get(hmod(i, 3))
		total = (total + size(e) + size(s) + sh.vt.area(sh)) & 0xFFFFFF
	}
	var keptSize int32
	for _, k := range kept.data {
		keptSize = (keptSize + size(k)) & 0xFFFFFF
	}
	fmt.Printf("%d\n%d\n%d\n", total, failures, keptSize)
}
