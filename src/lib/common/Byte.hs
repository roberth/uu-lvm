{-*-----------------------------------------------------------------------
  The Core Assembler.

  Daan Leijen.

  Copyright 2001, Daan Leijen. All rights reserved. This file
  is distributed under the terms of the GHC license. For more
  information, see the file "license.txt", which is included in
  the distribution.
-----------------------------------------------------------------------*-}

-- $Id$

module Byte( Byte

           , Bytes, nil, unit, cons, cat, cats, isNil
           , bytesLength
           , writeBytes
           , bytesFromList, listFromBytes

           , bytesFromString, stringFromBytes
           , bytesFromInt32
           , byteFromInt8
           ) where

import IO       ( IOMode(..) )
import Special  ( openBinary, writeBinaryChar, closeBinary )
import Standard ( strict )

{----------------------------------------------------------------
  types
----------------------------------------------------------------}
type Byte   = Char

data Bytes  = Nil
            | Cons !Byte !Bytes
            | Cat  !Bytes !Bytes


{----------------------------------------------------------------
  conversion to bytes
----------------------------------------------------------------}
byteFromInt8 :: Int -> Byte
byteFromInt8 i
  = toEnum (rem i 256)


bytesFromString :: String -> Bytes
bytesFromString s
  = bytesFromList s

stringFromBytes :: Bytes -> String
stringFromBytes bs
  = listFromBytes bs

bytesFromInt32 :: Int -> Bytes    -- 4 byte big-endian encoding
bytesFromInt32 i
  = let n0 = if (i < 0) then (max32+i+1) else i
        n1 = quot n0 256
        n2 = quot n1 256
        n3 = quot n2 256
        xs = map byteFromInt8 [n3,n2,n1,n0]
    in bytesFromList xs

max32 :: Int
max32
  = 2^32-1




{----------------------------------------------------------------
  Byte lists
----------------------------------------------------------------}
isNil Nil         = True
isNil (Cons b bs) = False
isNil (Cat bs cs) = isNil bs && isNil cs

nil         = Nil
unit b      = Cons b Nil
cons b bs   = Cons b bs

cats bbs    = foldr Cat Nil bbs
cat bs cs   = case cs of
                Nil   -> bs
                other -> case bs of
                           Nil   -> cs
                           other -> Cat bs cs



listFromBytes bs
  = loop [] bs
  where
    loop next bs
      = case bs of
          Nil       -> next
          Cons b bs -> b:loop next bs
          Cat bs cs -> loop (loop next cs) bs

bytesFromList bs
  = foldr Cons Nil bs

bytesLength :: Bytes -> Int
bytesLength bs
  = loop 0 bs
  where
    loop n bs
      = case bs of
          Nil       -> n
          Cons b bs -> strict loop (n+1) bs
          Cat bs cs -> loop (loop n cs) bs

writeBytes :: FilePath -> Bytes -> IO ()
writeBytes path bs
  = do{ h <- openBinary path WriteMode
      ; write h bs
      ; closeBinary h
      }
  where
    write h bs
      = case bs of
          Nil       -> return ()
          Cons b bs -> do{ writeBinaryChar h b; write h bs }
          Cat bs cs -> do{ write h bs; write h cs }
