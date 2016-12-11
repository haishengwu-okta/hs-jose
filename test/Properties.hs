-- Copyright (C) 2015, 2016  Fraser Tweedale
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# LANGUAGE ScopedTypeVariables #-}

module Properties where

import Control.Applicative
import Control.Monad.Except (runExceptT)
import Data.Functor.Identity

import Data.Aeson
import qualified Data.ByteString as B

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck.Monadic
import Test.QuickCheck.Instances ()

import Crypto.JOSE.Error (Error)
import Crypto.JOSE.Types
import Crypto.JOSE.JWK
import Crypto.JOSE.JWS

properties = testGroup "Properties"
  [ testProperty "SizedBase64Integer round-trip"
    (prop_roundTrip :: SizedBase64Integer -> Bool)
  , testProperty "JWK round-trip" (prop_roundTrip :: JWK -> Bool)
  , testProperty "RSA gen, sign and verify" prop_rsaSignAndVerify
  , testProperty "gen, sign with best alg, verify" prop_bestJWSAlg
  ]

prop_roundTrip :: (Eq a, ToJSON a, FromJSON a) => a -> Bool
prop_roundTrip a = decode (encode [a]) == Just [a]

debugRoundTrip
  :: (Show a, Arbitrary a, ToJSON a, FromJSON a)
  => (a -> Bool)
  -> Property
debugRoundTrip f = monadicIO $ do
  a :: a <- pick arbitrary
  let encoded = encode [a]
  monitor $ counterexample $
    "JSON: \n" ++ show encoded ++ "\n\nDecoded: \n" ++ show (decode encoded :: Maybe [a])
  assert $ f a

prop_rsaSignAndVerify :: B.ByteString -> Property
prop_rsaSignAndVerify msg = monadicIO $ do
  keylen <- pick $ elements ((`div` 8) <$> [2048, 3072, 4096])
  k :: JWK <- run $ genJWK (RSAGenParam keylen)
  alg <- pick $ elements [RS256, RS384, RS512, PS256, PS384, PS512]
  monitor (collect alg)
  let
    h = newJWSHeader (Protected, alg)
    go = do
      jws :: JWS Identity JWSHeader <- newJWS k h msg
      verifyJWS defaultValidationSettings k jws
  wp (runExceptT go) checkSignVerifyResult

prop_bestJWSAlg :: B.ByteString -> Property
prop_bestJWSAlg msg = monadicIO $ do
  genParam <- pick arbitrary
  k <- run $ genJWK genParam
  case bestJWSAlg k of
    Left (_ :: Error) -> assert False
    Right alg -> do
      monitor (collect alg)
      let
        h = newJWSHeader (Protected, alg)
        go = do
          jws :: JWS Identity JWSHeader <- newJWS k h msg
          verifyJWS defaultValidationSettings k jws
      wp (runExceptT go) checkSignVerifyResult

checkSignVerifyResult :: Monad m => Either Error a -> PropertyM m ()
checkSignVerifyResult = assert . either (const False) (const True)
