{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}
module Pukeko.Language.AST.Std
  ( GenModuleInfo (..)
  , ModuleInfo
  , Module (..)
  , TopLevel (..)
  , GenDefn (..)
  , Defn
  , Expr (..)
  , Case (..)
  , Altn (..)
  , GenPatn (..)
  , Patn
  , Bind (..)

  , abstract
  , (//)
  , bindName
  , patnToBind

  , module2tops
  , bind2evar
  , defn2dcon
  , patn2bind
  , case2rhs
  , altn2rhs

  , retagDefn
  , retagExpr

  , _Wild
  , _Name

  , prettyBinds

  , Pos
  , module Pukeko.Language.AST.Scope
  )
  where

import Control.Lens
import Data.Vector.Sized (Vector)
import Data.Foldable

import           Pukeko.Pos
import           Pukeko.Pretty
import qualified Pukeko.Language.Operator as Op
import qualified Pukeko.Language.Ident    as Id
import qualified Pukeko.Language.Type     as Ty
import           Pukeko.Language.AST.Classes
import           Pukeko.Language.AST.Stage
import           Pukeko.Language.AST.Scope
import           Pukeko.Language.AST.ModuleInfo
import qualified Pukeko.Language.AST.ConDecl as Con

type ModuleInfo st = GenModuleInfo (HasCons st) (HasVals st)

data Module st = MkModule
  { _moduleInfo :: GenModuleInfo (HasCons st) (HasVals st)
  , _moduleTops :: [TopLevel st]
  }

data TopLevel st
  = HasTypDef st ~ 'True => TypDef Pos [Con.TConDecl]
  | HasVal    st ~ 'True => Val    Pos Id.EVar (Ty.Type Ty.Closed)
  | forall n.
    HasTopLet st ~ 'True => TopLet Pos (Vector n (Defn st Id.EVar))
  | forall n.
    HasTopLet st ~ 'True => TopRec Pos (Vector n (Defn st (FinScope n Id.EVar)))
  | HasDef    st ~ 'True => Def    Pos Id.EVar (Expr st Id.EVar)
  | forall n.
    HasSupCom st ~ 'True => SupCom Pos Id.EVar (Vector n Bind) (Expr st (FinScope n Id.EVar))
  | HasSupCom st ~ 'True => Caf    Pos Id.EVar (Expr st Id.EVar)
  |                         Asm    Pos Id.EVar String

data GenDefn expr v = MkDefn
  { _defnPos :: Pos
  , _defnLhs :: Id.EVar
  , _defnRhs :: expr v
  }
  deriving (Functor, Foldable, Traversable)

type Defn st = GenDefn (Expr st)

data Expr st v
  =           Var Pos v
  |           Con Pos Id.DCon
  |           Num Pos Int
  |           App Pos (Expr st v) [Expr st v]
  | forall n. HasLam st ~ 'True => Lam Pos (Vector n Bind)   (Expr st (FinScope n v))
  | forall n. Let Pos (Vector n (Defn st v))              (Expr st (FinScope n v))
  | forall n. Rec Pos (Vector n (Defn st (FinScope n v))) (Expr st (FinScope n v))
  | HasMat st ~ 'False => Cas Pos (Expr st v) [Case st v]
  | HasMat st ~ 'True => Mat Pos (Expr st v) [Altn st v]

data Case st v = forall n. MkCase
  { _casePos   :: Pos
  , _caseCon   :: Id.DCon
  , _caseBinds :: Vector n Bind
  , _caseRhs   :: Expr st (FinScope n v)
  }

data Altn st v = MkAltn
  { _altnPos  :: Pos
  , _altnPatn :: Patn st
  , _altnRhs  :: Expr st (Scope Id.EVar v)
  }

-- TODO: Remove useless parameter.
data GenPatn dcon
  = Bind     Bind
  | Dest Pos dcon [GenPatn dcon]

type Patn st = GenPatn Id.DCon

data Bind
  = Wild Pos
  | Name Pos Id.EVar


-- * Derived optics
makeLenses ''GenDefn
makePrisms ''Bind


-- * Abstraction and substition

-- | Abstract all variables which are mapped to @Just@.
abstract :: (v -> Maybe (i, Id.EVar)) -> Expr st v -> Expr st (Scope i v)
abstract f = fmap (match f)
  where
    match :: (v -> Maybe (i, Id.EVar)) -> v -> Scope i v
    match f v = maybe (Free v) (uncurry mkBound) (f v)

-- | Replace subexpressions.
(//) :: Expr st v -> (Pos -> v -> Expr st w) -> Expr st w
expr // f = case expr of
  Var w x       -> f w x
  Con w c       -> Con w c
  Num w n       -> Num w n
  App w t  us   -> App w (t // f) (map (// f) us)
  -- If  w t  u  v -> If  w (t // f) (u // f) (v // f)
  Cas w t  cs   -> Cas w (t // f) (map (over' case2rhs (/// f)) cs)
  Lam w ps t    -> Lam w ps (t /// f)
  Let w ds t    -> Let w (over (traverse . rhs1) (//  f) ds) (t /// f)
  Rec w ds t    -> Rec w (over (traverse . rhs1) (/// f) ds) (t /// f)
  Mat w t  as   -> Mat w (t // f) (map (over' altn2rhs (/// f)) as)

(///) :: Expr st (Scope i v) -> (Pos -> v -> Expr st w) -> Expr st (Scope i w)
t /// f = t // (\w x -> dist w (fmap (f w) x))

dist :: Pos -> Scope i (Expr st v) -> Expr st (Scope i v)
dist w (Bound i x) = Var w (Bound i x)
dist _ (Free t)    = fmap Free t

-- * Getters
bindName :: Bind -> Maybe Id.EVar
bindName = \case
  Wild _   -> Nothing
  Name _ x -> Just x

patnToBind :: GenPatn dcon -> Maybe Bind
patnToBind = \case
  Bind b -> Just b
  Dest{} -> Nothing

-- * Traversals
module2tops ::
  SameModuleInfo st1 st2 =>
  Lens (Module st1) (Module st2) [TopLevel st1] [TopLevel st2]
module2tops f (MkModule info tops) = MkModule info <$> f tops

-- TODO: Make this indexed if possible.
bind2evar :: Traversal' Bind Id.EVar
bind2evar f = \case
  Wild w   -> pure (Wild w)
  Name w x -> Name w <$> f x

-- * Deep traversals
type ExprConTraversal t =
  forall st1 st2 v. SameNodes st1 st2 =>
  IndexedTraversal Pos (t st1 v) (t st2 v) Id.DCon Id.DCon

defn2dcon :: ExprConTraversal Defn
defn2dcon = rhs2 . expr2dcon

expr2dcon :: ExprConTraversal Expr
expr2dcon f = \case
  Var w x       -> pure $ Var w x
  Con w c       -> Con w <$> indexed f w c
  Num w n       -> pure $ Num w n
  App w t  us   -> App w <$> expr2dcon f t <*> (traverse . expr2dcon) f us
  Cas w t  cs   -> Cas w <$> expr2dcon f t <*> (traverse . case2dcon) f cs
  Lam w bs t    -> Lam w bs <$> expr2dcon f t
  Let w ds t    -> Let w <$> (traverse . defn2dcon) f ds <*> expr2dcon f t
  Rec w ds t    -> Rec w <$> (traverse . defn2dcon) f ds <*> expr2dcon f t
  Mat w t  as   -> Mat w <$> expr2dcon f t <*> (traverse . altn2dcon) f as

case2dcon :: ExprConTraversal Case
case2dcon f (MkCase w c bs t) =
  MkCase w <$> indexed f w c <*> pure bs <*> expr2dcon f t

altn2dcon :: ExprConTraversal Altn
altn2dcon f (MkAltn w p t) =
  MkAltn w <$> patn2dcon f p <*> expr2dcon f t

patn2dcon ::
  IndexedTraversal Pos (GenPatn con1) (GenPatn con2) con1 con2
patn2dcon f = \case
  Bind   b    -> pure $ Bind b
  Dest w c ps -> Dest w <$> indexed f w c <*> (traverse . patn2dcon) f ps

patn2bind :: IndexedTraversal' Pos (GenPatn dcon) Bind
patn2bind f = \case
  Bind   b    -> Bind <$> indexed f (b^.pos) b
  Dest w c ps -> Dest w c <$> (traverse . patn2bind) f ps

-- * Highly polymorphic lenses
over' ::
  ((forall i. g (s i v1) -> Identity (g (s i v2))) -> f v1 -> Identity (f v2)) ->
   (forall i. g (s i v1) ->           g (s i v2))  -> f v1 ->           f v2
over' l f = runIdentity . l (Identity . f)

case2rhs
  :: (Functor f)
  => (forall i. IsVarLevel i => Expr st1 (Scope i v1) -> f (Expr st2 (Scope i v2)))
  -> Case st1 v1 -> f (Case st2 v2)
case2rhs f (MkCase w c bs t) = MkCase w c bs <$> f t

altn2rhs
  :: (Functor f)
  => (forall i. IsVarLevel i => Expr st1 (Scope i v1) -> f (Expr st2 (Scope i v2)))
  -> Altn st1 v1 -> f (Altn st2 v2)
altn2rhs f (MkAltn w p t) = MkAltn w p <$> f t

-- * Retagging
retagDefn ::
  (SameNodes st1 st2) =>
  Defn st1 v -> Defn st2 v
retagDefn = over defn2dcon id

retagExpr ::
  forall st1 st2 v. (SameNodes st1 st2) =>
  Expr st1 v -> Expr st2 v
retagExpr = over expr2dcon id

-- * Manual instances
instance TraversableWithIndex Pos expr => FunctorWithIndex     Pos (GenDefn expr) where
instance TraversableWithIndex Pos expr => FoldableWithIndex    Pos (GenDefn expr) where
instance TraversableWithIndex Pos expr => TraversableWithIndex Pos (GenDefn expr) where
  itraverse f (MkDefn w x e) = MkDefn w x <$> itraverse f e

instance FunctorWithIndex     Pos (Expr st) where
instance FoldableWithIndex    Pos (Expr st) where
instance TraversableWithIndex Pos (Expr st) where
  itraverse f = \case
    Var w x -> Var w <$> f w x
    Con w c -> pure (Con w c)
    Num w n -> pure (Num w n)
    App w e0 es -> App w <$> itraverse f e0 <*> (traverse . itraverse) f es
    Lam w bs e0 -> Lam w bs <$> itraverse (traverse . f) e0
    Let w ds e0 ->
      Let w <$> (traverse . itraverse) f ds <*> itraverse (traverse . f) e0
    Rec w ds e0 ->
      Rec w
      <$> (traverse . itraverse) (traverse . f) ds
      <*> itraverse (traverse . f) e0
    Cas w e0 cs -> Cas w <$> itraverse f e0 <*> (traverse . itraverse) f cs
    Mat w e0 as -> Mat w <$> itraverse f e0 <*> (traverse . itraverse) f as

instance FunctorWithIndex     Pos (Case st) where
instance FoldableWithIndex    Pos (Case st) where
instance TraversableWithIndex Pos (Case st) where
  itraverse f (MkCase w c bs e0) = MkCase w c bs <$> itraverse (traverse . f) e0

instance FunctorWithIndex     Pos (Altn st) where
instance FoldableWithIndex    Pos (Altn st) where
instance TraversableWithIndex Pos (Altn st) where
  itraverse f (MkAltn w p e0) = MkAltn w p <$> itraverse (traverse . f) e0



instance HasPos (GenDefn expr v) where
  pos = defnPos

instance HasLhs (GenDefn expr v) where
  type Lhs (GenDefn expr v) = Id.EVar
  lhs = defnLhs

instance HasRhs (GenDefn expr v) where
  type Rhs (GenDefn expr v) = expr v
  rhs = defnRhs

instance HasRhs1 (GenDefn expr) where
  type Rhs1 (GenDefn expr) = expr
  rhs1 = defnRhs

instance HasRhs2 GenDefn where
  rhs2 = defnRhs

instance HasPos (Expr std v) where
  pos f = \case
    Var w x       -> fmap (\w' -> Var w' x      ) (f w)
    Con w c       -> fmap (\w' -> Con w' c      ) (f w)
    Num w n       -> fmap (\w' -> Num w' n      ) (f w)
    App w t  us   -> fmap (\w' -> App w' t  us  ) (f w)
    Cas w t  cs   -> fmap (\w' -> Cas w' t  cs  ) (f w)
    Lam w ps t    -> fmap (\w' -> Lam w' ps t   ) (f w)
    Let w ds t    -> fmap (\w' -> Let w' ds t   ) (f w)
    Rec w ds t    -> fmap (\w' -> Rec w' ds t   ) (f w)
    Mat w ts as   -> fmap (\w' -> Mat w' ts as  ) (f w)

instance HasPos Bind where
  pos f = \case
    Wild w   -> fmap         Wild       (f w)
    Name w x -> fmap (\w' -> Name w' x) (f w)

-- * Pretty printing
instance (HasTypDef st ~ 'False) => Pretty (TopLevel st) where
  pPrintPrec _ _ = \case
    Val _ x t ->
      "val" <+> pretty x <+> colon <+> pretty t
    TopLet _ ds -> prettyDefns False ds
    TopRec _ ds -> prettyDefns True  ds
    Def    w x e -> "let" <+> pretty (MkDefn w x e)
    SupCom _ x bs e ->
      "let" <+> hang (pretty x <+> prettyBinds bs <+> equals) 2 (pretty e)
    Caf _ x t ->
      "let" <+> hang (pretty x <+> equals) 2 (pretty t)
    Asm _ x s ->
      hsep ["external", pretty x, equals, text (show s)]

instance (IsVar v) => Pretty (Defn st v) where
  pPrintPrec lvl _ (MkDefn _ x t) =
    hang (pPrintPrec lvl 0 x <+> equals) 2 (pPrintPrec lvl 0 t)

prettyDefns :: (IsVar v) => Bool -> Vector n (Defn st v) -> Doc
prettyDefns isrec ds = case toList ds of
    [] -> mempty
    d0:ds -> vcat ((let_ <+> pretty d0) : map (\d -> "and" <+> pretty d) ds)
    where
      let_ | isrec     = "let rec"
           | otherwise = "let"

instance (IsVar v) => Pretty (Expr st v) where
  pPrintPrec lvl prec = \case
    Var _ x -> pretty (varName x)
    Con _ c -> pretty c
    Num _ n -> int n
    App _ t us ->
      maybeParens (prec > Op.aprec) $ hsep
      $ pPrintPrec lvl Op.aprec t : map (pPrintPrec lvl (Op.aprec+1)) us
    -- TODO: Bring this back in Ap when _fun is an operator.
    -- ApOp   { _op, _arg1, _arg2 } ->
    --   let MkSpec { _sym, _prec, _assoc } = Operator.findByName _op
    --       (prec1, prec2) =
    --         case _assoc of
    --           AssocLeft  -> (_prec  , _prec+1)
    --           AssocRight -> (_prec+1, _prec  )
    --           AssocNone  -> (_prec+1, _prec+1)
    --   in  maybeParens (prec > _prec) $
    --         pPrintPrec lvl prec1 _arg1 <> text _sym <> pPrintPrec lvl prec2 _arg2
    -- TODO: Avoid this code duplication.
    Let _ ds t -> sep [prettyDefns False ds, "in"] $$ pPrintPrec lvl 0 t
    Rec _ ds t -> sep [prettyDefns True  ds, "in"] $$ pPrintPrec lvl 0 t
    Lam _ bs t ->
      maybeParens (prec > 0) $ hsep
        [ "fun", prettyBinds bs
        , "->" , pPrintPrec lvl 0 t
        ]
    -- If { _cond, _then, _else } ->
    --   maybeParens (prec > 0) $ sep
    --     [ "if"  <+> pPrintPrec lvl 0 _cond <+> "then"
    --     , nest 2 (pPrintPrec lvl 0 _then)
    --     , "else"
    --     , nest 2 (pPrintPrec lvl 0 _else)
    --     ]
    Mat _ t as ->
      maybeParens (prec > 0) $ vcat
      $ ("match" <+> pPrintPrec lvl 0 t <+> "with") : map (pPrintPrec lvl 0) as
    Cas _ t cs ->
      maybeParens (prec > 0) $ vcat
      $ ("match" <+> pPrintPrec lvl 0 t <+> "with") : map (pPrintPrec lvl 0) cs

instance (IsVar v) => Pretty (Case st v) where
  pPrintPrec lvl _ (MkCase _ c bs t) =
    hang ("|" <+> pretty c <+> prettyBinds bs <+> "->") 2 (pPrintPrec lvl 0 t)

instance (IsVar v) => Pretty (Altn st v) where
  pPrintPrec lvl _ (MkAltn _ p t) =
    hang ("|" <+> pPrintPrec lvl 0 p <+> "->") 2 (pPrintPrec lvl 0 t)

instance Pretty dcon => Pretty (GenPatn dcon) where
  pPrintPrec lvl prec = \case
    Bind   b    -> pretty b
    Dest _ c ps ->
      maybeParens (prec > 0 && not (null ps)) $
      pretty c <+> hsep (map (pPrintPrec lvl 1) (toList ps))

instance Pretty Bind where
  pPrint = \case
    Wild _   -> "_"
    Name _ x -> pretty x

prettyBinds :: Vector n Bind -> Doc
prettyBinds = hsep . map pretty . toList

-- * Derived instances
deriving instance Functor     (Expr st)
deriving instance Foldable    (Expr st)
deriving instance Traversable (Expr st)

deriving instance Functor     (Case st)
deriving instance Foldable    (Case st)
deriving instance Traversable (Case st)

deriving instance Functor     (Altn st)
deriving instance Foldable    (Altn st)
deriving instance Traversable (Altn st)
