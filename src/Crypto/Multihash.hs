-- |
-- Module      : Crypto.Multihash
-- License     : BSD3
-- Maintainer  : Marcello Seri <marcello.seri@gmail.com>
-- Stability   : experimental
-- Portability : unknown
--
-- Multihash library built on top of haskell 'cryptonite' crypto package
-- Multihash is a protocol for encoding the hash algorithm and digest length 
-- at the start of the digest, see the official 
-- <https://github.com/jbenet/multihash/ multihash poroposal github repo>.
--
-- The library re-exports the needed types and typclasses from 'Crypto.Hash.Algorithms'
-- namely 'HashAlgorithm', 'SHA1', 'SHA256', 'SHA512', 'SHA3_512', 'SHA3_384',
-- 'SHA3_256', 'SHA3_224', 'Blake2b_512', 'Blake2s_256'. 
--
-- For additional informations refer to the README.md or the
-- <https://github.com/mseri/crypto-multihash gihub repository>.
--
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts  #-}

-- TODO: use length in check* to treat correctly truncated hashes
-- see https://github.com/jbenet/multihash/issues/1#issuecomment-91783612

module Crypto.Multihash
  ( -- * Multihash Types
    MultihashDigest
  , Base            (..)
  , Codable         (..)
  , Encodable       (..)
  --, Checkable       (..)
  --, Payload         (..)
  -- * Multihash helpers
  , multihash
  , multihashlazy
  , truncatedMultihash
  , truncatedMultihash'
  , checkMultihash
  , checkMultihash'
  , getBase
  -- * Re-exported types
  , HashAlgorithm
  , SHA1(..)
  , SHA256(..)
  , SHA512(..)
  , SHA3_512(..)
  , SHA3_384(..)
  , SHA3_256(..)
  , SHA3_224(..)
  , Blake2b_512(..)
  , Blake2s_256(..)
  ) where

import Crypto.Hash (Digest, hash, hashlazy)
import Crypto.Hash.Algorithms
import Data.ByteArray (ByteArrayAccess, Bytes)
import qualified Data.ByteArray as BA
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.List (elemIndex)
import Data.String (IsString(..))
import Data.String.Conversions
import Data.Word (Word8)

-------------------------------------------------------------------------------
import Crypto.Multihash.Internal.Types
import Crypto.Multihash.Internal
-------------------------------------------------------------------------------

-- | Multihash Digest container
data MultihashDigest a = MultihashDigest
  { _getAlgorithm :: a     -- ^ hash algorithm
  , _getLength :: Int      -- ^ hash lenght
  , _getDigest :: Digest a -- ^ binary digest data
  } deriving (Eq)

instance (HashAlgorithm a, Codable a) => Show (MultihashDigest a) where
  show = encode' Base58

instance (HashAlgorithm a, Codable a) => Encodable (MultihashDigest a) where
  encode base (MultihashDigest alg len md) = 
    -- lenght can be shorter to allow truncated multihash
    if len <=0 || len > BA.length md
      then
        Left "Corrupted MultihashDigest: invalid length"
      else do
        d <- fullDigestUnpacked
        return $ fromString $ map (toEnum . fromIntegral) d
        

    where
      fullDigestUnpacked :: Either String [Word8]
      fullDigestUnpacked = do
        d <- encoder base fullDigest
        return $ BA.unpack d

      fullDigest :: Bytes
      fullDigest = BA.pack [dHead, dSize] `BA.append` dTail
        where
          dHead :: Word8
          dHead = fromIntegral $ toCode alg
          dSize :: Word8
          dSize = fromIntegral len
          dTail :: Bytes
          dTail = BA.take len (BA.convert md)

  check hash_ multihash_ = let hash_' = convertString hash_ in do
    base <- getBase hash_'
    m <- encode base multihash_
    return (m == hash_')

-- | Newtype to allow the creation of a 'Checkable' typeclass for 
--   all 'ByteArrayAccess' without recurring to UndecidableInstances
newtype Payload bs = Payload bs

instance ByteArrayAccess bs => Checkable (Payload bs) where
  -- checkPayload :: (IsString s, ByteArrayAccess bs) => s -> bs -> Either String Bool
  checkPayload hash_ (Payload p) = let hash' = convertString hash_ in do
    base <- getBase hash'
    mhd <- convertFromBase base hash'
    -- Hacky... think to a different approach
    if badLength mhd 
      then 
        Left "Corrupted MultihasDigest: invalid length"
      else do
        m <- getBinaryEncodedMultihash mhd p
        return (m == mhd)

-------------------------------------------------------------------------------

-- | Helper to multihash a lazy 'BL.ByteString' using a supported hash algorithm.
--   Uses 'Crypto.Hash.hashlazy' for hashing.
multihashlazy :: (HashAlgorithm a, Codable a) => a -> BL.ByteString -> MultihashDigest a
multihashlazy alg bs = let digest = hashlazy bs
                       in MultihashDigest alg (BA.length digest) digest

-- | Helper to multihash a 'ByteArrayAccess' (e.g. a 'BS.ByteString') using a 
--   supported hash algorithm. Uses 'Crypto.Hash.hash' for hashing.
multihash :: (HashAlgorithm a, Codable a, ByteArrayAccess bs) => a -> bs -> MultihashDigest a
multihash alg bs = let digest = hash bs
                   in MultihashDigest alg (BA.length digest) digest


-- | Helper to multihash a 'ByteArrayAccess' using a supported hash algorithm. 
--   Uses 'Crypto.Hash.hash' for hashing and truncates the hash to the lenght 
--   specified (must be positive and not longer than the digest length).
truncatedMultihash :: (HashAlgorithm a, Codable a, ByteArrayAccess bs) 
                      => Int -> a -> bs -> Either String (MultihashDigest a)
truncatedMultihash len alg bs = let digest = hash bs in 
                  if len <= 0 || len > BA.length digest
                    then Left "invalid truncated multihash lenght"
                    else Right $ MultihashDigest alg len digest

-- | Unsafe helper to multihash a 'ByteArrayAccess' using a supported hash algorithm. 
--   Uses 'Crypto.Hash.hash' for hashing and truncates the hash to the lenght 
--   specified (must be positive and not longer than the digest length, otherwise
--   the function will throw an error).
truncatedMultihash' :: (HashAlgorithm a, Codable a, ByteArrayAccess bs) 
                      => Int -> a -> bs -> MultihashDigest a
truncatedMultihash' len alg bs = eitherToErr $ truncatedMultihash len alg bs

-------------------------------------------------------------------------------

-- | Safely check the correctness of an encoded 'Encodable' against the 
--   corresponding data.
checkMultihash :: (IsString s, ConvertibleStrings s BS.ByteString, ByteArrayAccess bs)
                  => s -> bs -> Either String Bool
checkMultihash h p = checkPayload h (Payload p)

-- | Unsafe version of 'checkMultihash'. 
--   Throws on encoding/decoding errors instead of returning an 'Either' type.
checkMultihash' :: (IsString s, ConvertibleStrings s BS.ByteString, ByteArrayAccess bs)
                   => s -> bs -> Bool
checkMultihash' h p = checkPayload' h (Payload p)

-------------------------------------------------------------------------------

-- | Infer the hash function from an unencoded 'BS.BinaryString' representing 
--   a 'MultihashDigest' and uses it to binary encode the data in a 'MultihashDigest'.
getBinaryEncodedMultihash :: (ByteArrayAccess bs, IsString s) 
                             => BS.ByteString -> bs -> Either String s
getBinaryEncodedMultihash mhd uh = 
  case elemIndex bitOne hashCodes of
    Just 0 -> rs SHA1 uh
    Just 1 -> rs SHA256 uh
    Just 2 -> rs SHA512 uh
    Just 3 -> rs SHA3_512 uh
    Just 4 -> rs SHA3_384 uh
    Just 5 -> rs SHA3_256 uh
    Just 6 -> rs SHA3_224 uh
    Just 7 -> rs Blake2b_512 uh
    Just 8 -> rs Blake2s_256 uh
    Just _ -> Left "This should be impossible"
    Nothing -> Left "Impossible to infer the appropriate hash from the header"
  where 
    [bitOne, bitTwo] = take 2 $ BA.unpack mhd
    rs alg s = truncatedMultihash (fromIntegral bitTwo) alg s >>= encode Base2
    
    hashCodes :: [Word8]
    hashCodes = map fromIntegral
                    ([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x40, 0x41]::[Int])
