{------------------------------------------------------------------------
  The Core Assembler.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
------------------------------------------------------------------------}

--  $Id$

----------------------------------------------------------------
-- Determine which bindings are really recursive and which are not.
-- maintains free variable information & normalised structure
----------------------------------------------------------------
module Lvm.Core.LetSort( coreLetSort ) where

import qualified Data.Graph as G
import qualified Data.Tree  as G
import Lvm.Common.Id       ( Id )
import Lvm.Common.IdSet    ( IdSet, elemSet, foldSet )
import Lvm.Core.Data
import Lvm.Core.Utils


----------------------------------------------------------------
-- coreLetSort
-- pre: [coreFreeVar] all let bindings are annotated with their free variables
--
-- transform a @Rec@ bindings into the smallest @NonRec@ and @Rec@ bindings.
----------------------------------------------------------------
coreLetSort :: CoreModule -> CoreModule
coreLetSort = mapExpr lsExpr

lsExpr :: Expr -> Expr
lsExpr expr
  = case expr of
      Let (Strict (Bind x rhs)) e
        -> Let (Strict (Bind x (lsExpr rhs))) (lsExpr e)
      Let binds e
        -> let bindss = sortBinds binds
           in foldr Let (lsExpr e) bindss
      Match x alts
        -> Match x (lsAlts alts)
      Lam x e
        -> Lam x (lsExpr e)
      Ap e1 e2
        -> Ap (lsExpr e1) (lsExpr e2)
      Con (ConTag tag arity)
        -> Con (ConTag (lsExpr tag) arity)
      Note n e
        -> Note n (lsExpr e)
      _
        -> expr

lsAlts :: Alts -> Alts
lsAlts = mapAlts (\pat -> Alt pat . lsExpr)

----------------------------------------------------------------
-- topological sort let bindings
----------------------------------------------------------------
sortBinds :: Binds -> [Binds]
sortBinds (Rec bindsrec)
  = let binds  = map (\(Bind x rhs) -> (x,rhs)) bindsrec
        names  = zip (map fst binds) [0..]
        edges  = concat (map (depends names) binds)
        sorted = topSort (length names-1) edges
        binds'  = map (map (binds!!)) sorted
        binds'' = map (map (\(x,expr) -> (x,lsExpr expr))) binds'
    in  map toBinding binds'' -- foldr sortLets (lsExpr expr) binds''
sortBinds binds
  = [mapBinds (\x expr -> Bind x (lsExpr expr)) binds]

-- topological sort
topSort :: G.Vertex -> [G.Edge] -> [[G.Vertex]]
topSort n = map G.flatten . G.scc . G.buildG (0, n)

toBinding :: [(Id, Expr)] -> Binds
toBinding [(x,rhs)]
  | not (elemSet x (freeVar rhs)) = NonRec (Bind x rhs)
toBinding binds
  = Rec (map (uncurry Bind) binds)


type Vertex = Int

depends :: [(Id,Vertex)] -> (Id,Expr) -> [(Vertex,Vertex)]
depends names (v,expr)
  = foldSet depend [] (freeVar expr)
  where
    index     = case lookup v names of
                  Just i  -> i
                  Nothing -> error "CoreLetSort.depends: id not in let group??"

    depend x ds   = case lookup x names of
                      Just i  -> (index,i):ds
                      Nothing -> ds

freeVar :: Expr -> IdSet
freeVar expr
  = case expr of
      Note (FreeVar fv) _ -> fv
      _                   -> error "CoreLetSort.freeVar: no annotation. Do coreFreeVar first?"
