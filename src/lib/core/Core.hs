{-*-----------------------------------------------------------------------
  The Core Assembler.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
-----------------------------------------------------------------------*-}

-- $Id$

module Core ( module Module
            , CoreModule, CoreValue
            , Expr(..), Note(..), Binds(..), Recs, Bind(..)
            , Alts, Alt(..), Pat(..), Literal(..)

            , patBinders
            , listFromBinds, unzipBinds, binders, mapBinds
            , mapAccumBinds, mapAccum, zipBindsWith, mapAlts, zipAltsWith
            , mapExprWithSupply, mapExpr
            ) where

import Byte   ( Bytes )
import Id     ( Id, NameSupply, mapWithSupply )
import Module
import IdMap  ( IdMap, filterMap )
import IdSet  ( IdSet, emptySet, setFromMap, setFromList )

----------------------------------------------------------------
-- Modules
----------------------------------------------------------------
type CoreModule = Module Expr
type CoreValue  = DValue Expr

----------------------------------------------------------------
-- Core expressions:
----------------------------------------------------------------
data Expr       = Let       Binds Expr
                | Case      Expr  Id Alts
                | Ap        { expr1::Expr, expr2::Expr }
                | Lam       Id Expr
                | Con       Id
                | Var       Id
                | Lit       { lit::Literal }
                | Note      Note Expr

data Note       = FreeVar   IdSet


data Binds      = Rec       Recs
                | NonRec    Bind
type Recs       = [Bind]
data Bind       = Bind      {bindId::Id, bindExpr::Expr}

type Alts       = [Alt]
data Alt        = Alt       {pat::Pat, altExpr::Expr}


data Pat        = PatCon     Id [Id]
                | PatLit     {patLit::Literal}
                | PatDefault

data Literal    = LitInt    Int
                | LitDouble Double
                | LitBytes  Bytes


----------------------------------------------------------------
-- Common functions
----------------------------------------------------------------
patBinders pat
  = case pat of
      PatCon id ids -> setFromList ids
      other         -> emptySet

listFromBinds :: Binds -> [Bind]
listFromBinds binds
  = case binds of
      NonRec bind -> [bind]
      Rec recs    -> recs

binders :: Binds -> [Id]
binders binds
  = map (\(Bind id rhs) -> id) (listFromBinds binds)

unzipBinds :: [Bind] -> ([Id],[Expr])
unzipBinds binds
  = unzip (map (\(Bind id rhs) -> (id,rhs)) binds)

mapBinds :: (Id -> Expr -> Bind) -> Binds -> Binds
mapBinds f binds
  = case binds of
      NonRec (Bind id rhs)
        -> NonRec (f id rhs)
      Rec recs
        -> Rec (map (\(Bind id rhs) -> f id rhs) recs)

mapAccumBinds :: (a -> Id -> Expr -> (Bind,a)) -> a -> Binds -> (Binds,a)
mapAccumBinds f x binds
  = case binds of
      NonRec (Bind id rhs)
        -> let (bind,y) = f x id rhs
           in  (NonRec bind, y)
      Rec recs
        -> let (recs',z) = mapAccum (\x (Bind id rhs) -> f x id rhs) x recs
           in  (Rec recs',z)

mapAccum               :: (a -> b -> (c,a)) -> a -> [b] -> ([c],a)
mapAccum f s []         = ([],s)
mapAccum f s (x:xs)     = (y:ys,s'')
                         where (y,s' )  = f s x
                               (ys,s'') = mapAccum f s' xs


zipBindsWith :: (a -> Id -> Expr -> Bind) -> [a] -> Binds -> Binds
zipBindsWith f (x:xs) (NonRec (Bind id rhs))
  = NonRec (f x id rhs)
zipBindsWith f xs (Rec recs)
  = Rec (zipWith (\x (Bind id rhs) -> f x id rhs) xs recs)


mapAlts :: (Pat -> Expr -> Alt) -> Alts -> Alts
mapAlts f alts
  = map (\(Alt pat expr) -> f pat expr) alts

zipAltsWith :: (a -> Pat -> Expr -> Alt) -> [a] -> Alts -> Alts
zipAltsWith f xs alts
  = zipWith (\x (Alt pat expr) -> f x pat expr) xs alts


----------------------------------------------------------------
--
----------------------------------------------------------------
mapExprWithSupply :: (NameSupply -> Expr -> Expr) -> NameSupply -> CoreModule -> CoreModule
mapExprWithSupply f supply mod
  = mod{ values = mapWithSupply fvalue supply (values mod) }
  where
    fvalue supply (id,value) = (id,value{ valueValue = f supply (valueValue value)})

mapExpr :: (Expr -> Expr) -> CoreModule -> CoreModule
mapExpr f mod
  = mapValues f mod