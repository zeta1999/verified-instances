{-@ LIQUID "--higherorder"     @-}
{-@ LIQUID "--totality"        @-}
{-@ LIQUID "--prune-unsorted"  @-}

module Data.VerifiedEq where

-- import Data.Nat
-- import Data.List
import Language.Haskell.Liquid.ProofCombinators

{-@ data VerifiedEq a = VerifiedEq {
      eq :: x:a -> y:a -> {v:Bool | Prop v <=> x == y }
    , refl :: x:a -> { x == x }
    , sym :: x:a -> y:a -> { (x == y) ==> (y == x) }
    , trans :: x:a -> y:a -> z:a -> { (x == y) && (y == z) ==> (y == x) }
    }
@-}
data VerifiedEq a = VerifiedEq {
    eq :: a -> a -> Bool
  , refl :: a -> Proof
  , sym :: a -> a -> Proof
  , trans :: a -> a -> a -> Proof
}

{-@ eqIntRefl :: x:Int -> { x == x } @-}
eqIntRefl :: Int -> Proof
eqIntRefl x = simpleProof

{-@ eqIntSym :: x:Int -> y:Int -> { x == y ==> y == x } @-}
eqIntSym :: Int -> Int -> Proof
eqIntSym x y = simpleProof

{-@ eqIntTrans :: x:Int -> y:Int -> z:Int -> { x == y && y == z ==> x == z } @-}
eqIntTrans :: Int -> Int -> Int -> Proof
eqIntTrans x y z = simpleProof

veqInt :: VerifiedEq Int
veqInt = VerifiedEq (==) eqIntRefl eqIntSym eqIntTrans

-- veqN :: VerifiedEq N
-- veqN = VerifiedEq eqN eqNRefl eqNSym eqNTrans

-- veqList :: Eq a => VerifiedEq (List a)
-- veqList = VerifiedEq eqList eqListRefl eqListSym eqListTrans
