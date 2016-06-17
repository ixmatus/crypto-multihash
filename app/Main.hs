{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad
import Crypto.Multihash
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.List
import System.Console.GetOpt
import System.IO hiding (withFile)
import System.Environment
import System.Exit
import Text.Printf (printf)

main :: IO ()
main = do
  (args, files) <- getArgs >>= parse
  mapM_ printers files
  putStrLn "Done! Note: shake-128/256 and Base32 are not yet part of the library"
 
printer :: (HashAlgorithm a, Codable a, Show a) => a -> ByteString -> IO ()
printer alg bs = do
  let m = multihash alg bs
  putStrLn $ printf "Base16: %s" (encode Base16 m)
  -- Base32 missing
  putStrLn $ printf "Base58: %s" (encode Base58 m)
  putStrLn $ printf "Base64: %s" (encode Base64 m)
  putStrLn ""

printers f = do
  d <- withFile f
  putStrLn $ printf "Hashing %s\n" (if f == "-" then show d else show f)
  printer SHA1 d
  printer SHA256 d
  printer SHA512 d
  printer SHA3_512 d
  printer SHA3_384 d
  printer SHA3_256 d
  printer SHA3_224 d
  printer Blake2b_512 d
  printer Blake2s_256 d
  where withFile f = if f == "-" then B.getContents else B.readFile f

data Flag = Help                  -- --help
          deriving (Eq,Ord,Enum,Show,Bounded)
 
flags = [Option [] ["help"] (NoArg Help) "Print this help message"]
 
parse argv = case getOpt Permute flags argv of
    (args,fs,[]) -> do
        let files = if null fs then ["-"] else fs
        if Help `elem` args
            then do hPutStrLn stderr (usageInfo header flags)
                    exitWith ExitSuccess
            else return (nub (concatMap set args), files)
 
    (_,_,errs)   -> do
        hPutStrLn stderr (concat errs ++ usageInfo header flags)
        exitWith (ExitFailure 1)
 
    where header = "Usage: mh [file ...]"
          set f  = [f]