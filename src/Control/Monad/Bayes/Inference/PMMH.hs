{-# LANGUAGE RankNTypes #-}

-- |
-- Module      : Control.Monad.Bayes.Inference.PMMH
-- Description : Particle Marginal Metropolis-Hastings (PMMH)
-- Copyright   : (c) Adam Scibior, 2015-2020
-- License     : MIT
-- Maintainer  : leonhard.markert@tweag.io
-- Stability   : experimental
-- Portability : GHC
--
-- Particle Marginal Metropolis-Hastings (PMMH) sampling.
--
-- Christophe Andrieu, Arnaud Doucet, and Roman Holenstein. 2010. Particle Markov chain Monte Carlo Methods. /Journal of the Royal Statistical Society/ 72 (2010), 269-342. <http://www.stats.ox.ac.uk/~doucet/andrieu_doucet_holenstein_PMCMC.pdf>
module Control.Monad.Bayes.Inference.PMMH
  ( pmmh,
    -- pmmhBayesianModel,
    pmmhBayesianModel,
  )
where

import Control.Monad.Bayes.Class (Bayesian (generative), MonadInfer, MonadSample, latent)
import Control.Monad.Bayes.Inference.MCMC (MCMCConfig, mcmc)
import Control.Monad.Bayes.Inference.SMC (SMCConfig (), smc)
import Control.Monad.Bayes.Population as Pop
  ( Population,
    hoist,
    population,
    pushEvidence,
  )
import Control.Monad.Bayes.Sequential (Sequential)
import Control.Monad.Bayes.Traced.Static (Traced)
import Control.Monad.Bayes.Weighted
import Control.Monad.Trans (lift)
import Numeric.Log (Log)

-- | Particle Marginal Metropolis-Hastings sampling.
pmmh ::
  MonadSample m =>
  MCMCConfig ->
  SMCConfig (Weighted m) ->
  Traced (Weighted m) a1 ->
  (a1 -> Sequential (Population (Weighted m)) a2) ->
  m [[(a2, Log Double)]]
pmmh mcmcConf smcConf param model =
  mcmc
    mcmcConf
    ( param
        >>= population
          . pushEvidence
          . Pop.hoist lift
          . smc smcConf
          . model
    )

-- | Particle Marginal Metropolis-Hastings sampling from a Bayesian model
pmmhBayesianModel ::
  MonadInfer m =>
  MCMCConfig ->
  SMCConfig (Weighted m) ->
  (forall n. MonadInfer n => Bayesian n a1 a2) ->
  m [[(a2, Log Double)]]
pmmhBayesianModel mcmcConf smcConf bm = pmmh mcmcConf smcConf (latent bm) (generative bm)
