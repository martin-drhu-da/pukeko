{-# LANGUAGE DeriveFunctor #-}
module Pukeko.Language.Syntax
  ( Expr (..)
  , Patn (..)
  , Defn (..)
  , desugarApOp
  , desugarIf
  , unzipPatns
  , unzipDefns
  , unzipDefns3
  , Annot (..)
  , inject
  , module Pukeko.Language.Ident
  )
  where

import Pukeko.Language.Ident
import Pukeko.Language.Operator (Spec (..), Assoc (..), aprec)
import Pukeko.Language.Term
import Pukeko.Language.Type (Type)
import Pukeko.Pretty

import qualified Pukeko.Language.Operator as Operator

data Expr a
  = Var    { _annot :: a, _ident :: Ident }
  | Num    { _annot :: a, _int   :: Int }
  | Pack   { _annot :: a, _tag   :: Int , _arity :: Int  }
  | Ap     { _annot :: a, _fun   :: Expr a, _arg :: Expr a }
  | ApOp   { _annot :: a, _op    :: Ident, _arg1 :: Expr a, _arg2 :: Expr a }
  | Let    { _annot :: a, _isrec :: Bool, _defns :: [Defn a], _body :: Expr a }
  | Lam    { _annot :: a, _patns :: [Patn a], _body :: Expr a }
  | If     { _annot :: a, _cond  :: Expr a, _then  :: Expr a, _else :: Expr a }
  deriving (Show, Functor)

data Patn a = MkPatn { _annot :: a, _ident :: Ident, _type :: Maybe Type }
  deriving (Show, Functor)

data Defn a = MkDefn { _patn :: Patn a, _expr :: Expr a }
  deriving (Show, Functor)


desugarApOp :: Expr a -> Expr a
desugarApOp ApOp{ _annot, _op, _arg1, _arg2 } =
  Ap { _annot
     , _fun = Ap { _annot
                 , _fun = Var { _annot, _ident = _op }
                 , _arg = _arg1
                 }
     , _arg = _arg2
     }
desugarApOp _ = error "desugarApOp can only be applied to ApOp nodes"

desugarIf :: Expr a -> Expr a
desugarIf If{ _annot, _cond, _then, _else } =
  Ap { _annot
     , _fun = Ap { _annot
                 , _fun = Ap { _annot
                             , _fun = Var { _annot, _ident = MkIdent "if" }
                             , _arg = _cond
                             }
                 , _arg = _then
                 }
     , _arg = _else
     }
desugarIf _ = error "desugarIf can only be applied to If nodes"

unzipPatns :: [Patn a] -> ([Ident], [Maybe Type])
unzipPatns = unzip . map (\MkPatn{ _ident, _type} -> (_ident, _type))

unzipDefns :: [Defn a] -> ([Patn a], [Expr a])
unzipDefns = unzip . map (\MkDefn{ _patn, _expr} -> (_patn, _expr))

unzipDefns3 :: [Defn a] -> ([Ident], [Maybe Type], [Expr a])
unzipDefns3 = unzip3 .
  map (\MkDefn{ _patn = MkPatn{ _ident, _type }, _expr } -> (_ident, _type, _expr))

class Annot f where
  annot :: f a -> a


inject :: Expr a -> Expr a -> Expr a
inject expr_prel expr_user =
  case expr_prel of
    Let { _body } -> expr_prel { _body = inject _body expr_user }
    _ -> expr_user


instance Pretty (Expr a) where
  pPrintPrec lvl prec expr =
    case expr of
      Var  { _ident } -> pretty _ident
      Num  { _int   } -> int _int
      Pack { _tag, _arity } -> text "Pack" <> braces (int _tag <> comma <> int _arity)
      Ap   { _fun, _arg   } ->
        maybeParens (prec > aprec) $
          pPrintPrec lvl aprec _fun <+> pPrintPrec lvl (aprec+1) _arg
      ApOp   { _op, _arg1, _arg2 } ->
        let MkSpec { _sym, _prec, _assoc } = Operator.findByName _op
            (prec1, prec2) =
              case _assoc of
                AssocLeft  -> (_prec  , _prec+1)
                AssocRight -> (_prec+1, _prec  )
                AssocNone  -> (_prec+1, _prec+1)
        in  maybeParens (prec > _prec) $
              pPrintPrec lvl prec1 _arg1 <> text _sym <> pPrintPrec lvl prec2 _arg2
      Let    { _isrec, _defns, _body  } ->
        case _defns of
          [] -> pPrintPrec lvl 0 _body
          defn0:defns -> vcat
            [ text (if _isrec then "letrec" else "let") <+> pPrintPrec lvl 0 defn0
            , vcat $ map (\defn -> text "and" <+> pPrintPrec lvl 0 defn) defns
            , text "in" <+> pPrintPrec lvl 0 _body
            ]
      Lam    { _patns, _body  } ->
        maybeParens (prec > 0) $ hsep
          [ text "fun", hsep (map (pPrintPrec lvl 1) _patns)
          , text "->" , pPrintPrec lvl 0 _body
          ]
      If { _cond, _then, _else } ->
        maybeParens (prec > 0) $ hsep
          [ text "if"  , pPrintPrec lvl 0 _cond
          , text "then", pPrintPrec lvl 0 _then
          , text "else", pPrintPrec lvl 0 _else
          ]
    where

instance Pretty (Defn a) where
  pPrintPrec lvl _ MkDefn{ _patn, _expr } =
    case _expr of
      Lam { _patns, _body } ->
        let lhs = pPrintPrec lvl 0 _patn <+> hsep (map (pPrintPrec lvl 1) _patns)
        in  hang (lhs <+> equals) 2 (pPrintPrec lvl 0 _body)
      _ -> hang (pPrintPrec lvl 0 _patn <+> equals) 2 (pPrintPrec lvl 0 _expr)

instance Pretty (Patn a) where
  pPrintPrec _ prec MkPatn{ _ident, _type } =
    case _type of
      Nothing -> pretty _ident
      Just t  -> maybeParens (prec > 0) $ pretty _ident <> colon <+> pretty t


instance Annot Expr where
  annot = _annot :: Expr _ -> _

instance Annot Patn where
  annot = _annot :: Patn _ -> _
