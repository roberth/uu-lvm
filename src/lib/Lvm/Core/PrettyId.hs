{------------------------------------------------------------------------
  The Core Assembler.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
------------------------------------------------------------------------}

--  $Id$

module Lvm.Core.PrettyId ( ppId, ppVarId, ppConId, ppQualId, ppQualCon, ppString ) where

import Data.Char     ( isAlphaNum, isAlpha, isLower, isUpper )
import Text.PrettyPrint.Leijen
import Lvm.Common.Id       ( Id, stringFromId, idFromString )
import Lvm.Common.IdSet    ( IdSet, setFromList, elemSet )

ppId :: Id -> Doc
ppId = ppEscapeId isAlpha quoted

ppVarId :: Id -> Doc
ppVarId = ppEscapeId isLower quoted

ppConId :: Id -> Doc
ppConId = ppEscapeId isUpper (quoted . (':' :))

ppQualId :: Id -> Id -> Doc
ppQualId x y = pretty x <> dot <> ppVarId y

ppQualCon :: Id -> Id -> Doc
ppQualCon x y = pretty x <> dot <> ppConId y

quoted :: String -> String
quoted s = "''" ++ s ++ "''"

ppString :: String -> Doc
ppString s
  = dquotes (text (concatMap escape s))

ppEscapeId :: (Char -> Bool) -> (String -> String) -> Id -> Doc
ppEscapeId isValid esc x
  = if not (isReserved x) && firstOk && ordinary
     then text name
     else text (esc (concatMap escapeId name)) <> char ' '
  where
    name     = stringFromId x
    firstOk  = case name of
                 []  -> False
                 y:_ -> isValid y
    ordinary = all idchar name
    
idchar :: Char -> Bool
idchar c = isAlphaNum c || c == '_' || c == '\''
    
escapeId :: Char -> String
escapeId ' ' = "\\s"
escapeId c   = escape c

escape :: Char -> String
escape c
  = case c of
      -- '.'   -> "\\."
      '\a'  -> "\\a"
      '\b'  -> "\\b"
      '\f'  -> "\\f"
      '\n'  -> "\\n"
      '\r'  -> "\\r"
      '\t'  -> "\\t"
      '\v'  -> "\\v"
      '\\'  -> "\\\\"
      '\"'  -> "\\\""
      '\''  -> "\\'"
      _     -> [c]


isReserved :: Id -> Bool
isReserved = (`elemSet` reserved)
  
reserved :: IdSet
reserved
  = setFromList $ map idFromString
    ["module","where"
    ,"import","abstract","extern"
    ,"custom","val","con"
    ,"match","with"
    ,"let","rec","in"
    ,"static","dynamic","runtime"
    ,"stdcall","ccall","instruction"
    ,"decorate"
    ,"private","public","nothing"
    ,"type","data","forall","exist"
    ,"case","of"
    ,"if","then","else"
    ]