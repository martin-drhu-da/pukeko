module Pukeko.BackEnd
  ( NASM
  , run
  ) where

import Pukeko.Prelude

import qualified Pukeko.AST.NoLambda     as Lambda
import qualified Pukeko.BackEnd.Compiler as Compiler
import qualified Pukeko.BackEnd.NASM     as NASM
import qualified Pukeko.BackEnd.PeepHole as PeepHole

type NASM = String

run :: MonadError String m => Lambda.Module -> m NASM
run =
  Compiler.compile
  >=> pure . PeepHole.optimize
  >=> NASM.assemble