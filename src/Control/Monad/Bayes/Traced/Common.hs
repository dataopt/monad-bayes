-- |
-- Module      : Control.Monad.Bayes.Traced.Common
-- Description : Numeric code for Trace MCMC
-- Copyright   : (c) Adam Scibior, 2015-2020
-- License     : MIT
-- Maintainer  : leonhard.markert@tweag.io
-- Stability   : experimental
-- Portability : GHC
module Control.Monad.Bayes.Traced.Common
  ( Trace,
    singleton,
    output,
    scored,
    bind,
    mhTrans,
    mhTransFree,
    mhTrans',
    burnIn,
  )
where

import Control.Monad.Bayes.Class
  ( MonadSample (bernoulli, random),
    discrete,
  )
import qualified Control.Monad.Bayes.Density.Free as Free
import Control.Monad.Bayes.Density.State
import Control.Monad.Bayes.Weighted as Weighted
  ( Weighted,
    hoist,
    weighted,
  )
import Control.Monad.Trans.Writer (WriterT (WriterT, runWriterT))
import Data.Functor.Identity (Identity (runIdentity))
import Numeric.Log (Log, ln)
import Statistics.Distribution.DiscreteUniform (discreteUniformAB)

-- | Collection of random variables sampler during the program's execution.
data Trace a = Trace
  { -- | Sequence of random variables sampler during the program's execution.
    variables :: [Double],
    --
    output :: a,
    -- | The probability of observing this particular sequence.
    probDensity :: Log Double
  }

instance Functor Trace where
  fmap f t = t {output = f (output t)}

instance Applicative Trace where
  pure x = Trace {variables = [], output = x, probDensity = 1}
  tf <*> tx =
    Trace
      { variables = variables tf ++ variables tx,
        output = output tf (output tx),
        probDensity = probDensity tf * probDensity tx
      }

instance Monad Trace where
  t >>= f =
    let t' = f (output t)
     in t' {variables = variables t ++ variables t', probDensity = probDensity t * probDensity t'}

singleton :: Double -> Trace Double
singleton u = Trace {variables = [u], output = u, probDensity = 1}

scored :: Log Double -> Trace ()
scored w = Trace {variables = [], output = (), probDensity = w}

bind :: Monad m => m (Trace a) -> (a -> m (Trace b)) -> m (Trace b)
bind dx f = do
  t1 <- dx
  t2 <- f (output t1)
  return $ t2 {variables = variables t1 ++ variables t2, probDensity = probDensity t1 * probDensity t2}

-- | A single Metropolis-corrected transition of single-site Trace MCMC.
mhTrans :: MonadSample m => (Weighted (Density m)) a -> Trace a -> m (Trace a)
mhTrans m t@Trace {variables = us, probDensity = p} = do
  let n = length us
  us' <- do
    i <- discrete $ discreteUniformAB 0 (n - 1)
    u' <- random
    case splitAt i us of
      (xs, _ : ys) -> return $ xs ++ (u' : ys)
      _ -> error "impossible"
  ((b, q), vs) <- density (weighted m) us' -- runWriterT $ runWeighted $ Weighted.hoist (WriterT . density us') m
  let ratio = (exp . ln) $ min 1 (q * fromIntegral n / (p * fromIntegral (length vs)))
  accept <- bernoulli ratio
  return $ if accept then Trace vs b q else t

-- | A single Metropolis-corrected transition of single-site Trace MCMC.
mhTransFree :: MonadSample m => (Weighted (Free.Density m)) a -> Trace a -> m (Trace a)
mhTransFree m t@Trace {variables = us, probDensity = p} = do
  let n = length us
  us' <- do
    i <- discrete $ discreteUniformAB 0 (n - 1)
    u' <- random
    case splitAt i us of
      (xs, _ : ys) -> return $ xs ++ (u' : ys)
      _ -> error "impossible"
  ((b, q), vs) <- runWriterT $ weighted $ Weighted.hoist (WriterT . Free.density us') m
  let ratio = (exp . ln) $ min 1 (q * fromIntegral n / (p * fromIntegral (length vs)))
  accept <- bernoulli ratio
  return $ if accept then Trace vs b q else t

-- | A variant of 'mhTrans' with an external sampling monad.
mhTrans' :: MonadSample m => Weighted (Free.Density Identity) a -> Trace a -> m (Trace a)
mhTrans' m = mhTransFree (Weighted.hoist (Free.hoist (return . runIdentity)) m)

-- | burn in an MCMC chain for n steps (which amounts to dropping samples of the end of the list)
burnIn :: Functor m => Int -> m [a] -> m [a]
burnIn n = fmap dropEnd
  where
    dropEnd ls = let len = length ls in take (len - n) ls
