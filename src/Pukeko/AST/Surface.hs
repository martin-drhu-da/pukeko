-- | AST generated by the parser.
module Pukeko.AST.Surface
  ( -- * Types
    TCon
  , DCon
  , Package (..)
  , Module (..)
  , TopLevel (..)
  , TConDecl (..)
  , DConDecl (..)
  , Type (..)
  , Defn (..)
  , Expr (..)
  , Bind (..)
  , Altn (..)
  , Patn (..)

    -- * Smart constructors
  , mkApp
  , mkAppOp
  , mkIf
  , mkLam
  , mkTApp
  , mkTFun

  , extend
  , type2tvar
  )
where

import Pukeko.Prelude

import qualified Pukeko.AST.Identifier as Id

type TCon = Id.TCon
type DCon = Id.DCon

data Package = MkPackage
  { _pkg2root    :: FilePath
  , _pkg2modules :: [Module]
  }

data Module = MkModule
  { _mod2file    :: FilePath
  , _mod2imports :: [FilePath]
  , _mod2decls   :: [TopLevel]
  }

data TopLevel
  = TLTyp Pos (NonEmpty TConDecl)
  | TLVal Pos Id.EVar Type
  | TLLet Pos (NonEmpty (Defn Id.EVar))
  | TLRec Pos (NonEmpty (Defn Id.EVar))
  | TLAsm Pos Id.EVar String

data TConDecl = MkTConDecl
  { _tname  :: Id.TCon
  , _params :: [Id.TVar]
  , _dcons  :: [DConDecl]
  }

data DConDecl = MkDConDecl
  { _dname  :: Id.DCon
  , _fields :: [Type]
  }

data Type
  = TVar Id.TVar
  | TCon Id.TCon
  | TArr
  | TApp Type Type

data Defn v = MkDefn Bind (Expr v)

data Expr v
  = EVar Pos v
  | ECon Pos DCon
  | ENum Pos Int
  | EApp Pos (Expr v) (NonEmpty (Expr v))
  | EMat Pos (Expr v) [Altn v]
  | ELam Pos (NonEmpty Bind) (Expr v)
  | ELet Pos (NonEmpty (Defn v)) (Expr v)
  | ERec Pos (NonEmpty (Defn v)) (Expr v)

data Bind = MkBind Pos Id.EVar

data Altn v = MkAltn Pos Patn (Expr v)

data Patn
  = PWld Pos
  | PVar Pos Id.EVar
  | PCon Pos Id.DCon [Patn]

extend :: Module -> Package -> Package
extend mdl (MkPackage _ mdls) = MkPackage (_mod2file mdl) (mdls ++ [mdl])

mkApp :: Pos -> Expr v -> [Expr v] -> Expr v
mkApp pos fun = \case
  []       -> fun
  arg:args -> EApp pos fun (arg :| args)

mkAppOp :: String -> Pos -> Expr Id.EVar -> Expr Id.EVar -> Expr Id.EVar
mkAppOp sym pos arg1 arg2 =
  let fun = EVar pos (Id.op sym)
  in  EApp pos fun (arg1 :| [arg2])

mkIf :: Pos -> Expr v -> Pos -> Expr v -> Pos -> Expr v -> Expr v
mkIf wt t wu u wv v =
  EMat wt t [ MkAltn wu (PCon wu (Id.dcon "True") []) u
            , MkAltn wv (PCon wv (Id.dcon "False") []) v
            ]

mkLam :: Pos -> [Bind] -> Expr v -> Expr v
mkLam w = \case
  []     -> id
  (b:bs) -> ELam w (b :| bs)

mkTApp :: Type -> [Type] -> Type
mkTApp = foldl TApp

mkTFun :: Type -> Type -> Type
mkTFun tx ty = mkTApp TArr [tx, ty]

type2tvar :: Traversal' Type Id.TVar
type2tvar f = \case
  TVar v     -> TVar <$> f v
  TCon c     -> pure (TCon c)
  TArr       -> pure TArr
  TApp tf tp -> TApp <$> type2tvar f tf <*> type2tvar f tp
