{-@ LIQUID "--higherorder" @-}
{-# LANGUAGE BangPatterns #-}
#!/usr/bin/env stack
-- stack --resolver lts-6.20 --install-ghc runghc --package containers

-- |

module Control.SimplePar
    ( new,put,get
    , IVar, Par
    , main, err, deadlock, loop, dag
    )
    where

import Control.Monad
import Control.Monad.Except
import Data.IntMap as M hiding (fromList)
import Data.List as L


--------------------------------------------------------------------------------

-- Full version:
-- data Trace = forall a . Get (IVar a) (a -> Trace)
--            | forall a . Put (IVar a) a Trace
--            | forall a . New (IVarContents a) (IVar a -> Trace)
--            | Fork Trace Trace
--            | Done
--            | Yield Trace
--            | forall a . LiftIO (IO a) (a -> Trace)


-- | Restricted version:
data Trace = Get (IVar Val) (Val -> Trace)
           | Put (IVar Val) Val Trace
           | New (IVar Val -> Trace)
           | Fork Trace Trace
           | Done


-- | Hack: hardcode all IVar values to Double:
type Val = Double

-- newtype IVar a = IVar (IORef (IVarContents a))

-- | An IVar is an index into an IntMap
data IVar a = IVar Int

type Heap = M.IntMap (Maybe Val)

-- User-facing API:
--------------------------------------------------------------------------------

new :: Par (IVar Val)
new  = Par New

get :: IVar Val -> Par Val
get v = Par $ \c -> Get v c

put :: IVar Val -> Val -> Par ()
put v a = Par $ \c -> Put v a (c ())

fork :: Par () -> Par ()
-- Child thread executes with no continuation:
fork (Par k1) = Par (\k2 -> Fork (k1 (\() -> Done)) (k2 ()))

--------------------------------------------------------------------------------

newtype Par a = Par {
    -- A par computation takes a continuation and generates a trace
    -- incorporating it.
    runCont :: (a -> Trace) -> Trace
}

instance Functor Par where
    fmap f m = Par $ \c -> runCont m (c . f)

instance Applicative Par where
   (<*>) = ap
   -- Par ff <*> Par fa = Par (\bcont -> fa (\ a -> ff (\ ab -> bcont (ab a))))
   pure a = Par ($ a)

instance Monad Par where
    return = pure
    m >>= k  = Par $ \c -> runCont m $ \a -> runCont (k a) c


data InfList a = Cons a (InfList a)

fromList :: [a] -> InfList a
fromList (a:b) = Cons a (fromList b)
fromList [] = error "fromList: cannot convert finite list to infinite list!"

--------------------------------------------------------------------------------
-- The scheduler itself
--------------------------------------------------------------------------------

-- Goal: Prove that every schedule is equivalent to a canonical schedule:
-- Theorem: forall p l1 . runPar l1 p == runPar (repeat 0) p

-- | Exception thrown by runPar
data Exn = MultiplePut Val Int Val
         | Deadlock (M.IntMap [Val -> Trace])

instance Show Exn where
  show (MultiplePut v ix v0) =
    "multiple put, attempt to put " ++ show v ++ " to IVar " ++
    show ix ++ " already containing " ++ show v0
  show (Deadlock blkd) =
    "no runnable threads, but " ++ show (sum (L.map length (M.elems blkd))) ++
    " thread(s) blocked on these IVars: " ++ show (M.keys blkd)

-- we can syntactically describe parallel evaluation contexts if we like:
--   fork (a1 >>= k1) (a2 >>= k2)

-- lemma: the heap is used linearly and grows monotonically towards deterministic final state

-- noninteference lemma:  i /= j  =>  get (IVar i) # put (IVar j) v



-- | Run a Par computation.  Take a stream of random numbers for scheduling decisions.
runPar :: InfList Word -> Par Val -> Except Exn Val
runPar randoms p = do
  let initHeap = M.singleton 0 Nothing
      initThreads :: [Trace]
      initThreads = [runCont p (\v -> Put (IVar 0) v Done)]

  finalHeap <- sched randoms initThreads M.empty 1 initHeap
  let Just finalVal = finalHeap M.! 0
  return finalVal

  where
    sched :: InfList Word -> [Trace] -> M.IntMap [Val -> Trace] -> Int -> Heap -> Except Exn Heap
    sched _ [] blkd _ heap = do
      if M.null blkd
        then return heap
        else throwError $ Deadlock blkd

    sched (Cons rnd rs) threads blkd cntr heap = do
      (thrds', blkd', cntr', heap') <- step (yank rnd threads) blkd cntr heap
      sched rs thrds' blkd' cntr' heap'

    step :: (Trace, [Trace]) -> IntMap [Val -> Trace] -> Int -> IntMap (Maybe Val) -> Except Exn ([Trace], IntMap [Val -> Trace], Int, IntMap (Maybe Val))
    step (trc, others) blkd cntr heap =
      case trc of
        Done -> return (others, blkd, cntr, heap)
        Fork t1 t2 -> return (t1 : t2 : others, blkd, cntr, heap)
        New k -> return (k (IVar cntr) : others, blkd, cntr + 1, M.insert cntr Nothing heap)
        Get (IVar ix) k ->
          case heap M.! ix of
            Nothing -> return (others, M.insertWith (++) ix [k] blkd, cntr, heap)
            Just v  -> return (k v : others, blkd, cntr, heap)
        Put (IVar ix) v t2 ->
          let heap' = M.insert ix (Just v) heap
          in case heap M.! ix of
            Nothing ->
              case M.lookup ix blkd of
                Nothing -> return (t2 : others, blkd, cntr, heap')
                Just ls -> return (t2 : [ k v | k <- ls ] ++ others
                                 , M.delete ix blkd, cntr, heap')
            Just v0 -> throwError $ MultiplePut v ix v0

    yank n ls = let (hd,x:tl) = splitAt (fromIntegral n `mod` length ls) ls
                in (x, hd++tl)

--------------------------------------------------------------------------------

roundRobin :: InfList Word
roundRobin = fromList [0..]

main :: IO ()
main = do
  print $ runPar roundRobin (return 3.99)

  print $ runPar roundRobin (do v <- new; put v 3.12; get v)

-- TODO: make this into a quickcheck test harness.


-- | Example error
err :: IO ()
err = print $ runPar roundRobin (do v <- new; put v 3.12; put v 4.5; get v)

-- | Example deadlock
deadlock :: IO ()
deadlock = print $ runPar roundRobin (do v <- new; get v)

-- | runPar can be nonterminating of course.
loop :: IO ()
loop = print $ runPar roundRobin (do v <- new; put v 4.1; loopit 0.0 v)

loopit :: Val -> IVar Val -> Par b
loopit !acc vr = do n <- get vr; loopit (acc+n) vr

-- | A program that cannot execute sequentially.
dag :: Par Val
dag = do a <- new
         b <- new
         fork $ do x <- get a
--                 put b 3 -- Control dependence without information flow.
                   put b x -- Control dependence PLUS information flow.
         put a 100
         get b

-- [2016.12.15] Notes from call:
-- Possibly related:
-- "Core calculus of dependency": https://people.mpi-sws.org/~dg/teaching/lis2014/modules/ifc-3-abadi99.pdf
-- Also check out "Partial order reduction" in model checking.
