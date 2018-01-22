type Unit =
       | Unit
type Bool =
       | False
       | True
type Pair a b =
       | Pair a b
type Dict$Eq a =
       | Dict$Eq (a -> a -> Bool)
type Dict$Ord a =
       | Dict$Ord (a -> a -> Bool) (a -> a -> Bool) (a -> a -> Bool) (a -> a -> Bool)
let (<) : ∀a. Dict$Ord a -> a -> a -> Bool =
      fun @a ->
        fun (dict : Dict$Ord a) ->
          match dict with
          | Dict$Ord @a (<) (<=) (>=) (>) -> (<)
let (<=) : ∀a. Dict$Ord a -> a -> a -> Bool =
      fun @a ->
        fun (dict : Dict$Ord a) ->
          match dict with
          | Dict$Ord @a (<) (<=) (>=) (>) -> (<=)
type Dict$Monoid m =
       | Dict$Monoid m (m -> m -> m)
type Dict$Ring a =
       | Dict$Ring (a -> a) (a -> a -> a) (a -> a -> a) (a -> a -> a)
let (-) : ∀a. Dict$Ring a -> a -> a -> a =
      fun @a ->
        fun (dict : Dict$Ring a) ->
          match dict with
          | Dict$Ring @a neg (+) (-) (*) -> (-)
type Int
external lt_int : Int -> Int -> Bool = "lt"
external le_int : Int -> Int -> Bool = "le"
external ge_int : Int -> Int -> Bool = "ge"
external gt_int : Int -> Int -> Bool = "gt"
let dict$Ord$Int : Dict$Ord Int =
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
let dict$Ring$Int : Dict$Ring Int =
      let neg : Int -> Int = neg_int
      and (+) : Int -> Int -> Int = add_int
      and (-) : Int -> Int -> Int = sub_int
      and (*) : Int -> Int -> Int = mul_int
      in
      Dict$Ring @Int neg (+) (-) (*)
type Dict$Foldable t =
       | Dict$Foldable (∀a b. (a -> b -> b) -> b -> t a -> b) (∀a b. (b -> a -> b) -> b -> t a -> b)
let foldr : ∀t. Dict$Foldable t -> (∀a b. (a -> b -> b) -> b -> t a -> b) =
      fun @t ->
        fun (dict : Dict$Foldable t) ->
          match dict with
          | Dict$Foldable @t foldr foldl -> foldr
let foldl : ∀t. Dict$Foldable t -> (∀a b. (b -> a -> b) -> b -> t a -> b) =
      fun @t ->
        fun (dict : Dict$Foldable t) ->
          match dict with
          | Dict$Foldable @t foldr foldl -> foldl
type Dict$Functor f =
       | Dict$Functor (∀a b. (a -> b) -> f a -> f b)
type List a =
       | Nil
       | Cons a (List a)
let dict$Foldable$List$ll1 : ∀a b. (a -> b -> b) -> b -> List a -> b =
      fun @a @b ->
        fun (f : a -> b -> b) (y0 : b) (xs : List a) ->
          match xs with
          | Nil @a -> y0
          | Cons @a x xs ->
            f x (foldr @List dict$Foldable$List @a @b f y0 xs)
let dict$Foldable$List$ll2 : ∀a b. (b -> a -> b) -> b -> List a -> b =
      fun @a @b ->
        fun (f : b -> a -> b) (y0 : b) (xs : List a) ->
          match xs with
          | Nil @a -> y0
          | Cons @a x xs ->
            foldl @List dict$Foldable$List @a @b f (f y0 x) xs
let dict$Foldable$List : Dict$Foldable List =
      let foldr : ∀a b. (a -> b -> b) -> b -> List a -> b =
            fun @a @b -> dict$Foldable$List$ll1 @a @b
      and foldl : ∀a b. (b -> a -> b) -> b -> List a -> b =
            fun @a @b -> dict$Foldable$List$ll2 @a @b
      in
      Dict$Foldable @List foldr foldl
let to_list : ∀a t. Dict$Foldable t -> t a -> List a =
      fun @a @t ->
        fun (dict$Foldable$t : Dict$Foldable t) ->
          foldr @t dict$Foldable$t @a @(List a) (Cons @a) (Nil @a)
let replicate : ∀a. Int -> a -> List a =
      fun @a ->
        fun (n : Int) (x : a) ->
          match (<=) @Int dict$Ord$Int n 0 with
          | False -> Cons @a x (replicate @a ((-) @Int dict$Ring$Int n 1) x)
          | True -> Nil @a
type Dict$Monad m =
       | Dict$Monad (∀a. a -> m a) (∀a b. m a -> (a -> m b) -> m b)
let pure : ∀m. Dict$Monad m -> (∀a. a -> m a) =
      fun @m ->
        fun (dict : Dict$Monad m) ->
          match dict with
          | Dict$Monad @m pure (>>=) -> pure
let (>>=) : ∀m. Dict$Monad m -> (∀a b. m a -> (a -> m b) -> m b) =
      fun @m ->
        fun (dict : Dict$Monad m) ->
          match dict with
          | Dict$Monad @m pure (>>=) -> (>>=)
let (;ll1) : ∀a m. m a -> Unit -> m a =
      fun @a @m -> fun (m2 : m a) (x : Unit) -> m2
let (;) : ∀a m. Dict$Monad m -> m Unit -> m a -> m a =
      fun @a @m ->
        fun (dict$Monad$m : Dict$Monad m) (m1 : m Unit) (m2 : m a) ->
          (>>=) @m dict$Monad$m @Unit @a m1 ((;ll1) @a @m m2)
let sequence$ll1 : ∀a m. Dict$Monad m -> a -> List a -> m (List a) =
      fun @a @m ->
        fun (dict$Monad$m : Dict$Monad m) (x : a) (xs : List a) ->
          pure @m dict$Monad$m @(List a) (Cons @a x xs)
let sequence$ll2 : ∀a m. Dict$Monad m -> List (m a) -> a -> m (List a) =
      fun @a @m ->
        fun (dict$Monad$m : Dict$Monad m) (ms : List (m a)) (x : a) ->
          (>>=) @m dict$Monad$m @(List a) @(List a) (sequence @a @m dict$Monad$m ms) (sequence$ll1 @a @m dict$Monad$m x)
let sequence : ∀a m. Dict$Monad m -> List (m a) -> m (List a) =
      fun @a @m ->
        fun (dict$Monad$m : Dict$Monad m) (ms : List (m a)) ->
          match ms with
          | Nil @(m a) -> pure @m dict$Monad$m @(List a) (Nil @a)
          | Cons @(m a) m ms ->
            (>>=) @m dict$Monad$m @a @(List a) m (sequence$ll2 @a @m dict$Monad$m ms)
let traverse_$ll1 : ∀a m. Dict$Monad m -> (a -> m Unit) -> a -> m Unit -> m Unit =
      fun @a @m ->
        fun (dict$Monad$m : Dict$Monad m) (f : a -> m Unit) (x : a) (m : m Unit) ->
          (;) @Unit @m dict$Monad$m (f x) m
let traverse_ : ∀a m t. Dict$Monad m -> Dict$Foldable t -> (a -> m Unit) -> t a -> m Unit =
      fun @a @m @t ->
        fun (dict$Monad$m : Dict$Monad m) (dict$Foldable$t : Dict$Foldable t) (f : a -> m Unit) ->
          foldr @t dict$Foldable$t @a @(m Unit) (traverse_$ll1 @a @m dict$Monad$m f) (pure @m dict$Monad$m @Unit Unit)
type IO a
external pure_io : ∀a. a -> IO a = "return"
external bind_io : ∀a b. IO a -> (a -> IO b) -> IO b = "bind"
let dict$Monad$IO : Dict$Monad IO =
      let pure : ∀a. a -> IO a = fun @a -> pure_io @a
      and (>>=) : ∀a b. IO a -> (a -> IO b) -> IO b =
            fun @a @b -> bind_io @a @b
      in
      Dict$Monad @IO pure (>>=)
external print : Int -> IO Unit = "print"
external input : IO Int = "input"
type BinTree a =
       | Leaf
       | Branch (BinTree a) a (BinTree a)
let dict$Foldable$BinTree$ll1 : ∀a b. (a -> b -> b) -> b -> BinTree a -> b =
      fun @a @b ->
        fun (f : a -> b -> b) (y0 : b) (t : BinTree a) ->
          match t with
          | Leaf @a -> y0
          | Branch @a l x r ->
            foldr @BinTree dict$Foldable$BinTree @a @b f (f x (foldr @BinTree dict$Foldable$BinTree @a @b f y0 r)) l
let dict$Foldable$BinTree$ll2 : ∀a b. (b -> a -> b) -> b -> BinTree a -> b =
      fun @a @b ->
        fun (f : b -> a -> b) (y0 : b) (t : BinTree a) ->
          match t with
          | Leaf @a -> y0
          | Branch @a l x r ->
            foldl @BinTree dict$Foldable$BinTree @a @b f (f (foldl @BinTree dict$Foldable$BinTree @a @b f y0 l) x) r
let dict$Foldable$BinTree : Dict$Foldable BinTree =
      let foldr : ∀a b. (a -> b -> b) -> b -> BinTree a -> b =
            fun @a @b -> dict$Foldable$BinTree$ll1 @a @b
      and foldl : ∀a b. (b -> a -> b) -> b -> BinTree a -> b =
            fun @a @b -> dict$Foldable$BinTree$ll2 @a @b
      in
      Dict$Foldable @BinTree foldr foldl
type Bag a =
       | Bag (BinTree a)
let dict$Foldable$Bag$ll1 : ∀a b. (a -> b -> b) -> b -> Bag a -> b =
      fun @a @b ->
        fun (f : a -> b -> b) (y0 : b) (s : Bag a) ->
          match s with
          | Bag @a t -> foldr @BinTree dict$Foldable$BinTree @a @b f y0 t
let dict$Foldable$Bag$ll2 : ∀a b. (b -> a -> b) -> b -> Bag a -> b =
      fun @a @b ->
        fun (f : b -> a -> b) (y0 : b) (s : Bag a) ->
          match s with
          | Bag @a t -> foldl @BinTree dict$Foldable$BinTree @a @b f y0 t
let dict$Foldable$Bag : Dict$Foldable Bag =
      let foldr : ∀a b. (a -> b -> b) -> b -> Bag a -> b =
            fun @a @b -> dict$Foldable$Bag$ll1 @a @b
      and foldl : ∀a b. (b -> a -> b) -> b -> Bag a -> b =
            fun @a @b -> dict$Foldable$Bag$ll2 @a @b
      in
      Dict$Foldable @Bag foldr foldl
let bag_empty : ∀a. Bag a = fun @a -> Bag @a (Leaf @a)
let bag_insert$ll1 : ∀_12. (∀_12. Dict$Ord _12 -> _12 -> BinTree _12 -> BinTree _12) -> Dict$Ord _12 -> _12 -> BinTree _12 -> BinTree _12 =
      fun @_12 ->
        fun (insert : ∀_12. Dict$Ord _12 -> _12 -> BinTree _12 -> BinTree _12) (dict$Ord$_12 : Dict$Ord _12) (x : _12) (t : BinTree _12) ->
          match t with
          | Leaf @_12 -> Branch @_12 (Leaf @_12) x (Leaf @_12)
          | Branch @_12 l y r ->
            match (<) @_12 dict$Ord$_12 x y with
            | False -> Branch @_12 l y (insert @_12 dict$Ord$_12 x r)
            | True -> Branch @_12 (insert @_12 dict$Ord$_12 x l) y r
let bag_insert : ∀a. Dict$Ord a -> a -> Bag a -> Bag a =
      fun @a ->
        fun (dict$Ord$a : Dict$Ord a) (x : a) (s : Bag a) ->
          let rec insert : ∀_12. Dict$Ord _12 -> _12 -> BinTree _12 -> BinTree _12 =
                    fun @_12 -> bag_insert$ll1 @_12 insert
          in
          match s with
          | Bag @a t -> Bag @a (insert @a dict$Ord$a x t)
let tsort$ll1 : Bag Int -> Int -> Bag Int =
      fun (s : Bag Int) (x : Int) -> bag_insert @Int dict$Ord$Int x s
let tsort : List Int -> List Int =
      fun (xs : List Int) ->
        to_list @Int @Bag dict$Foldable$Bag (foldl @List dict$Foldable$List @Int @(Bag Int) tsort$ll1 (bag_empty @Int) xs)
let main$ll1 : List Int -> IO Unit =
      fun (xs : List Int) ->
        traverse_ @Int @IO @List dict$Monad$IO dict$Foldable$List print (tsort xs)
let main$ll2 : Int -> IO Unit =
      fun (n : Int) ->
        (>>=) @IO dict$Monad$IO @(List Int) @Unit (sequence @Int @IO dict$Monad$IO (replicate @(IO Int) n input)) main$ll1
let main : IO Unit =
      (>>=) @IO dict$Monad$IO @Int @Unit input main$ll2
