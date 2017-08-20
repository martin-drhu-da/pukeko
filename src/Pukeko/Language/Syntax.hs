{-# LANGUAGE DeriveFunctor #-}
module Pukeko.Language.Syntax
  ( Module
  , TopLevel (..)
  , Expr (..)
  , Patn (..)
  , Patn1
  , Defn (..)
  , Altn (..)
  , mkAp
  , mkApOp
  , desugarIf
  , unzipDefns
  , envPatn1
  , zipMaybe
  , Annot (..)
  , TypeConOf
  , TermConOf
  , StageLP
  , StageTR
  )
where

import Data.Map (Map)
import Data.Maybe (catMaybes)
import qualified Data.Map as Map

import Pukeko.Error
import Pukeko.Pretty
import Pukeko.Language.Operator (aprec)
import Pukeko.Language.Type (Type, Closed, ADT (..), Constructor (..), mkADT, mkConstructor)
import qualified Pukeko.Language.Ident    as Ident

type family TypeConOf stage
type family TermConOf stage

data StageLP
type instance TypeConOf StageLP = Ident.Con
type instance TermConOf StageLP = Ident.Con

data StageTR
type instance TypeConOf StageTR = ADT Ident.Con
type instance TermConOf StageTR = Constructor (ADT Ident.Con)


type Module stage a = [TopLevel stage a]

data TopLevel stage a
  = Type{ _annot :: a, _adts :: [ADT (TypeConOf stage)] }
  | Val{ _annot :: a, _ident :: Ident.EVar, _type :: Type (TypeConOf stage) Closed }
  | Def{ _annot :: a, _isrec :: Bool, _defns :: [Defn stage a] }
  | Asm{ _annot :: a, _ident :: Ident.EVar, _asm :: String }

data Expr stage a
  = Var    { _annot :: a, _var   :: Ident.EVar }
  | Con    { _annot :: a, _con   :: TermConOf stage }
  | Num    { _annot :: a, _int   :: Int }
  | Ap     { _annot :: a, _fun   :: Expr stage a   , _args  :: [Expr stage a] }
  | Lam    { _annot :: a, _patns :: [Patn1 stage a], _body  :: Expr stage a   }
  | Let    { _annot :: a, _isrec :: Bool     , _defns :: [Defn stage a], _body :: Expr stage a }
  | If     { _annot :: a, _cond  :: Expr stage a   , _then  :: Expr stage a  , _else :: Expr stage a }
  | Match  { _annot :: a, _expr  :: Expr stage a   , _altns :: [Altn stage a] }
  deriving (Functor)

data Patn stage a
  = Wild{_annot :: a}
  | Bind{_annot :: a, _ident :: Ident.EVar}
  deriving (Functor)

type Patn1 = Patn

data Defn stage a = MkDefn{_annot :: a, _lhs :: Ident.EVar, _rhs :: Expr stage a}
  deriving (Functor)

data Altn stage a = MkAltn{ _annot :: a, _con :: TermConOf stage, _patns :: [Patn1 stage a], _rhs :: Expr stage a }
  deriving (Functor)

mkAp :: a -> Expr stage a -> [Expr stage a] -> Expr stage a
mkAp _annot _fun _args
  | null _args = _fun
  | otherwise  = Ap { _annot, _fun, _args }

mkApOp :: String -> a -> Expr stage a -> Expr stage a -> Expr stage a
mkApOp sym _annot arg1 arg2 =
  let _fun = Var{ _annot, _var = Ident.op sym }
  in  Ap{ _annot, _fun, _args = [arg1, arg2]}

boolFalse, boolTrue :: Constructor (ADT Ident.Con)
MkADT{_constructors = [boolFalse, boolTrue]} =
  let ident = Ident.constructor "Bool"
      mk adt = mkADT ident adt []
        [ mkConstructor (Ident.constructor "False") []
        , mkConstructor (Ident.constructor "True" ) []
        ]
  in  mk (mk ident)

desugarIf :: Expr StageTR a -> Expr StageTR a
desugarIf If{ _annot, _cond, _then, _else } =
  Match { _annot = _annot
        , _expr  = _cond
        , _altns =
          [ MkAltn { _annot = annot _else
                   , _con   = boolFalse
                   , _patns = []
                   , _rhs   = _else
                   }
          , MkAltn { _annot = annot _then
                   , _con   = boolTrue
                   , _patns = []
                   , _rhs   = _then
                   }
          ]
        }
desugarIf _ = bug "syntax" "desugarIf on wrong node" Nothing

unzipDefns :: [Defn stage a] -> ([Ident.EVar], [Expr stage a])
unzipDefns = unzip . map (\MkDefn{_lhs, _rhs} -> (_lhs, _rhs))

envPatn1 :: [Patn1 stage a] -> [b] -> Map Ident.EVar b
envPatn1 bs = Map.fromList . catMaybes . zipWith f bs
  where f patn x = case patn of
          Wild{}       -> Nothing
          Bind{_ident} -> Just (_ident, x)

zipMaybe :: [Maybe a] -> [b] -> [(a, b)]
zipMaybe xs = catMaybes . zipWith (\x y -> (,) <$> x <*> pure y) xs

instance (Pretty (TypeConOf stage), Pretty (TermConOf stage)) => Pretty (Expr stage a) where
  pPrintPrec lvl prec expr =
    case expr of
      Var  { _var } -> pretty _var
      Con  { _con } -> pretty _con
      Num  { _int } -> int _int
      Ap   { _fun, _args } ->
        maybeParens (prec > aprec) $ hsep $
          pPrintPrec lvl aprec _fun : map (pPrintPrec lvl (aprec+1)) _args
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
      Let    { _isrec, _defns, _body  } ->
        case _defns of
          [] -> pPrintPrec lvl 0 _body
          defn0:defns -> vcat
            [ sep
              [ vcat $
                ((if _isrec then "let rec" else "let") <+> pPrintPrec lvl 0 defn0) :
                map (\defn -> "and" <+> pPrintPrec lvl 0 defn) defns
              , "in"
              ]
            , pPrintPrec lvl 0 _body
            ]
      Lam{_patns, _body} ->
        maybeParens (prec > 0) $ hsep
          [ "fun", hsep (map (pPrintPrec lvl 1) _patns)
          , "->" , pPrintPrec lvl 0 _body
          ]
      If { _cond, _then, _else } ->
        maybeParens (prec > 0) $ sep
          [ "if"  <+> pPrintPrec lvl 0 _cond <+> "then"
          , nest 2 (pPrintPrec lvl 0 _then)
          , "else"
          , nest 2 (pPrintPrec lvl 0 _else)
          ]
      Match { _expr, _altns } ->
        maybeParens (prec > 0) $ vcat $
        ("match" <+> pPrintPrec lvl 0 _expr <+> "with") :
        map (pPrintPrec lvl 0) _altns

instance (Pretty (TypeConOf stage), Pretty (TermConOf stage)) => Pretty (Defn stage a) where
  pPrintPrec lvl _ MkDefn{ _lhs, _rhs } = case _rhs of
    Lam{_patns, _body} ->
      let lhs = pPrintPrec lvl 0 _lhs <+> hsep (map (pPrintPrec lvl 1) _patns)
      in  hang (lhs <+> equals) 2 (pPrintPrec lvl 0 _body)
    _ -> hang (pPrintPrec lvl 0 _lhs <+> equals) 2 (pPrintPrec lvl 0 _rhs)

instance (Pretty (TypeConOf stage)) => Pretty (Patn1 stage a) where
  pPrintPrec _ _ patn = case patn of
    Wild{}       -> "_"
    Bind{_ident} -> pretty _ident

instance (Pretty (TypeConOf stage), Pretty (TermConOf stage)) => Pretty (Altn stage a) where
  pPrintPrec lvl _ MkAltn{_con, _patns, _rhs} = hang
    (hsep ["|", pretty _con, hsep (map (pPrintPrec lvl 1) _patns), "->"]) 2
    (pPrintPrec lvl 0 _rhs)

instance (Pretty (TypeConOf stage), Pretty (TermConOf stage)) => Pretty (TopLevel stage a) where
  pPrintPrec lvl _ top = case top of
    Type{} -> empty
    Val{} -> empty
    -- TODO: Avoid code duplication.
    Def{ _isrec, _defns } -> case _defns of
      [] -> empty
      defn0:defns -> vcat $
        ((if _isrec then "let rec" else "let") <+> pPrintPrec lvl 0 defn0) :
        map (\defn -> "and" <+> pPrintPrec lvl 0 defn) defns
    Asm{ _ident, _asm } ->
      hsep ["external", pretty _ident, equals, text (show _asm)]

class Annot f where
  annot :: f a -> a

instance Annot (TopLevel stage) where
  annot = _annot :: TopLevel _ _ -> _

instance Annot (Expr stage) where
  annot = _annot :: Expr _ _ -> _

instance Annot (Defn stage) where
  annot = _annot :: Defn _ _ -> _

instance Annot (Patn stage) where
  annot = _annot :: Patn _ _ -> _

instance Annot (Altn stage) where
  annot = _annot :: Altn _ _ -> _
