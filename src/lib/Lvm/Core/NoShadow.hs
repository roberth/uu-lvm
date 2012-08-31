{------------------------------------------------------------------------
  The Core Assembler.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
------------------------------------------------------------------------}

--  $Id$

----------------------------------------------------------------
-- Make all local bindings locally unique.
-- and all local let-bindings globally unique.
--
-- After this pass, no variables shadow each other and let-bound variables
-- are globally unique.
----------------------------------------------------------------
module Lvm.Core.NoShadow( coreNoShadow, coreRename ) where

import Data.Maybe
import Lvm.Common.Id     ( Id, freshIdFromId, NameSupply, splitNameSupply, splitNameSupplies )
import Lvm.Common.IdMap  ( IdMap, emptyMap, lookupMap, extendMap )
import Lvm.Common.IdSet  ( IdSet, emptySet, elemSet, insertSet )
import Lvm.Core.Expr
import Lvm.Core.Utils

----------------------------------------------------------------
-- Environment: name supply, id's in scope & renamed identifiers
----------------------------------------------------------------
data Env  = Env NameSupply IdSet (IdMap Id)

renameBinders :: Env -> [Id] -> (Env, [Id])
renameBinders env bs
  = let (env',bs') = foldl (\(env1,ids) x1 -> renameBinder env1 x1 $ \env2 x2 -> (env2,x2:ids)) (env,[]) bs
    in  (env',reverse bs')

renameLetBinder :: Env -> Id -> (Env -> Id -> a) -> a
renameLetBinder (Env supply inscope renaming) x cont
    = let (x2,supply') = freshIdFromId x supply
          inscope'      = insertSet x inscope
          renaming'     = extendMap x x2 renaming
      in cont (Env supply' inscope' renaming') x2

renameBinder :: Env -> Id -> (Env -> Id -> a) -> a
renameBinder env@(Env supply set m) x cont
  | elemSet x set
      = renameLetBinder env x cont
  | otherwise
      = cont (Env supply (insertSet x set) m) x

renameVar :: Env -> Id -> Id
renameVar (Env _ _ m) x
  = fromMaybe x (lookupMap x m)

splitEnv :: Env -> (Env,Env)
splitEnv (Env supply set m)
  = let (s0,s1) = splitNameSupply supply
    in  (Env s0 set m,Env s1 set m)

splitEnvs :: Env -> [Env]
splitEnvs (Env supply set idmap)
  = map (\s -> Env s set idmap) (splitNameSupplies supply)


----------------------------------------------------------------
-- coreNoShadow: make all local variables locally unique
-- ie. no local variable shadows another variable
----------------------------------------------------------------
coreNoShadow :: NameSupply -> CoreModule -> CoreModule
coreNoShadow = mapExprWithSupply (nsDeclExpr emptySet)

coreRename :: NameSupply -> CoreModule -> CoreModule
coreRename supply m = mapExprWithSupply (nsDeclExpr (globalNames m)) supply m

nsDeclExpr :: IdSet -> NameSupply -> Expr -> Expr
nsDeclExpr inscope supply = nsExpr (Env supply inscope emptyMap)


nsExpr :: Env -> Expr -> Expr
nsExpr env expr
  = case expr of
      Note n e          -> Note n (nsExpr env e)
      Let binds e       -> nsBinds env binds $ \env' binds' ->
                           Let binds' (nsExpr env' e)
      Match x alts      -> Match (renameVar env x) (nsAlts env alts)
      Lam x e           -> renameBinder env x $ \env2 x2 ->
                           Lam x2 (nsExpr env2 e)
      Ap expr1 expr2    -> let (env1,env2) = splitEnv env
                           in  Ap (nsExpr env1 expr1) (nsExpr env2 expr2)
      Var x             -> Var (renameVar env x)
      Con (ConTag e a)  -> Con (ConTag (nsExpr env e) a)
      _                 -> expr

nsBinds :: Env -> Binds -> (Env -> Binds -> a) -> a
nsBinds env binds cont
  = case binds of
      Strict (Bind x rhs)  -> nonrec Strict x rhs
      NonRec (Bind x rhs)  -> nonrec NonRec x rhs
      Rec _                -> rec_
  where
    nonrec make x1 rhs
      = renameLetBinder env x1 $ \env' x2 ->
        cont env' (make (Bind x2 (nsExpr env rhs)))
      
    rec_ 
      = let (binds',env') = mapAccumBinds (\env1 x1 rhs -> renameLetBinder env1 x1 $ \env2 x2 -> (Bind x2 rhs,env2))
                                           env binds
        in cont env' (zipBindsWith (\env1 x1 rhs -> Bind x1 (nsExpr env1 rhs)) (splitEnvs env') binds')

nsAlts :: Env -> Alts -> Alts
nsAlts = zipAltsWith nsAlt . splitEnvs

nsAlt :: Env -> Pat -> Expr -> Alt
nsAlt env pat expr
  = let (pat',env') = nsPat env pat
    in Alt pat' (nsExpr env' expr)

nsPat :: Env -> Pat -> (Pat, Env)
nsPat env pat
  = case pat of
      PatCon con ids -> let (env',ids') = renameBinders env ids
                        in (PatCon con ids',env')
      other          -> (other,env)
