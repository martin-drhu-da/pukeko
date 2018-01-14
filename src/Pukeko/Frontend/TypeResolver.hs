module Pukeko.FrontEnd.TypeResolver
  ( resolveModule
  ) where

import Pukeko.Prelude

import           Control.Lens

import           Pukeko.AST.SystemF
import qualified Pukeko.AST.Stage      as St
import qualified Pukeko.AST.ConDecl    as Con
import           Pukeko.AST.Type
import qualified Pukeko.AST.Identifier as Id

type In  = St.Renamer
type Out = St.TypeResolver

data TRState = MkTRState
  { _st2tcons :: Map Id.TCon (Some1 Con.TConDecl)
  , _st2dcons :: Map Id.DCon (Some1 (Pair1 Con.TConDecl Con.DConDecl))
  }
makeLenses ''TRState

newtype TR a = TR {unTR :: StateT TRState (Except String) a}
  deriving ( Functor, Applicative, Monad
           , MonadError String
           , MonadState TRState
           )

evalTR :: MonadError String m => TR a -> m a
evalTR tr =
  let st = MkTRState mempty mempty
  in  runExcept (evalStateT (unTR tr) st)

-- TODO: Use proper terminology in error messages.
trType :: Pos -> Type tv -> TR (Type tv)
trType w = type2tcon $ \tcon -> do
  ex <- uses st2tcons (has (ix tcon))
  unless ex (throwAt w "unknown type cons" tcon)
  pure tcon

insertTCon :: Pos -> Con.TConDecl n -> TR ()
insertTCon posn tcon@Con.MkTConDecl{_tname} = do
  old <- use (st2tcons . at _tname)
  when (isJust old) $ throwAt posn "duplicate type cons" _tname
  st2tcons . at _tname ?= Some1 tcon

insertDCon :: KnownNat n => Pos -> Con.TConDecl n -> Con.DConDecl n -> TR ()
insertDCon posn tcon dcon@Con.MkDConDecl{_dname} = do
  old <- use (st2dcons . at _dname)
  when (isJust old) $ throwAt posn "duplicate term cons" _dname
  st2dcons . at _dname ?= Some1 (Pair1 tcon dcon)

findDCon :: Pos -> Id.DCon -> TR Id.DCon
findDCon w dcon = do
  ex <- uses st2dcons (has (ix dcon))
  unless ex (throwAt w "unknown term cons" dcon)
  pure dcon

trTopLevel :: TopLevel In -> TR (TopLevel Out)
trTopLevel top = case top of
  TLTyp w tconDecls -> do
    for_ tconDecls (\(Some1 tcon) -> insertTCon w tcon)
    for_ tconDecls $ \(Some1 tcon@Con.MkTConDecl{_dcons = dconDecls}) -> do
      for_ dconDecls $ \dcon@Con.MkDConDecl{_fields} -> do
        for_ _fields (trType w)
        insertDCon w tcon dcon
    pure (TLTyp w tconDecls)
  TLVal w x t  -> TLVal w x <$> trType w t
  TLDef     d  -> TLDef <$> itraverseOf defn2dcon findDCon d
  TLAsm   b a  -> pure (TLAsm (retagBind b) a)

resolveModule :: MonadError String m => Module In -> m (Module Out)
resolveModule m0 = evalTR (module2tops (traverse trTopLevel) m0)