{-# LANGUAGE GADTs #-}
module CoreLang.Demo where

import Text.Parsec (SourcePos)
import System.Console.Haskeline

import CoreLang.Language.Syntax (Expr)
import CoreLang.Pretty

import qualified CoreLang.Language.LambdaLifter   as Lifter
import qualified CoreLang.Language.Parser         as Parser
import qualified CoreLang.Monomorphic.Checker     as Mono
-- import qualified CoreLang.Monomorphic.Inferrer    as Mono.Inferrer
import qualified CoreLang.Polymorphic.TypeChecker as Poly


repl :: Pretty t => (Expr SourcePos -> Either String t) -> IO ()
repl cmd = runInputT (defaultSettings { historyFile = Just ".history" }) loop
  where
    loop :: InputT IO ()
    loop = do
      input <- getInputLine "[CoReLaNG] "
      case input of
        Nothing -> return ()
        Just code -> do
          case Parser.parseExpr "<repl>" code >>= cmd of
            Left  e -> outputStrLn $ "ERROR: " ++ e
            Right t -> do
              outputStrLn (replicate 60 '=')
              outputStrLn $ prettyShow t
              outputStrLn (replicate 60 '=')
          loop

onLabeledInput :: Pretty t => (Expr SourcePos -> Either String t) -> String -> String -> IO ()
onLabeledInput f file code =
  case Parser.parseExpr file code >>= f of
    Left  e -> putStrLn $ "error: " ++ e
    Right t -> putStrLn $ prettyShow t

onInput :: Pretty t => (Expr SourcePos -> Either String t) -> String -> IO ()
onInput f = onLabeledInput f "<input>"

file ::  Pretty t => (Expr SourcePos -> Either String t) -> String -> IO ()
file f file = readFile file >>= onLabeledInput f file

lambdaLifter :: Expr SourcePos -> Either String (Expr ())
lambdaLifter expr = do
  _ <- Poly.inferExpr expr
  return (Lifter.lifter expr)

data Command where
  Command :: Pretty t => String -> (Expr SourcePos -> Either String t) -> Command

commands :: [Command]
commands =
  [ Command "parse"      pure
  , Command "mono.check" Mono.checkExpr
  , Command "poly.infer" Poly.inferExpr
  , Command "lambdalift" (return . Lifter.lifter)
  ]
