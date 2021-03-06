{-# LANGUAGE OverloadedStrings #-}

import Control.Monad (zipWithM, forM_)
import Crypto.Multihash
import Crypto.Multihash.Weak (weakMultihash, checkWeakMultihash, toWeakMultihash)
import Data.ByteString (ByteString, pack, unpack)
import Text.Printf (printf)

import Test.Hspec
import Test.QuickCheck

-- TODO: 
--   * use QuickCheck to test Multihash serializatio/deserializatio/check properties
--     especially now that we infer the decoding for arbitrary truncations
--   * test for valid and invalid truncated multihashes

instance Arbitrary ByteString where
    arbitrary = pack `fmap` arbitrary
    --coarbitrary = coarbitrary . unpack

testString :: ByteString
testString = "test"

failTestString :: ByteString
failTestString = "test1"

weakAlgos = [ "sha1", "sha256", "sha512", "sha3-512" 
            , "sha3-384", "sha3-256", "sha3-224"
            , "blake2b-512", "blake2s-256" ]

-- Useful for testing, generated in Weak by
-- tester = map (\(a,_) -> _getLength $ weakMultihash' a ("test"::ByteString)) allowedAlgos
maxHashLengths = [20,32,64,64,48,32,28,64,32]

main :: IO ()
main = runSpec

prop_gen_check :: ByteString -> Property
prop_gen_check str = 
  let m = multihash SHA1 str
      enc :: ByteString
      enc = encode' Base16 m 
  in check' enc m === True

prop_get_base :: Base -> ByteString -> Property
prop_get_base base str = 
  let m = multihash SHA1 str
      enc :: ByteString
      enc = encode' base m 
  in getBase enc === Right base

runQC = quickCheck prop_gen_check

runSpec = hspec $ do
  ------------------------------------------------------------------------
  describe "Multihash: check properties with QuickCheck" $ do
    it "correctly encodes and checks SHA1" $
      property prop_gen_check
    forM_ [Base16, Base32, Base58, Base64] $ \b -> 
      it ("correctly infer" ++ show b ++ "encodings on full-length hashes") $ 
        property (prop_get_base b)
  ------------------------------------------------------------------------
  mhEncoding SHA1 h1
  mhCheck mh checkMultihash SHA1 h1
  mhEncoding SHA256 h2
  mhCheck mh checkMultihash SHA256 h2
  mhEncoding SHA512 h3
  mhCheck mh checkMultihash SHA512 h3
  mhEncoding SHA3_512 h4
  mhCheck mh checkMultihash SHA3_512 h4
  mhEncoding SHA3_384 h5
  mhCheck mh checkMultihash SHA3_384 h5
  mhEncoding SHA3_256 h6
  mhCheck mh checkMultihash SHA3_256 h6
  mhEncoding SHA3_224 h7
  mhCheck mh checkMultihash SHA3_224 h7
  mhEncoding Blake2b_512 h8
  mhCheck mh checkMultihash Blake2b_512 h8
  mhEncoding Blake2s_256 h9
  mhCheck mh checkMultihash Blake2s_256 h9
  ------------------------------------------------------------------------
  traverse (uncurry wmhEncoding) 
           (zip weakAlgos h)
  traverse (uncurry (mhCheck wmh checkWeakMultihash))
           (zip weakAlgos h)
  ------------------------------------------------------------------------
  describe "Multihash: fails correctly when" $ do
    it "checking an invalid truncated multihash" $
      checkMultihash ("1340ee26b0dd4af7e749aa1a8e"::ByteString) testString 
        `shouldBe` Left "Corrupted MultihasDigest: invalid length"
    it "checking an invalid truncated multihash" $
      checkMultihash ("dd4af7e749aa1a8e1340ee26b0"::ByteString) testString 
        `shouldBe` Left "Corrupted MultihasDigest: invalid length"
  
  describe "Weak Multihash: fails correctly when" $ do
    it "checking an invalid truncated multihash" $
      checkWeakMultihash ("1340ee26b0dd4af7e749aa1a8e"::ByteString) testString 
        `shouldBe` Left "Corrupted MultihasDigest: invalid length"
    it "checking an invalid truncated multihash" $
      checkWeakMultihash ("dd4af7e749aa1a8e1340ee26b0"::ByteString) testString 
        `shouldBe` Left "Corrupted MultihasDigest: invalid length"
  ------------------------------------------------------------------------
  where
    mh = "Multihash"::String
    wmh = "Weak Multihash"::String

    mhEncoding :: (HashAlgorithm a, Codable a, Show a) => a 
                      -> (ByteString, ByteString, ByteString, ByteString) -> SpecWith ()
    mhEncoding alg (sm16, sm32, sm58, sm64) = 
        let m = multihash alg testString in
        describe (printf "Multihash: encoding %s multihash" (show alg)) $ do
          it "returns the correct Base16 hash" $ 
            encode' Base16 m `shouldBe` sm16
          it "returns the correct Base32 hash" $ 
            encode' Base32 m `shouldBe` sm32
          it "returns the correct Base58 hash" $ 
            encode' Base58 m `shouldBe` sm58
          it "returns the correct Base64 hash" $ 
            encode' Base64 m `shouldBe` sm64

    wmhEncoding :: ByteString 
                       -> (ByteString, ByteString, ByteString, ByteString) -> SpecWith ()
    wmhEncoding alg (sm16, sm32, sm58, sm64) = 
        let m = case weakMultihash alg testString of 
                  Right val -> val
                  Left  err -> error err
        in do
        describe (printf "Weak Multihash: encoding %s multihash" (show alg)) $ do
          it "returns the correct Base16 hash" $ 
            encode' Base16 m `shouldBe` sm16
          it "returns the correct Base32 hash" $ 
            encode' Base32 m `shouldBe` sm32
          it "returns the correct Base58 hash" $ 
            encode' Base58 m `shouldBe` sm58
          it "returns the correct Base64 hash" $ 
            encode' Base64 m `shouldBe` sm64

        describe (printf "Weak Multihash: decoding %s multihash" (show alg)) $ do
          it "imports the correct hash from Base16" $ 
            toWeakMultihash sm16 `shouldBe` Right m
          it "imports the correct hash from Base32" $ 
            toWeakMultihash sm32 `shouldBe` Right m
          it "imports the correct hash from Base58" $ 
            toWeakMultihash sm58 `shouldBe` Right m
          it "imports the correct hash from Base64" $ 
            toWeakMultihash sm64 `shouldBe` Right m
    
    -- hashChecker :: (HashAlgorithm a, Codable a, Show a) => a 
    --                -> (ByteString, ByteString, ByteString, ByteString) -> SpecWith ()
    mhCheck t checker alg (e16, e32, e58, e64) =
      describe (printf "%s: using checkPayload on %s hashes" t (show alg)) $ do
        it "checks correctly Base16 hashes"  $
          checker e16 testString `shouldBe` Right True
        it "fails correctly on Base16 hashes" $
          checker e16 failTestString `shouldBe` Right False
        it "checks correctly Base32 hashes"  $
          checker e32 testString `shouldBe` Right True
        it "fails correctly on Base32 hashes" $
          checker e32 failTestString `shouldBe` Right False
        it "checks correctly Base58 hashes" $
          checker e58 testString `shouldBe` Right True
        it "fails correctly on Base58 hashes" $
          checker e58 failTestString `shouldBe` Right False
        it "checks correctly Base64 hashes" $
          checker e64 testString `shouldBe` Right True
        it "fails correctly on Base64 hashes" $
          checker e64 failTestString `shouldBe` Right False

    -- array of triples of hashes of the string "test"
    h@[h1, h2, h3, h4, h5, h6, h7, h8, h9] = 
      [
        ( "1114a94a8fe5ccb19ba61c4c0873d391e987982fbbd3"
        , "CEKKSSUP4XGLDG5GDRGAQ46TSHUYPGBPXPJQ===="
        , "5dt9CqvXK9qs7vazf7k7ZRqe28VPTg"
        , "ERSpSo/lzLGbphxMCHPTkemHmC+70w==")
      , ( "12209f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        , "CIQJ7BWQQGEEY7LFTIX6VIGFLLIBLI57J4NSWC4CFTIV23AVWDYAUCA=" 
        , "QmZ5NmGeStdit7tV6gdak1F8FyZhPsfA843YS9f2ywKH6w"
        , "EiCfhtCBiEx9ZZov6qDFWtAVo79PGysLgizRXWwVsPAKCA==")
      , ( "1340ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff"
        , "CNAO4JVQ3VFPPZ2JVINI5Y6BBLUZEP3BRGAHOLSHH6EBTJOUSQHA3MT2YGC7RIHB2X4E7CF4RB75M6YUG4ZMGBGML6U23DTPK72QAKFI74======"
        , "8VxYhLL7s5BvLogtUGgNJ7DebZ5Ba9mG3izfc7v6o4RZ28x469vJaifa3TQ13Z9DycmAuJWnp7ErkZofm4rsMo78fQ"
        , "E0DuJrDdSvfnSaoajuPBCumSP2GJgHcuRz+IGaXUlA4NsnrBhfig4dX4T4i8iH/WexQ3MsMEzF+prY5vV/UAKKj/")
      , ( "14409ece086e9bac491fac5c1d1046ca11d737b92a2b2ebd93f005d7b710110c0a678288166e7fbe796883a4f2e9b3ca9f484f521d0ce464345cc1aec96779149c14"
        , "CRAJ5TQIN2N2YSI7VROB2ECGZII5ON5ZFIVS5PMT6AC5PNYQCEGAUZ4CRALG4756PFUIHJHS5GZ4VH2IJ5JB2DHEMQ2FZQNOZFTXSFE4CQ======"
        , "8tXEcJyq2MCx27UHYbZxmte37ezBawV35QhfKPtq5QeSnX66q4DDf1cwMYUh2pUVbxdQgrDaSjbrPrfNxzvSSLQAtT"
        , "FECezghum6xJH6xcHRBGyhHXN7kqKy69k/AF17cQEQwKZ4KIFm5/vnlog6Ty6bPKn0hPUh0M5GQ0XMGuyWd5FJwU")
      , ( "1530e516dabb23b6e30026863543282780a3ae0dccf05551cf0295178d7ff0f1b41eecb9db3ff219007c4e097260d58621bd"
        , "CUYOKFW2XMR3NYYAE2DDKQZIE6AKHLQNZTYFKUOPAKKRPDL76DY3IHXMXHNT74QZAB6E4CLSMDKYMIN5"
        , "G9LerVN7c3uUAAymoAGkCGZPn53PZi1SHwPJ2nznLp82jcM2M1KLwpfrZh3F1QRVG3f2"
        , "FTDlFtq7I7bjACaGNUMoJ4Cjrg3M8FVRzwKVF41/8PG0Huy52z/yGQB8TglyYNWGIb0=")
      , ( "162036f028580bb02cc8272a9a020f4200e346e276ae664e45ee80745574e2f5ab80"
        , "CYQDN4BILAF3ALGIE4VJUAQPIIAOGRXCO2XGMTSF52AHIVLU4L22XAA="
        , "W1d9SeHn1mCnY3jZMs5YeqfFbwEnq5gQy1VDymGoPK28RD"
        , "FiA28ChYC7AsyCcqmgIPQgDjRuJ2rmZORe6AdFV04vWrgA==")
      , ( "171c3797bf0afbbfca4a7bbba7602a2b552746876517a7f9b7ce2db0ae7b"
        , "C4ODPF57BL537SSKPO52OYBKFNKSORUHMUL2P6NXZYW3BLT3"
        , "5daZNVMeTfSuCvu7rBKsFkzEMebnuGjNpos1ThF1c"
        , "Fxw3l78K+7/KSnu7p2AqK1UnRodlF6f5t84tsK57")
      , ( "4040a71079d42853dea26e453004338670a53814b78137ffbed07603a41d76a483aa9bc33b582f77d30a65e6f29a896c0411f38312e1d66e0bf16386c86a89bea572"
        , "IBAKOEDZ2QUFHXVCNZCTABBTQZYKKOAUW6ATP7562B3AHJA5O2SIHKU3YM5VQL3X2MFGLZXSTKEWYBAR6OBRFYOWNYF7CY4GZBVITPVFOI======"
        , "S2XUqUDxz3MHMZtJpCZKt5oRjXHQ34gsyDBT759qNwoSP9rDBHVHxjQUQtXfExotxTqf4rMEXQkNmXE3N9mhoZX6wK"
        , "QECnEHnUKFPeom5FMAQzhnClOBS3gTf/vtB2A6QddqSDqpvDO1gvd9MKZebymolsBBHzgxLh1m4L8WOGyGqJvqVy")
      , ( "4120f308fc02ce9172ad02a7d75800ecfc027109bc67987ea32aba9b8dcc7b10150e"
        , "IEQPGCH4ALHJC4VNAKT5OWAA5T6AE4IJXRTZQ7VDFK5JXDOMPMIBKDQ="
        , "2UPuEK7FVakwP3yUak5jKQhZb6pgpbcqYoRZ2tDzgeCfVr5"
        , "QSDzCPwCzpFyrQKn11gA7PwCcQm8Z5h+oyq6m43MexAVDg==")
      ]

