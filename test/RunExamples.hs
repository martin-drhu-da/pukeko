{-# OPTIONS_GHC -Wno-missing-signatures -Wno-name-shadowing #-}
module RunExamples where

import Pukeko.Prelude hiding (assert, run)

import Data.IORef
import System.Directory (setCurrentDirectory)
import System.Exit (ExitCode (..))
import System.FilePath
import System.Process (readProcess, readProcessWithExitCode)
import System.IO.Unsafe
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck
import Test.QuickCheck.Monadic

data Mode = Native | Ruceki

modeRef :: IORef Mode
modeRef = unsafePerformIO $ newIORef Native
{-# NOINLINE modeRef #-}

getMode :: IO Mode
getMode = readIORef modeRef

format :: [Int] -> String
format = unlines . map show

runProg :: FilePath -> String -> IO (ExitCode, String)
runProg prog input = do
  mode <- getMode
  let (cmd, args) = case mode of
        Native -> ("." </> prog, [])
        Ruceki -> ("ruceki", [prog <.> "pub"])
  (exitCode, stdout, _) <- readProcessWithExitCode cmd args input
  return (exitCode, stdout)

build prog = getMode >>= \case
  Native -> void (readProcess "make" [prog] "")
  Ruceki -> void (readProcess "make" [prog <.> "pub"] "")

specifyProg name = beforeAll_ (build name) . specify name

testText name input output =
  specifyProg name $ runProg name input `shouldReturn` (ExitSuccess, output)

testNumeric name input output = testText name (format input) (format output)

prop_prog_correct :: Gen [Int] -> ([Int] -> [Int]) -> FilePath -> Property
prop_prog_correct gen spec prog = monadicIO $ do
  xs <- pick gen
  (exitCode, stdout) <- run $ runProg prog (format xs)
  assert (exitCode == ExitSuccess)
  let ys = spec xs
  assert (stdout == format ys)

prop_sort_correct :: FilePath -> Property
prop_sort_correct =
  let gen = do
        n <- choose (0, 1000)
        xs <- vectorOf n (choose (-1000, 1000))
        return (n:xs)
  in  prop_prog_correct gen (sort . tail)

-- testSort :: String -> Test
testSort name = specifyProg name (prop_sort_correct name)

prop_function_correct :: Int -> (Int -> Int) -> FilePath -> Property
prop_function_correct bound spec =
  let gen = do
        n <- choose (0, bound)
        return [n]
  in  prop_prog_correct gen (\[x] -> [spec x])

-- testFunction :: String -> Int -> (Int -> Int) -> Test
testFunction name bound spec =
  specifyProg name (prop_function_correct bound spec name)

spec_catalan :: Int -> Int
spec_catalan n =
  let p = 100000007
      sols = 1 : map (sum . zipWith (*) sols) (tail $ scanl (flip (:)) [] sols)
  in  fromInteger $ (sols !! n) `mod` p

_spec_queens :: Int -> Int
_spec_queens n =
  let diff [] _  = []
      diff xs [] = xs
      diff (x:xs) (y:ys) = case x `compare` y of
        LT -> x : diff xs (y:ys)
        EQ -> diff xs ys
        GT -> diff (x:xs) ys
      solve' [] = [[]]
      solve' (ks:kss) = do
        k <- ks
        qs <- solve' $ zipWith (\ls i -> diff ls [k-i, k, k+i]) kss [1..]
        return $ k:qs
      solve n = solve' (replicate n [1..n])
  in  length $ solve n

spec_fibs :: Int -> Int
spec_fibs n =
  let p = 1000000000039
      fibs = 0 : 1 : zipWith (+) fibs (tail fibs)
  in  fromInteger $ (fibs !! n) `mod` p

spec_primes :: Int -> Int
spec_primes n =
  let sieve []     = undefined
      sieve (p:ks) = p : sieve (filter ((0 /=) . (`mod` p)) ks)
      primes = 2 : 3 : sieve (scanl1 (+) (5 : cycle [2, 4]))
  in  primes !! n

prop_rmq_correct :: FilePath -> Property
prop_rmq_correct prog = monadicIO $ do
  (m,n,xs,qs) <- pick $ do
    m <- choose (1, 1000)
    let n = 10
    xs <- vectorOf m $ choose (-1000, 1000)
    qs <- vectorOf n $ do
      lo <- choose (0, m-1)
      hi <- choose (lo, m-1)
      return (lo, hi)
    return (m, n, xs, qs)
  let input = m:n:xs ++ concatMap (\(lo, hi) -> [lo, hi]) qs
  (exitCode, stdout) <- run $ runProg prog (format input)
  assert (exitCode == ExitSuccess)
  let output = map (\(lo, hi) -> minimum $ take (hi-lo+1) $ drop lo xs) qs
  assert (stdout == format output)

main :: IO ()
main = hspec $ beforeAll_ (setCurrentDirectory "examples") $ do
  describe "native" $ do
    describe "test basics" $ do
      testText    "hello" "" "Hello World!\n"
      testText    "rev" "abc" "cba"
      testNumeric "monad_io" [3, 2]  (concat $ replicate 3 [2, 1, 0])
      testNumeric "wildcard" [7, 13] [7, 13]
      testNumeric "fix"      (10:[1 .. 10]) [2, 4 .. 20]
    describe "test sorting" $ mapM_ testSort
      [ "isort"
      , "qsort"
      , "tsort"
      ]
    describe "test number theory/combinatorics" $ do
      testFunction "fibs"    1000 spec_fibs
      testFunction "catalan"  100 spec_catalan
      testNumeric  "queens"   [8] [92]
      testFunction "primes"   100 spec_primes
      specifyProg "rmq" (prop_rmq_correct "rmq")
  beforeAll_ (writeIORef modeRef Ruceki) $ describe "interpreted" $ do
    describe "test basics" $ do
      testText    "hello" "" "Hello World!\n"
      testText    "rev" "abc" "cba"
      testNumeric "monad_io" [3, 2]  (concat $ replicate 3 [2, 1, 0])
      testNumeric "wildcard" [7, 13] [7, 13]
    describe "test sorting" $ modifyMaxSuccess (const 10) $ mapM_ testSort
      [ "isort"
      , "qsort"
      ]
    describe "test number theory/combinatorics" $ do
      testNumeric  "queens"   [8] [92]
