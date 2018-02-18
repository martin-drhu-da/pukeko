{-# LANGUAGE GADTs #-}
-- | Check that all type constructor are applied to the right number of
-- variables and all variables are bound.
module Pukeko.FrontEnd.KindChecker
  ( checkModule
  ) where

import Pukeko.Prelude
import Pukeko.Pretty

import           Control.Monad.Freer.Supply
import           Control.Monad.ST
import           Data.Forget      (Forget (..))
import qualified Data.Map           as Map
import           Data.STRef
import qualified Data.Vector        as Vec

import           Pukeko.AST.SystemF    hiding (Free)
import           Pukeko.AST.Language
import           Pukeko.AST.Name
import           Pukeko.AST.ConDecl
import qualified Pukeko.AST.Identifier as Id
import           Pukeko.AST.Type

type In  = Surface

data Open s

data UVar s
  = Free (Forget Id.TVar)
  | Link (Kind (Open s))

data Kind a where
  Star  ::                     Kind a
  Arrow :: Kind a -> Kind a -> Kind a
  UVar  :: STRef s (UVar s) -> Kind (Open s)

type KCEnv n s = Vector (Kind (Open s))

type KCState s = Map (Name TCon) (Kind (Open s))

type KC n s =
  Eff
  [ Reader (KCEnv n s), State (KCState s)
  , Reader SourcePos, Supply Id.TVar, Error Failure, ST s
  ]

freshUVar :: KC n s (Kind (Open s))
freshUVar = do
  v <- fresh
  UVar <$> sendM (newSTRef (Free (Forget v)))

localize :: [Kind (Open s)] -> KC n s a -> KC m s a
localize env = local' (const (Vec.fromList env))

kcType :: Kind (Open s) -> Type (TScope Int Void) -> KC n s ()
kcType k = \case
  TVar v -> do
    kv <- asks (Vec.! scope absurd id v)
    unify kv k
  TAtm TAArr -> unify (Arrow Star (Arrow Star Star)) k
  TAtm TAInt -> unify Star k
  TAtm (TACon tcon) -> do
    kcon <- gets (Map.! tcon)
    unify kcon k
  TApp tf tp -> do
    ktp <- freshUVar
    kcType ktp tp
    kcType (Arrow ktp k) tf
  TUni{} -> impossible  -- we have only rank-1 types and no type annotations

kcTConDecl :: TConDecl -> KC n s ()
kcTConDecl (MkTConDecl tcon prms dcons0) = here tcon $ do
  kind <- freshUVar
  modify (Map.insert tcon kind)
  paramKinds <- traverse (const freshUVar) prms
  unify kind (foldr Arrow Star paramKinds)
  localize paramKinds $
    case dcons0 of
      Left typ -> kcType Star typ
      Right dcons ->
        for_ dcons $ here' $ \MkDConDecl{_dcon2fields = flds} ->
          traverse_ (kcType Star) flds
  close kind

kcVal :: Type Void -> KC n s ()
kcVal = \case
  TUni xs t -> k (toList xs) t
  t         -> k [] (fmap absurd t)
  where
    k xs t = do
      env <- traverse (const freshUVar) xs
      localize env (kcType Star t)

kcDecl :: Decl In -> KC n s ()
kcDecl decl = case decl of
  DType tcon -> kcTConDecl tcon
  DSign (MkSignDecl _ t) -> kcVal t
  -- NOTE: The typed in (external) function declaration are bogus (for now), so
  -- there's nothing to be checked.
  DFunc{} -> pure ()
  DExtn{} -> pure ()
  -- FIXME: Check kinds in type class declarations and instance definitions.
  DClss{} -> pure ()
  DInst{} -> pure ()

kcModule ::Module In -> KC n s ()
kcModule (MkModule decls)= traverse_ (\top -> reset @Id.TVar *> kcDecl top) decls

checkModule :: Member (Error Failure) effs => Module In -> Eff effs ()
checkModule module0 = either throwError pure $ runST $
  kcModule module0
  & runReader Vec.empty
  & evalState mempty
  & runReader noPos
  & evalSupply Id.freshTVars
  & runError
  & runM


unwind :: Kind (Open s) -> KC n s (Kind (Open s))
unwind k0 = case k0 of
  UVar uref -> do
    sendM (readSTRef uref) >>= \case
      Free _  -> pure k0
      Link k1 -> do
        k2 <- unwind k1
        sendM (writeSTRef uref (Link k2))
        pure k2
  _ -> pure k0

assertFree :: STRef s (UVar s) -> KC a s ()
assertFree uref =
  sendM (readSTRef uref) >>= \case
    Free _ -> pure ()
    Link _ -> impossible  -- this is only called after unwinding

occursCheck :: STRef s (UVar s) -> Kind (Open s) -> KC n s ()
occursCheck uref1 = \case
  Star        -> pure ()
  Arrow kf kp -> occursCheck uref1 kf *> occursCheck uref1 kp
  UVar uref2
    | uref1 == uref2 -> throwHere "occurs check"
    | otherwise -> do
        uvar2 <- sendM (readSTRef uref2)
        case uvar2 of
          Link k2 -> occursCheck uref1 k2
          Free _  -> pure ()

unify :: Kind (Open s) -> Kind (Open s) -> KC n s ()
unify k1 k2 = do
  k1 <- unwind k1
  k2 <- unwind k2
  case (k1, k2) of
    (Star, Star) -> pure ()
    (Arrow kf1 kp1, Arrow kf2 kp2) -> unify kf1 kf2 *> unify kp1 kp2
    (UVar uref1, UVar uref2)
      | uref1 == uref2 -> pure ()
    (UVar uref1, _) -> do
      assertFree uref1
      occursCheck uref1 k2
      sendM (writeSTRef uref1 (Link k2))
    (_, UVar _) -> unify k2 k1
    -- TODO: Improve error message.
    (_, _) -> do
      d1 <- sendM (prettyKind False k1)
      d2 <- sendM (prettyKind False k2)
      throwHere ("cannot unify kinds" <+> d1 <+> "and" <+> d2)

close :: Kind (Open s) -> KC n s ()
close k = do
  k <- unwind k
  case k of
    Star -> pure ()
    Arrow kf kp -> close kf *> close kp
    UVar uref -> do
      assertFree uref
      sendM (writeSTRef uref (Link Star))

prettyKind :: Bool -> Kind (Open s) -> ST s (Doc ann)
prettyKind prec = \case
  Star -> pure "*"
  Arrow kf kp -> do
    df <- prettyKind True  kf
    dp <- prettyKind False kp
    pure $ maybeParens prec (df <+> "->" <+> dp)
  UVar uref -> do
    uvar <- readSTRef uref
    case uvar of
      Free (Forget v) -> pure (pretty v)
      Link k          -> prettyKind prec k
