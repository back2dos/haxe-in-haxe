type hint = int
let[@inline] wrap x = (x lsl 31) asr 31
let[@inline] ( +! ) a b = wrap (a + b)
let[@inline] ( -! ) a b = wrap (a - b)
let[@inline] ( *! ) a b = wrap (a * b)
let[@inline] ( &! ) a b = a land b
let[@inline] hmod a b = if b = 0 then 0 else a mod b
let[@inline] hasr a n = a asr n
let[@inline] lit (x : int) : hint = x
let[@inline] eqi (a : hint) b = a = b
let[@inline] to_int (a : hint) = a
let show = string_of_int
