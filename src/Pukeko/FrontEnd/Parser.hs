{-# OPTIONS_GHC -Wno-missing-signatures #-}
-- | Implementation of the parser.
module Pukeko.FrontEnd.Parser
  ( Module
  , Package
  , parseInput
  , parseModule
  , parsePackage
  , extend
  )
  where

import Pukeko.Prelude hiding ((<|>), many)

import           System.FilePath as Sys
import           Text.Parsec
import           Text.Parsec.Expr
import           Text.Parsec.Language
import qualified Text.Parsec.Token as Token

import           Pukeko.AST.Operator   (Spec (..))
import           Pukeko.AST.Surface
import           Pukeko.AST.Type
import qualified Pukeko.AST.Identifier as Id
import qualified Pukeko.AST.Operator   as Op
import           Pukeko.FrontEnd.Parser.Build (build)

parseInput :: MonadError String m => SourceName -> String -> m Module
parseInput source =
  either (throwError . show) pure . parse (module_ source <* eof) source

parseModule :: (MonadError String m, MonadIO m) => FilePath -> m Module
parseModule file = do
  liftIO (putStr (file ++ " "))
  code <- liftIO (readFile file)
  parseInput file code

parsePackage :: (MonadError String m, MonadIO m) => FilePath -> m Package
parsePackage file = build parseModule file <* liftIO (putStrLn "")

type Parser = Parsec String ()

pukekoDef :: LanguageDef st
pukekoDef = haskellStyle
  { Token.reservedNames =
      [ "fun"
      , "val", "let", "rec", "and", "in"
      , "if", "then", "else"
      , "match", "with"
      , "type"
      , "external"
      , "import"
      ]
  , Token.opStart  = oneOf Op.letters
  , Token.opLetter = oneOf Op.letters
  , Token.reservedOpNames = ["=", "->", ":", ".", "|"]
  }

pukeko@Token.TokenParser
  { Token.reserved
  , Token.reservedOp
  , Token.operator
  , Token.natural
  , Token.identifier
  , Token.parens
  , Token.symbol
  , Token.whiteSpace
  } =
  Token.makeTokenParser pukekoDef

many1NE :: Parser a -> Parser (NonEmpty a)
many1NE p = (:|) <$> p <*> many p

sepBy1NE :: Parser a -> Parser sep -> Parser (NonEmpty a)
sepBy1NE p sep = (:|) <$> p <*> many (sep *> p)

getPos :: Parser Pos
getPos = mkPos <$> getPosition

nat :: Parser Int
nat = fromInteger <$> natural

equals, arrow, bar :: Parser ()
equals  = reservedOp "="
arrow   = reservedOp "->"
bar     = reservedOp "|"

evar :: Parser Id.EVar
evar = Id.evar <$> (lookAhead lower *> identifier)
  <|> Id.op <$> try (parens operator)

tvar :: Parser Id.TVar
tvar = Id.tvar <$> (lookAhead lower *> identifier)

tcon :: Parser Id.TCon
tcon = Id.tcon <$> (lookAhead upper *> Token.identifier pukeko)

dcon :: Parser Id.DCon
dcon = Id.dcon <$> (lookAhead upper *> Token.identifier pukeko)

type_, atype :: Parser (Type Id.TVar)
type_ =
  buildExpressionParser
    [ [ Infix (arrow *> pure (~>)) AssocRight ] ]
    (mkTApp <$> atype <*> many atype)
  <?> "type"
atype = choice
  [ TVar <$> tvar
  , TCon <$> tcon
  , parens type_
  ]

asType :: Parser (Type Id.TVar)
asType = reservedOp ":" *> type_

module_ :: SourceName -> Parser Module
module_ source = do
  imps <- many import_
  whiteSpace
  decls <- many $ choice
    [ let_ TLLet TLRec
    , TLAsm
      <$> getPos
      <*> (reserved "external" *> evar)
      <*> (equals *> Token.stringLiteral pukeko)
    , TLVal
      <$> getPos
      <*> (reserved "val" *> evar)
      <*> asType
    , TLTyp
      <$> getPos
      <*> (reserved "type" *> sepBy1NE tconDecl (reserved "and"))
    ]
  pure (MkModule source imps decls)

import_ :: Parser FilePath
import_ = do
  reserved "import"
  comps <- sepBy1 (many1 (lower <|> digit <|> char '_')) (char '/')
  void endOfLine
  pure (Sys.joinPath comps Sys.<.> "pu")

-- <patn>  ::= <apatn> | <con> <apatn>*
-- <apatn> ::= '_' | <evar> | <con> | '(' <patn> ')'
patn, apatn :: Parser Patn
patn  = PCon <$> getPos <*> dcon <*> many apatn <|>
        apatn
apatn = PWld <$> getPos <*  symbol "_"       <|>
        PVar <$> getPos <*> evar             <|>
        PCon <$> getPos <*> dcon <*> pure [] <|>
        parens patn

defnValLhs :: Parser (Expr Id.EVar -> Defn Id.EVar)
defnValLhs = MkDefn <$> bind

defnFunLhs :: Parser (Expr Id.EVar -> Defn Id.EVar)
defnFunLhs =
  (.) <$> (MkDefn <$> bind)
      <*> (ELam <$> getPos <*> many1NE bind)

-- TODO: Improve this code.
defn :: Parser (Defn Id.EVar)
defn = (try defnFunLhs <|> defnValLhs) <*> (equals *> expr) <?> "definition"

altn :: Parser (Altn Id.EVar)
altn =
  MkAltn <$> getPos
         <*> (bar *> patn)
         <*> (arrow *> expr)

let_ ::
  (Pos -> (NonEmpty (Defn Id.EVar)) -> a) ->
  (Pos -> (NonEmpty (Defn Id.EVar)) -> a) ->
  Parser a
let_ mkLet mkRec =
  f <$> getPos
    <*> (reserved "let" *> (reserved "rec" *> pure mkRec <|> pure mkLet))
    <*> sepBy1NE defn (reserved "and")
  where
    f w mk = mk w

expr, aexpr :: Parser (Expr Id.EVar)
expr =
  (buildExpressionParser operatorTable . choice)
  [ mkApp <$> getPos <*> aexpr <*> many aexpr
  , mkIf  <$> getPos
          <*> (reserved "if"   *> expr)
          <*> getPos
          <*> (reserved "then" *> expr)
          <*> getPos
          <*> (reserved "else" *> expr)
  , EMat
    <$> getPos
    <*> (reserved "match" *> expr)
    <*> (reserved "with"  *> (toList <$> many1 altn))
  , ELam
    <$> getPos
    <*> (reserved "fun" *> many1NE bind)
    <*> (arrow *> expr)
  , let_ ELet ERec <*> (reserved "in" *> expr)
  ]
  <?> "expression"
aexpr = choice
  [ EVar <$> getPos <*> evar
  , ECon <$> getPos <*> dcon
  , ENum <$> getPos <*> nat
  , parens expr
  ]

bind :: Parser Bind
bind = MkBind <$> getPos <*> evar

operatorTable = map (map f) (reverse Op.table)
  where
    f MkSpec { _sym, _assoc } = Infix (mkAppOp _sym <$> (getPos <* reservedOp _sym)) _assoc

tconDecl :: Parser TConDecl
tconDecl = MkTConDecl
  <$> tcon
  <*> many tvar
  <*> option [] (reservedOp "=" *> (toList <$> many1 dconDecl))

dconDecl :: Parser DConDecl
dconDecl = MkDConDecl <$> (reservedOp "|" *> dcon) <*> many atype