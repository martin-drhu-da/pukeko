-- | Perform link compression for functions which are just aliases. For instance,
--
-- > f = Cons 1 Nil
-- > g = f
-- > h = g
-- > k = append g h
--
-- is transformed into
--
-- > f = Cons 1 Nil
-- > g = f
-- > h = f
-- > k = append f f
--
-- Notice that @g@ and @h@ are dead code now.
module Pukeko.MiddleEnd.AliasInliner where

import Pukeko.Prelude

import           Control.Monad.ST
import qualified Data.Map          as Map
import qualified Data.Set          as Set
import qualified Data.UnionFind.ST as UF

import           Pukeko.AST.SuperCore
import           Pukeko.AST.Expr.Optics
import qualified Pukeko.AST.Identifier as Id

-- | Follow all chains of links in a module and adjust all call sites accordingly.
inlineModule :: Module -> Module
inlineModule = over mod2supcs inlineSupCDecls

-- | Follow all chains of links in a group of declarations and adjust all call
-- sites within this group.
inlineSupCDecls :: Traversable t => t (FuncDecl 'SupC) -> t (FuncDecl 'SupC)
inlineSupCDecls decls0 =
  let ls = mapMaybe isLink (toList decls0)
      uf = unionFind ls
  in  over (traverse . func2expr . expr2atom . _AVal)
        (\x -> Map.findWithDefault x x uf) decls0

-- | Determine if a declaration is a link, i.e., of the form
--
-- > f = g
--
-- If it is, return the pair @(f, g)@.
isLink :: FuncDecl 'SupC -> Maybe (Id.EVar, Id.EVar)
isLink = \case
  SupCDecl (unlctd -> z) _t vs xs (EVal x)
    | null vs && null xs -> Just (z, x)
  _                      -> Nothing

-- | Run Tarjan's union find algorithm on a list of equivalences and return a
-- map from each element to its representative.
unionFind :: Ord a => [(a, a)] -> Map a a
unionFind xys = runST $ do
  let xs = foldMap (\(x, y) -> Set.singleton x <> Set.singleton y) xys
  ps <- sequence (Map.fromSet UF.fresh xs)
  for_ xys $ \(x, y) -> UF.union (ps Map.! x) (ps Map.! y)
  for ps $ \p -> UF.repr p >>= UF.descriptor
