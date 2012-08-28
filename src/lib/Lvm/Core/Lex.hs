{------------------------------------------------------------------------
  The Core Assembler.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
------------------------------------------------------------------------}

--  $Id$

module Lvm.Core.Lex( topLevel
              , varid, conid, anyid
              , reserved, special
              , integerOrFloat, integer, stringLiteral 
              ) where

import Control.Monad (void)
import Data.Char  ( digitToInt, isAlphaNum, isLower, isUpper )
import Data.Set ( Set, fromList, member )
import Lvm.Common.Id    ( Id, idFromString )

import Text.ParserCombinators.Parsec hiding (space,tab,lower,upper,alphaNum,char,string)
import qualified Text.ParserCombinators.Parsec as P

-----------------------------------------------------------
-- Reserved
-----------------------------------------------------------   
special :: String -> Parser ()
special name
  = lexeme (string name <?> name)

reserved :: String -> Parser ()
reserved name 
  = lexeme $ try (
    do{ string name
      ; notFollowedBy idchar <?> ("end of " ++ show name)
      }  
    <?> name) 

isReserved :: String -> Bool
isReserved name
  = member name reservedNames

reservedNames :: Set String
reservedNames
  = fromList
    [ "module", "where"
    , "import", "abstract", "extern"
    , "custom", "val", "con"
    , "match", "with"
    , "let", "rec", "in"
    , "static", "dynamic", "runtime"
    , "stdcall", "ccall", "instruction"
    , "decorate"
    , "private", "public", "nothing"
    , "type", "data", "forall", "exist"
    , "case", "of"
    , "if", "then", "else"
    ]


-----------------------------------------------------------
-- Numbers
-----------------------------------------------------------

integerOrFloat :: Parser (Either Integer Double)
integerOrFloat  = lexeme intOrFloat <?> "number"

integer :: Parser Integer
integer         = lexeme int <?> "integer"

intOrFloat :: Parser (Either Integer Double)
intOrFloat      = do{ char '0'
                    ; zeroNumFloat
                    }
                  <|> decimalFloat
            
zeroNumFloat :: Parser (Either Integer Double)      
zeroNumFloat    =  do{ n <- hexadecimal <|> octal
                     ; return (Left n)
                     }
                <|> decimalFloat
                <|> fractFloat 0
                <|> return (Left 0)                  
            
decimalFloat :: Parser (Either Integer Double)      
decimalFloat    = do{ n <- decimal
                    ; option (Left n) 
                             (fractFloat n)
                    }

fractFloat :: Integer -> Parser (Either a Double)
fractFloat n    = do{ f <- fractExponent n
                    ; return (Right f)
                    }
             
fractExponent :: Integer -> Parser Double       
fractExponent n = do{ fract <- try fraction -- "try" due to ".." as in "[1..6]"
                    ; expo  <- option 1.0 exponent'
                    ; return ((fromInteger n + fract)*expo)
                    }
                <|>
                  do{ expo <- exponent'
                    ; return (fromInteger n * expo)
                    }

fraction :: Parser Double
fraction        = do{ char '.'
                    ; digits <- many1 digit <?> "fraction"
                    ; return (foldr op 0.0 digits)
                    }
                  <?> "fraction"
                where
                  op d f    = (f + fromIntegral (digitToInt d))/10.0

exponent'  :: Parser Double                    
exponent'       = do{ void (oneOf "eE")
                    ; f <- sign
                    ; e <- decimal <?> "exponent"
                    ; return (power (f e))
                    }
                  <?> "exponent"
                where
                   power e  | e < 0      = 1.0/power(-e)
                            | otherwise  = fromInteger (10^e)

sign :: Parser (Integer -> Integer)
sign            =   (char '-' >> return negate) 
                <|> (char '+' >> return id)     
                <|> return id



-- integers
int :: Parser Integer
int             = zeroNumber <|> decimal
    
zeroNumber :: Parser Integer
zeroNumber      = do{ char '0'
                    ; hexadecimal <|> octal <|> decimal <|> return 0
                    }
                  <?> ""       

decimal, hexadecimal, octal :: Parser Integer
decimal         = number 10 digit        
hexadecimal     = do{ void (oneOf "xX"); number 16 hexDigit }
octal           = do{ void (oneOf "oO"); number 8 octDigit  }

number :: Integer -> Parser Char -> Parser Integer
number base baseDigit
    = do{ digits <- many1 baseDigit
        ; let n = foldl (\x d -> base*x + toInteger (digitToInt d)) 0 digits
        ; seq n (return n)
        }


-----------------------------------------------------------
-- Identifiers
-----------------------------------------------------------   
anyid :: Parser (Either Id Id)
anyid
  =   do{ x <- varid; return (Left x) }
  <|> do{ x <- conid; return (Right x) }

varid,conid :: Parser Id
varid  
  = lexeme (
    do{ name <- lowerid <|> extid '$'
      ; return (idFromString name)
      } 
    <?> "variable")

conid  
  = lexeme (
    do{ name <- upperid <|> extid '@' 
      ; return (idFromString name)
      }
    <?> "constructor")


upperid :: Parser String
upperid
  = do{ c  <- upper
      ; cs <- many idchar
      ; return (c:cs)
      }

lowerid :: Parser String
lowerid
  = try $
    do{ c  <- lower
      ; cs <- many idchar
      ; let name = c:cs
      ; if isReserved name
         then unexpected ("reserved word " ++ show name)
         else return name
      }

idchar :: Parser Char
idchar
  = alphanum <|> oneOf "_'"


-- extended identifiers
extid :: Char -> Parser String
extid start
  = do{ char start
      ; xs <- many extchar
      ; return (foldr (maybe id (:)) "" xs)
      }

extchar :: Parser (Maybe Char)
extchar
  =   do{ c <- extletter; return (Just c) }
  <|> extescape
  <?> "identifier character"

extletter :: Parser Char
extletter
  = satisfy (\c -> isGraphic c && notElem c "\\.")

extescape :: Parser (Maybe Char)
extescape
  = do{ char '\\'
      ;     do{ escapeempty; return Nothing }
        <|> do{ esc <- escape; return (Just esc) }
      }

-----------------------------------------------------------
-- Strings
-----------------------------------------------------------
stringLiteral :: Parser String
stringLiteral   = lexeme (
                  do{ str <- between (char '"')                   
                                     (char '"' <?> "end of string")
                                     (many stringchar) 
                    ; return (foldr (maybe id (:)) "" str)
                    }
                  <?> "string")

stringchar :: Parser (Maybe Char)
stringchar      =   do{ c <- stringletter; return (Just c) }
                <|> stringescape 
                <?> "string character"
            
stringletter :: Parser Char
stringletter    = satisfy (\c -> c==' ' || (isGraphic c && notElem c "\"\\"))

stringescape :: Parser (Maybe Char)
stringescape    = do{ char '\\'
                    ;     do{ escapegap  ; return Nothing }
                      <|> do{ escapeempty; return Nothing }
                      <|> do{ esc <- escape; return (Just esc) }
                    }
           
escapeempty :: Parser ()         
escapeempty = char '&'

escapegap :: Parser ()
escapegap       = do{ whitespace
                    ; char '\\' <?> "end of string gap"
                    }
      
escape :: Parser Char                                 
escape          = charesc <|> charnum <?> "escape code"

charnum :: Parser Char
charnum         = do{ code <- decimal 
                              <|> do{ char 'o'; number 8 octDigit }
                              <|> do{ char 'x'; number 16 hexDigit }
                    ; return (toEnum (fromInteger code))
                    }

charesc :: Parser Char
charesc         = choice (map parseEsc escMap)
                where
                  parseEsc (c,code) = do{ char c; return code }
                  escMap            = zip "abfnrstv\\\"\'."
                                          "\a\b\f\n\r \t\v\\\"\'."


-----------------------------------------------------------
-- Lexeme
-----------------------------------------------------------   
lexeme :: Parser a -> Parser a
lexeme p
  = do{ x <- p
      ; whitespace
      ; return x
      }

-----------------------------------------------------------
-- Whitespace
-----------------------------------------------------------   
topLevel :: Parser a -> Parser a
topLevel p
  = do{ whitespace 
      ; x <- p
      ; eof
      ; return x
      }

whitespace :: Parser ()
whitespace 
  = skipMany (void white <|> linecomment <|> blockcomment <?> "")
           
linecomment :: Parser ()                                    
linecomment 
  = do{ try (string "--")
      ; skipMany linechar
      }

linechar :: Parser Char
linechar
  = graphic <|> space <|> tab

blockcomment :: Parser ()
blockcomment 
  = do{ try (string "{-")
      ; incomment
      }

incomment :: Parser ()
incomment 
    =   try (string "-}")
    <|> do{ blockcomment;             incomment }
    <|> do{ skipMany1 contentchar;    incomment }
    <|> do{ void (oneOf commentchar); incomment }
    <?> "end of comment"  
    where
      commentchar     = "-{}"
      contentchar     = white <|> satisfy (\c -> isGraphic c && notElem c commentchar)


-----------------------------------------------------------
-- Character classes
-----------------------------------------------------------   

white, space, tab, alphanum, lower, upper, graphic :: Parser Char

white    = oneOf " \n\r\t"
space    = P.char ' '
tab      = P.char '\t'
alphanum = satisfy isAlphaNum
lower    = satisfy isLower
upper    = satisfy isUpper
graphic  = satisfy isGraphic

isGraphic :: Char -> Bool
isGraphic c
  =  (code >= 0x21   && code <= 0xD7FF) || (code >= 0xE000 && code <= 0xFFFD)
  where
    code = fromEnum c
 
char :: Char -> Parser ()
char = void . P.char    

string :: String -> Parser ()
string = void . P.string