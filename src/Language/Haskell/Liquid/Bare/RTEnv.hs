{-# LANGUAGE TupleSections #-}

module Language.Haskell.Liquid.Bare.RTEnv ( makeRTEnv ) where

import Prelude hiding (error)

import Data.Graph hiding (Graph)
import Data.Maybe

import qualified Control.Exception   as Ex
import qualified Data.HashMap.Strict as M
import qualified Data.List           as L

import           Language.Fixpoint.Misc (fst3)
import           Language.Fixpoint.Types (Expr(..), Symbol, symbol) -- , tracepp)
import           Language.Haskell.Liquid.GHC.Misc (sourcePosSrcSpan)
import           Language.Haskell.Liquid.Types.RefType (symbolRTyVar)
import           Language.Haskell.Liquid.Types
import qualified Language.Haskell.Liquid.Measure as Ms
import           Language.Haskell.Liquid.Bare.Env
import           Language.Haskell.Liquid.Bare.Expand
import           Language.Haskell.Liquid.Bare.OfType
import           Language.Haskell.Liquid.Bare.Resolve

--------------------------------------------------------------------------------
-- | `makeRTEnv` initializes the env needed to `expand` refinements and types,
--   that is, the below needs to be called *before* we use `Expand.expand`
--------------------------------------------------------------------------------
makeRTEnv :: ModName
          -> Ms.BareSpec
          -> [(ModName, Ms.BareSpec)]
          -> M.HashMap Symbol LMap
          -> BareM ()
--------------------------------------------------------------------------------
makeRTEnv m lfSpec specs lm = do
  makeREAliases (eAs ++ eAs' ++ eAs'')
  makeRTAliases tAs
  where
    tAs   = [ (m, t) | (m, s)  <- specs,           t <- Ms.aliases   s ]
    eAs   = [ (m, e) | (m, s)  <- specs,           e <- Ms.ealiases  s ]
    eAs'  = [ (m, e) | e       <- Ms.ealiases lfSpec                   ]
    eAs'' = [ (m, e) | (_, xl) <- M.toList lm, let e  = lmapEAlias  xl ]

makeRTAliases :: [(ModName, RTAlias Symbol BareType)] -> BareM ()
makeRTAliases = graphExpand buildTypeEdges expBody
  where
    expBody (m, xt) = inModule m $ do
      let l  = rtPos  xt
      let l' = rtPosE xt
      body  <- withVArgs l l' (rtVArgs xt) $ ofBareType l $ rtBody xt
      setRTAlias (rtName xt) $ mapRTAVars symbolRTyVar $ xt { rtBody = body }

makeREAliases :: [(ModName, RTAlias Symbol Expr)] -> BareM ()
makeREAliases
  = graphExpand buildExprEdges expBody
  where
    expBody (mod, xt)
      = inModule mod $
          do let l  = rtPos  xt
             let l' = rtPosE xt
             body  <- withVArgs l l' (rtVArgs xt) $ resolve l =<< expand (rtBody xt)
             setREAlias (rtName xt) $ xt { rtBody = body }


graphExpand :: (PPrint t)
            => (AliasTable t -> t -> [Symbol])
            -> ((ModName, RTAlias Symbol t) -> BareM b)
            -> [(ModName, RTAlias Symbol t)]
            -> BareM ()
graphExpand buildEdges expBody xts
  = do let table = buildAliasTable xts
           graph = buildAliasGraph (buildEdges table) (map snd xts)
       checkCyclicAliases table graph
       mapM_ expBody $ genExpandOrder table graph

--------------------------------------------------------------------------------

type AliasTable t = M.HashMap Symbol (ModName, RTAlias Symbol t)

buildAliasTable :: [(ModName, RTAlias Symbol t)] -> AliasTable t
buildAliasTable
  = M.fromList . map (\(m, rta) -> (rtName rta, (m, rta)))

fromAliasSymbol :: AliasTable t -> Symbol -> (ModName, RTAlias Symbol t)
fromAliasSymbol table sym
  = fromMaybe err $ M.lookup sym table
  where
    err = panic Nothing $ "fromAliasSymbol: Dangling alias symbol: " ++ show sym


type Graph t = [Node t]
type Node  t = (t, t, [t])

buildAliasGraph :: (PPrint t) => (t -> [Symbol]) -> [RTAlias Symbol t] -> Graph Symbol
buildAliasGraph buildEdges
  = map (buildAliasNode buildEdges)

buildAliasNode :: (PPrint t) => (t -> [Symbol]) -> RTAlias Symbol t -> Node Symbol
buildAliasNode buildEdges alias
  = (rtName alias, rtName alias, buildEdges $ rtBody alias)

checkCyclicAliases :: AliasTable t -> Graph Symbol -> BareM ()
checkCyclicAliases table graph
  = case mapMaybe go $ stronglyConnComp graph of
      []   -> return ()
      sccs -> Ex.throw (cycleAliasErr table <$> sccs)
    where
      go (CyclicSCC vs) = Just vs
      go (AcyclicSCC _) = Nothing

cycleAliasErr :: AliasTable t -> [Symbol] -> Error
cycleAliasErr _ []          = panic Nothing "checkCyclicAliases: No type aliases in reported cycle"
cycleAliasErr t scc@(rta:_) = ErrAliasCycle { pos    = fst (locate rta)
                                            , acycle = map locate scc }
  where
    locate sym = ( sourcePosSrcSpan $ rtPos $ snd $ fromAliasSymbol t sym
                 , pprint sym )


genExpandOrder :: AliasTable t -> Graph Symbol -> [(ModName, RTAlias Symbol t)]
genExpandOrder table graph
  = map (fromAliasSymbol table) symOrder
  where
    (digraph, lookupVertex, _)
      = graphFromEdges graph
    symOrder
      = map (fst3 . lookupVertex) $ reverse $ topSort digraph

--------------------------------------------------------------------------------

ordNub :: Ord a => [a] -> [a]
ordNub = map head . L.group . L.sort

buildTypeEdges :: AliasTable BareType -> BareType -> [Symbol]
buildTypeEdges table = ordNub . go
  where
    go :: BareType -> [Symbol]
    go (RApp c ts rs _) = go_alias (symbol c) ++ concatMap go ts ++ concatMap go (mapMaybe go_ref rs)
    go (RFun _ t1 t2 _) = go t1 ++ go t2
    go (RAppTy t1 t2 _) = go t1 ++ go t2
    go (RAllE _ t1 t2)  = go t1 ++ go t2
    go (REx _ t1 t2)    = go t1 ++ go t2
    go (RAllT _ t)      = go t
    go (RAllP _ t)      = go t
    go (RAllS _ t)      = go t
    go (RVar _ _)       = []
    go (RExprArg _)     = []
    go (RHole _)        = []
    go (RRTy env _ _ t) = concatMap (go . snd) env ++ go t
    go_alias c          = [c | M.member c table]
    -- case M.lookup c table of
    --                         Just _  -> [c]
    --                         Nothing -> [ ]

    go_ref (RProp _ (RHole _)) = Nothing
    go_ref (RProp  _ t) = Just t


buildExprEdges :: M.HashMap Symbol a -> Expr -> [Symbol]
buildExprEdges table  = ordNub . go
  where
    go :: Expr -> [Symbol]
    go (EApp e1 e2)   = go e1 ++ go e2
    go (ENeg e)       = go e
    go (EBin _ e1 e2) = go e1 ++ go e2
    go (EIte _ e1 e2) = go e1 ++ go e2
    go (ECst e _)     = go e

    go (ESym _)       = []
    go (ECon _)       = []
    go (EVar v)       = go_alias v

    go (PAnd ps)           = concatMap go ps
    go (POr ps)            = concatMap go ps
    go (PNot p)            = go p
    go (PImp p q)          = go p ++ go q
    go (PIff p q)          = go p ++ go q
    go (PAll _ p)          = go p
    go (ELam _ e)          = go e

    go (PAtom _ e1 e2)     = go e1 ++ go e2

    go (ETApp e _)         = go e
    go (ETAbs e _)         = go e
    go (PKVar _ _)         = []
    go (PExist _ e)        = go e
    go (PGrad _ _ _ e)     = go e

    go_alias f           = [f | M.member f table ]
