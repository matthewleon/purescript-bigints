module Test.Main where

import Prelude hiding (not)

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Eff.Random (RANDOM)
import Data.Array (filter, range)
import Data.BigInt (BigInt, abs, and, even, fromBase, fromInt, fromNumber, fromString, not, odd, or, pow, prime, shl, shr, toBase, toBase', toNonEmptyString, toNumber, toString, xor)
import Data.Foldable (fold)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.NonEmpty ((:|))
import Data.String.NonEmpty (unsafeFromString)
import Data.String.NonEmpty as NES
import Partial.Unsafe (unsafePartial)
import Test.Assert (ASSERT, assert)
import Test.QuickCheck (QC, quickCheck)
import Test.QuickCheck.Arbitrary (class Arbitrary)
import Test.QuickCheck.Gen (Gen, arrayOf, chooseInt, elements, resize)
import Test.QuickCheck.Laws.Data as Data
import Type.Proxy (Proxy(..))


-- | Newtype with an Arbitrary instance that generates only small integers
newtype SmallInt = SmallInt Int

instance arbitrarySmallInt :: Arbitrary SmallInt where
  arbitrary = SmallInt <$> chooseInt (-5) 5

runSmallInt :: SmallInt -> Int
runSmallInt (SmallInt n) = n

-- | Arbitrary instance for BigInt
newtype TestBigInt = TestBigInt BigInt
derive newtype instance eqTestBigInt :: Eq TestBigInt
derive newtype instance ordTestBigInt :: Ord TestBigInt
derive newtype instance semiringTestBigInt :: Semiring TestBigInt
derive newtype instance ringTestBigInt :: Ring TestBigInt
derive newtype instance commutativeRingTestBigInt :: CommutativeRing TestBigInt
derive newtype instance euclideanRingTestBigInt :: EuclideanRing TestBigInt

instance arbitraryBigInt :: Arbitrary TestBigInt where
  arbitrary = do
    n <- (fromMaybe zero <<< fromString) <$> digitString
    op <- elements (id :| [negate])
    pure (TestBigInt (op n))
    where digits :: Gen Int
          digits = chooseInt 0 9
          digitString :: Gen String
          digitString = (fold <<< map show) <$> (resize 50 $ arrayOf digits)

-- | Convert SmallInt to BigInt
fromSmallInt :: SmallInt -> BigInt
fromSmallInt = fromInt <<< runSmallInt

-- | Test if a binary relation holds before and after converting to BigInt.
testBinary :: forall eff. (BigInt -> BigInt -> BigInt)
           -> (Int -> Int -> Int)
           -> QC eff Unit
testBinary f g = quickCheck (\x y -> (fromInt x) `f` (fromInt y) == fromInt (x `g` y))

main :: forall eff. Eff (console :: CONSOLE, assert :: ASSERT, random :: RANDOM, exception :: EXCEPTION | eff) Unit
main = do
  log "Simple arithmetic operations and conversions from Int"
  let two = one + one
  let three = two + one
  let four = three + one
  assert $ fromInt 3 == three
  assert $ two * two == four
  assert $ two * three * (three + four) == fromInt 42
  assert $ two - three == fromInt (-1)

  log "Parsing strings"
  assert $ fromString "2" == Just two
  assert $ fromString "a" == Nothing
  assert $ fromString "2.1" == Nothing
  assert $ fromString "123456789" == Just (fromInt 123456789)
  assert $ fromString "1e7" == Just (fromInt 10000000)
  quickCheck $ \(TestBigInt a) -> (fromString <<< toString) a == Just a

  log "Parsing strings with a different base"
  assert $ fromBase 2 "100" == Just four
  assert $ fromBase 16 "ff" == fromString "255"

  log "Rendering bigints as strings with a different base"
  assert $ toBase 2 four == "100"
  assert $ (toBase 16 <$> fromString "255") == Just "ff"
  assert $ toString (fromInt 12345) == "12345"

  assert $ toBase' 2 four == unsafePartial unsafeFromString "100"
  assert $ (toBase' 16 <$> fromString "255") == NES.fromString "ff"
  assert $ toNonEmptyString (fromInt 12345)
           == unsafePartial unsafeFromString "12345"

  log "Converting from Number to BigInt"
  assert $ fromNumber 0.0 == zero
  assert $ fromNumber 3.4 == three
  assert $ fromNumber (-3.9) == -three
  assert $ fromNumber 1.0e7 == fromInt 10000000
  assert $ Just (fromNumber 1.0e47) == fromString "1e47"
  quickCheck (\x -> fromInt x == fromNumber (Int.toNumber x))

  log "Conversions between String, Int and BigInt should not loose precision"
  quickCheck (\n -> fromString (show n) == Just (fromInt n))
  quickCheck (\n -> Int.toNumber n == toNumber (fromInt n))

  log "Binary relations between integers should hold before and after converting to BigInt"
  testBinary (+) (+)
  testBinary (-) (-)
  testBinary (/) (/)
  testBinary mod mod
  testBinary div div

  -- To test the multiplication, we need to make sure that Int does not overflow
  quickCheck (\x y -> fromSmallInt x * fromSmallInt y == fromInt (runSmallInt x * runSmallInt y))

  log "It should perform multiplications which would lead to imprecise results using Number"
  assert $ Just (fromInt 333190782 * fromInt 1103515245) == fromString "367681107430471590"

  log "compare, (==), even, odd should be the same before and after converting to BigInt"
  quickCheck (\x y -> compare x y == compare (fromInt x) (fromInt y))
  quickCheck (\x y -> (fromSmallInt x == fromSmallInt y) == (runSmallInt x == runSmallInt y))
  quickCheck (\x -> Int.even x == even (fromInt x))
  quickCheck (\x -> Int.odd x == odd (fromInt x))

  log "pow should perform integer exponentiation and yield 0 for negative exponents"
  assert $ three `pow` four == fromInt 81
  assert $ three `pow` -two == zero
  assert $ three `pow` zero == one
  assert $ zero `pow` zero == one

  log "Prime numbers"
  assert $ filter (prime <<< fromInt) (range 2 20) == [2, 3, 5, 7, 11, 13, 17, 19]

  log "Absolute value"
  quickCheck $ \(TestBigInt x) -> abs x == if x > zero then x else (-x)

  log "Logic"
  assert $ (not <<< not) one == one
  assert $ or one three == three
  assert $ xor one three == two
  assert $ and one three == one

  log "Shifting"
  assert $ shl two one == four
  assert $ shr two one == one

  let prxBigInt = Proxy ∷ Proxy TestBigInt
  Data.checkEq prxBigInt
  Data.checkOrd prxBigInt
  Data.checkSemiring prxBigInt
  Data.checkRing prxBigInt
--  Data.checkEuclideanRing prxBigInt
  Data.checkCommutativeRing prxBigInt
