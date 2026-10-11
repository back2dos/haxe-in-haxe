(* EXPERIMENTAL: backend/bench/Bench.hx translated by hand in the style a
   Haxe -> OCaml generator would emit (bench/WASM-BACKEND.md §2.8): every
   Haxe Int goes through the integer layer below, classes are records with a
   vtable, interface calls go through the vtable, Haxe arrays are growable
   records, throw carries the Haxe value.
   build.sh substitutes RETAIN and INTLAYER: int63.ml for native OCaml
   (63-bit int, wrapped to 32 bits), int32.ml for wasm_of_ocaml (whose int
   has 31 bits). *)

let retain = RETAIN

INTLAYER

type expr = Num of hint | Var of hint | Add of expr * expr | Mul of expr * expr | Neg of expr

type 'a harray = { mutable len : int; mutable data : 'a array }
let arr_make () = { len = 0; data = [||] }
let arr_push a v =
  if a.len = Array.length a.data then begin
    let n = Array.make (max 4 (2 * a.len)) v in
    Array.blit a.data 0 n 0 a.len;
    a.data <- n
  end;
  Array.unsafe_set a.data a.len v;
  a.len <- a.len + 1
let[@inline] arr_get a i dflt = let i = to_int i in if i >= 0 && i < a.len then Array.unsafe_get a.data i else dflt

type rect = { cid : int; vt : rect_vt; mutable w : hint; mutable h : hint }
and rect_vt = { area : rect -> hint }
let rect_area r = r.w *! r.h
let rect_vt = { area = rect_area }
let square_vt = { area = (fun r -> rect_area r +! lit 1) }
let new_rect w h = { cid = 1; vt = rect_vt; w; h }
let new_square s = { cid = 2; vt = square_vt; w = s; h = s }

type fail = { fcid : int; code : hint }
exception Haxe_exception of Obj.t
let is_fail (v : Obj.t) = (Obj.magic v : fail).fcid = 3 (* class-id test *)

type rng = { mutable state : hint }
let rng_next r n =
  r.state <- hmod ((r.state *! lit 75) +! lit 74) (lit 65537);
  hmod (hasr r.state 3) n

let rec build rng depth =
  if depth = 0 then (if eqi (rng_next rng (lit 4)) (lit 0) then Var (rng_next rng (lit 8)) else Num (rng_next rng (lit 10)))
  else
    match to_int (rng_next rng (lit 6)) with
    | 0 | 1 -> let a = build rng (depth - 1) in let b = build rng (depth - 1) in Add (a, b)
    | 2 -> let a = build rng (depth - 1) in let b = build rng (depth - 1) in Mul (a, b)
    | 3 -> Neg (build rng (depth - 1))
    | 4 -> Add (Num (lit 0), build rng (depth - 1))
    | _ -> Mul (build rng (depth - 1), Num (lit 1))

let rec simplify e =
  match e with
  | Add (a, b) -> (
      let a = simplify a in let b = simplify b in
      match (a, b) with
      | Num z, y when eqi z (lit 0) -> y
      | x, Num z when eqi z (lit 0) -> x
      | Num x, Num y -> Num ((x +! y) &! lit 0xFFFF)
      | x, y -> Add (x, y))
  | Mul (a, b) -> (
      let a = simplify a in let b = simplify b in
      match (a, b) with
      | Num z, _ when eqi z (lit 0) -> Num (lit 0)
      | _, Num z when eqi z (lit 0) -> Num (lit 0)
      | Num o, y when eqi o (lit 1) -> y
      | x, Num o when eqi o (lit 1) -> x
      | Num x, Num y -> Num ((x *! y) &! lit 0xFFFF)
      | x, y -> Mul (x, y))
  | Neg a -> (match simplify a with Neg x -> x | Num x -> Num ((lit 0 -! x) &! lit 0xFFFF) | x -> Neg x)
  | _ -> e

let rec eval e env =
  match e with
  | Num v -> v
  | Var i -> arr_get env i (lit 0)
  | Add (a, b) -> (let x = eval a env in let y = eval b env in x +! y) &! lit 0xFFFF
  | Mul (a, b) -> (let x = eval a env in let y = eval b env in x *! y) &! lit 0xFFFF
  | Neg a -> (lit 0 -! eval a env) &! lit 0xFFFF

let rec size = function
  | Num _ | Var _ -> lit 1
  | Add (a, b) | Mul (a, b) -> lit 1 +! size a +! size b
  | Neg a -> lit 1 +! size a

let check v = if eqi (hmod v (lit 7)) (lit 3) then raise (Haxe_exception (Obj.repr { fcid = 3; code = v })) else v

let map a f =
  let r = arr_make () in
  for i = 0 to a.len - 1 do arr_push r (f (Array.unsafe_get a.data i)) done;
  r

let () =
  let iters = 60 and depth = 24 in
  let env = ref (arr_make ()) in
  List.iter (fun x -> arr_push !env (lit x)) [ 1; 4; 7; 10; 13; 16; 19; 22 ];
  let total = ref (lit 0) and failures = ref (lit 0) in
  let shapes = arr_make () in
  List.iter (arr_push shapes) [ new_rect (lit 2) (lit 3); new_square (lit 4); new_rect (lit 5) (lit 1) ];
  let kept = arr_make () in
  for i = 0 to iters - 1 do
    let hi = lit i in
    let rng = { state = hi +! lit 1 } in
    let e = build rng depth in
    let s = simplify e in
    if retain then (arr_push kept e; arr_push kept s);
    let k = hi &! lit 3 in
    env := map !env (fun x -> ((x *! lit 5) +! k) &! lit 0xFF);
    let v = eval s !env in
    (try total := ((!total *! lit 31) +! check v) &! lit 0xFFFFFF
     with Haxe_exception x when is_fail x ->
       failures := !failures +! lit 1;
       total := (!total +! (Obj.obj x : fail).code) &! lit 0xFFFFFF);
    let sh = arr_get shapes (hmod hi (lit 3)) (Obj.magic 0) in
    total := (!total +! size e +! size s +! sh.vt.area sh) &! lit 0xFFFFFF
  done;
  let kept_size = ref (lit 0) in
  for j = 0 to kept.len - 1 do kept_size := (!kept_size +! size (Array.unsafe_get kept.data j)) &! lit 0xFFFFFF done;
  Printf.printf "%s\n%s\n%s\n" (show !total) (show !failures) (show !kept_size)
