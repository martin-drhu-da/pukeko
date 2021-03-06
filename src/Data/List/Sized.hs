{-# LANGUAGE GADTs #-}
{-# LANGUAGE PatternSynonyms #-}
module Data.List.Sized
  ( Nat (..)
  , One
  , List (..)
  , pattern Singleton
  , SomeList (..)
  , fromList
  , withList
  , withNonEmpty
  , match
  , map
  , (++)
  , zip
  , zipWith
  , unzip
  , unzipWith
  , transpose
  , findDelete
  )
where

import Prelude hiding (map, unzip, zip, zipWith, (++))

import Data.Bifunctor (bimap, second)
import Data.List.NonEmpty (NonEmpty (..))

data Nat = Zero | Succ Nat

type One = 'Succ 'Zero

type family (+) (m :: Nat) (n :: Nat) :: Nat

type instance (+) 'Zero     n = n
type instance (+) ('Succ m) n = 'Succ (m+n)

data List (n :: Nat) a where
  Nil  ::                  List  'Zero    a
  Cons :: a -> List n a -> List ('Succ n) a

pattern Singleton :: a -> List One a
pattern Singleton x = Cons x Nil

data SomeList a where
   SomeList :: List n a -> SomeList a

fromList :: forall a. [a] -> SomeList a
fromList = \case
  []   -> SomeList Nil
  x:xs ->
    case fromList xs of
      SomeList ys -> SomeList (Cons x ys)

withList :: [a] -> (forall n. List n a -> b) -> b
withList xs k = case fromList xs of
  SomeList ys -> k ys

withNonEmpty :: NonEmpty a -> (forall n. List ('Succ n) a -> b) -> b
withNonEmpty (x :| xs0) k = withList xs0 $ \xs1 -> k (Cons x xs1)

match :: List n a -> [b] -> Maybe (List n b)
match Nil         []     = Just Nil
match (Cons _ xs) (y:ys) = fmap (Cons y) (match xs ys)
match _           _      = Nothing

map :: (a -> b) -> List n a -> List n b
map = fmap

(++) :: List m a -> List n a -> List (m + n) a
Nil       ++ ys = ys
Cons x xs ++ ys = Cons x (xs ++ ys)

zip :: List n a -> List n b -> List n (a, b)
zip = zipWith (,)

zipWith :: (a -> b -> c) -> List n a -> List n b -> List n c
zipWith _ Nil Nil                 = Nil
zipWith f (Cons x xs) (Cons y ys) = Cons (f x y) (zipWith f xs ys)

unzip :: List n (a, b) -> (List n a, List n b)
unzip = unzipWith id

unzipWith :: (a -> (b, c)) -> List n a -> (List n b, List n c)
unzipWith _ Nil = (Nil, Nil)
unzipWith f (Cons x xs) = bimap (Cons y) (Cons z) (unzipWith f xs)
  where (y, z) = f x


transpose :: List n b -> List m (List n a) -> List n (List m a)
transpose zs Nil           = map (const Nil) zs
transpose zs (Cons xs xss) = zipWith Cons xs (transpose zs xss)

findDelete :: (a -> Maybe b) -> List ('Succ n) a -> Maybe (b, List n a)
findDelete f (Cons x xs)
  | Just y <- f x = Just (y, xs)
  | Nil    <- xs  = Nothing
  | Cons{} <- xs  = second (Cons x) <$> findDelete f xs

deriving instance Functor (List n)
deriving instance Foldable (List n)
deriving instance Traversable (List n)

deriving instance Functor SomeList
deriving instance Foldable SomeList
deriving instance Traversable SomeList
