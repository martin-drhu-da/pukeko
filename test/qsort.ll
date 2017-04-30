external (-) = "sub"
external (<) = "lt"
external (<=) = "le"
let foldr f y0 xs =
      match xs with
      | Nil -> y0
      | Cons x xs -> f x (foldr f y0 xs)
let partition$1 p part_p xs =
      match xs with
      | Nil -> Pair Nil Nil
      | Cons x xs ->
        match part_p xs with
        | Pair ys zs ->
          if p x then Pair (Cons x ys) zs else Pair ys (Cons x zs)
let partition p xs =
      let rec part_p = partition$1 p part_p in
      part_p xs
let append xs ys =
      match xs with
      | Nil -> ys
      | Cons x xs -> Cons x (append xs ys)
let replicate n x =
      if (<=) n 0 then Nil else Cons x (replicate ((-) n 1) x)
external return = "return"
external print = "print"
external input = "input"
external (>>=) = "bind"
let (;1) m2 _ = m2
let (;) m1 m2 = (>>=) m1 ((;1) m2)
let sequence_io$2 x xs = return (Cons x xs)
let sequence_io$1 ms x = (>>=) (sequence_io ms) (sequence_io$2 x)
let sequence_io ms =
      match ms with
      | Nil -> return Nil
      | Cons m ms -> (>>=) m (sequence_io$1 ms)
let iter_io$1 f x m = (;) (f x) m
let iter_io f = foldr (iter_io$1 f) (return Unit)
let qsort$1 x y = (<) y x
let qsort xs =
      match xs with
      | Nil -> Nil
      | Cons x xs ->
        match partition (qsort$1 x) xs with
        | Pair ys zs -> append (qsort ys) (Cons x (qsort zs))
let main$2 xs = iter_io print (qsort xs)
let main$1 n = (>>=) (sequence_io (replicate n input)) main$2
let main = (>>=) input main$1
