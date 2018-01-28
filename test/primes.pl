external abort : ∀a. a = "abort"
type Unit =
       | Unit
type Bool =
       | False
       | True
type Pair a b =
       | Pair a b
type Option a =
       | None
       | Some a
type Choice a b =
       | First a
       | Second b
type Dict$Eq a =
       | Dict$Eq (a -> a -> Bool)
(==) : ∀a. Dict$Eq a -> a -> a -> Bool =
  fun @a ->
    fun (dict : Dict$Eq a) ->
      match dict with
      | Dict$Eq @a (==) -> (==)
(!=) : ∀a. Dict$Eq a -> a -> a -> Bool =
  fun @a ->
    fun (dict$Eq$a : Dict$Eq a) (x : a) (y : a) ->
      match (==) @a dict$Eq$a x y with
      | False -> True
      | True -> False
type Dict$Ord a =
       | Dict$Ord (a -> a -> Bool) (a -> a -> Bool) (a -> a -> Bool) (a -> a -> Bool)
(<=) : ∀a. Dict$Ord a -> a -> a -> Bool =
  fun @a ->
    fun (dict : Dict$Ord a) ->
      match dict with
      | Dict$Ord @a (<) (<=) (>=) (>) -> (<=)
type Dict$Monoid m =
       | Dict$Monoid m (m -> m -> m)
append : ∀m. Dict$Monoid m -> m -> m -> m =
  fun @m ->
    fun (dict : Dict$Monoid m) ->
      match dict with
      | Dict$Monoid @m empty append -> append
type Dict$Ring a =
       | Dict$Ring (a -> a) (a -> a -> a) (a -> a -> a) (a -> a -> a)
(+) : ∀a. Dict$Ring a -> a -> a -> a =
  fun @a ->
    fun (dict : Dict$Ring a) ->
      match dict with
      | Dict$Ring @a neg (+) (-) (*) -> (+)
(-) : ∀a. Dict$Ring a -> a -> a -> a =
  fun @a ->
    fun (dict : Dict$Ring a) ->
      match dict with
      | Dict$Ring @a neg (+) (-) (*) -> (-)
type Int
external eq_int : Int -> Int -> Bool = "eq"
dict$Eq$Int : Dict$Eq Int =
  let (==) : Int -> Int -> Bool = eq_int in
  Dict$Eq @Int (==)
external lt_int : Int -> Int -> Bool = "lt"
external le_int : Int -> Int -> Bool = "le"
external ge_int : Int -> Int -> Bool = "ge"
external gt_int : Int -> Int -> Bool = "gt"
dict$Ord$Int : Dict$Ord Int =
  let (<) : Int -> Int -> Bool = lt_int
  and (<=) : Int -> Int -> Bool = le_int
  and (>=) : Int -> Int -> Bool = ge_int
  and (>) : Int -> Int -> Bool = gt_int
  in
  Dict$Ord @Int (<) (<=) (>=) (>)
external neg_int : Int -> Int = "neg"
external add_int : Int -> Int -> Int = "add"
external sub_int : Int -> Int -> Int = "sub"
external mul_int : Int -> Int -> Int = "mul"
dict$Ring$Int : Dict$Ring Int =
  let neg : Int -> Int = neg_int
  and (+) : Int -> Int -> Int = add_int
  and (-) : Int -> Int -> Int = sub_int
  and (*) : Int -> Int -> Int = mul_int
  in
  Dict$Ring @Int neg (+) (-) (*)
external (%) : Int -> Int -> Int = "mod"
type Dict$Foldable t =
       | Dict$Foldable (∀a b. (a -> b -> b) -> b -> t a -> b) (∀a b. (b -> a -> b) -> b -> t a -> b)
foldr : ∀t. Dict$Foldable t -> (∀a b. (a -> b -> b) -> b -> t a -> b) =
  fun @t ->
    fun (dict : Dict$Foldable t) ->
      match dict with
      | Dict$Foldable @t foldr foldl -> foldr
foldl : ∀t. Dict$Foldable t -> (∀a b. (b -> a -> b) -> b -> t a -> b) =
  fun @t ->
    fun (dict : Dict$Foldable t) ->
      match dict with
      | Dict$Foldable @t foldr foldl -> foldl
type Dict$Functor f =
       | Dict$Functor (∀a b. (a -> b) -> f a -> f b)
type List a =
       | Nil
       | Cons a (List a)
dict$Monoid$List$ll1 : ∀a. List a -> List a -> List a =
  fun @a ->
    fun (xs : List a) (ys : List a) ->
      foldr @List dict$Foldable$List @a @(List a) (Cons @a) ys xs
dict$Monoid$List : ∀a. Dict$Monoid (List a) =
  fun @a ->
    let empty : List a = Nil @a
    and append : List a -> List a -> List a = dict$Monoid$List$ll1 @a
    in
    Dict$Monoid @(List a) empty append
dict$Foldable$List$ll1 : ∀a b. (a -> b -> b) -> b -> List a -> b =
  fun @a @b ->
    fun (f : a -> b -> b) (y0 : b) (xs : List a) ->
      match xs with
      | Nil @a -> y0
      | Cons @a x xs ->
        f x (foldr @List dict$Foldable$List @a @b f y0 xs)
dict$Foldable$List$ll2 : ∀a b. (b -> a -> b) -> b -> List a -> b =
  fun @a @b ->
    fun (f : b -> a -> b) (y0 : b) (xs : List a) ->
      match xs with
      | Nil @a -> y0
      | Cons @a x xs ->
        foldl @List dict$Foldable$List @a @b f (f y0 x) xs
dict$Foldable$List : Dict$Foldable List =
  let foldr : ∀a b. (a -> b -> b) -> b -> List a -> b =
        fun @a @b -> dict$Foldable$List$ll1 @a @b
  and foldl : ∀a b. (b -> a -> b) -> b -> List a -> b =
        fun @a @b -> dict$Foldable$List$ll2 @a @b
  in
  Dict$Foldable @List foldr foldl
nth_exn : ∀a. List a -> Int -> a =
  fun @a ->
    fun (xs : List a) (n : Int) ->
      match xs with
      | Nil @a -> abort @a
      | Cons @a x xs ->
        match (<=) @Int dict$Ord$Int n 0 with
        | False -> nth_exn @a xs ((-) @Int dict$Ring$Int n 1)
        | True -> x
type Dict$Monad m =
       | Dict$Monad (∀a. a -> m a) (∀a b. m a -> (a -> m b) -> m b)
(>>=) : ∀m. Dict$Monad m -> (∀a b. m a -> (a -> m b) -> m b) =
  fun @m ->
    fun (dict : Dict$Monad m) ->
      match dict with
      | Dict$Monad @m pure (>>=) -> (>>=)
type IO a
external pure_io : ∀a. a -> IO a = "return"
external bind_io : ∀a b. IO a -> (a -> IO b) -> IO b = "bind"
dict$Monad$IO : Dict$Monad IO =
  let pure : ∀a. a -> IO a = fun @a -> pure_io @a
  and (>>=) : ∀a b. IO a -> (a -> IO b) -> IO b =
        fun @a @b -> bind_io @a @b
  in
  Dict$Monad @IO pure (>>=)
external print : Int -> IO Unit = "print"
external input : IO Int = "input"
repeat : ∀a. List a -> List a =
  fun @a ->
    fun (xs : List a) ->
      let rec ys : List a = append @(List a) (dict$Monoid$List @a) xs ys
      in
      ys
psums$ll1 : ∀_9. (∀_9. Dict$Ring _9 -> _9 -> List _9 -> List _9) -> Dict$Ring _9 -> _9 -> List _9 -> List _9 =
  fun @_9 ->
    fun (psums0 : ∀_9. Dict$Ring _9 -> _9 -> List _9 -> List _9) (dict$Ring$_9 : Dict$Ring _9) (n : _9) (xs : List _9) ->
      match xs with
      | Nil @_9 -> Nil @_9
      | Cons @_9 x xs ->
        let y : _9 = (+) @_9 dict$Ring$_9 x n in
        Cons @_9 y (psums0 @_9 dict$Ring$_9 y xs)
psums : List Int -> List Int =
  let rec psums0 : ∀_9. Dict$Ring _9 -> _9 -> List _9 -> List _9 =
            fun @_9 -> psums$ll1 @_9 psums0
  in
  psums0 @Int dict$Ring$Int 0
filter$ll1 : ∀a. (a -> Bool) -> (List a -> List a) -> List a -> List a =
  fun @a ->
    fun (p : a -> Bool) (filter_p : List a -> List a) (xs : List a) ->
      match xs with
      | Nil @a -> Nil @a
      | Cons @a x xs ->
        let ys : List a = filter_p xs in
        match p x with
        | False -> ys
        | True -> Cons @a x ys
filter : ∀a. (a -> Bool) -> List a -> List a =
  fun @a ->
    fun (p : a -> Bool) ->
      let rec filter_p : List a -> List a = filter$ll1 @a p filter_p in
      filter_p
sieve$ll1 : Int -> Int -> Bool =
  fun (p : Int) (k : Int) -> (!=) @Int dict$Eq$Int ((%) k p) 0
sieve : List Int -> List Int =
  fun (ks : List Int) ->
    match ks with
    | Nil @Int -> abort @(List Int)
    | Cons @Int p ks ->
      Cons @Int p (sieve (filter @Int (sieve$ll1 p) ks))
primes : List Int =
  Cons @Int 2 (Cons @Int 3 (sieve (psums (Cons @Int 5 (repeat @Int (Cons @Int 2 (Cons @Int 4 (Nil @Int))))))))
main$ll1 : Int -> IO Unit =
  fun (n : Int) -> print (nth_exn @Int primes n)
main : IO Unit = (>>=) @IO dict$Monad$IO @Int @Unit input main$ll1
