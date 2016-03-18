{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TypeFamilies          #-}

module Lucene.Query
  (
  -- * Query type
    LuceneQuery
  -- * Query construction
  -- $note-simplicity
  , (=:)
  , (&&:)
  , (||:)
  , (-:)
  -- * Expression type
  , LuceneExpr
  -- * Expression construction
  -- $note-simplicity
  , int
  , true
  , false
  , word
  , wild
  , regex
  , phrase
  , fuzz
  , (~:)
  , fuzzy
  , to
  , boost
  , (^:)
  -- * Query compilation
  , compileLuceneQuery
  ) where

import Lucene.Class
import Lucene.Type

import Control.Applicative
import Data.ByteString.Builder    (Builder)
import Data.ByteString.Lazy.Char8 (ByteString)
import Data.Monoid
import Data.String                (IsString(..))
import Data.Text                  (Text)
import GHC.Exts                   (IsList(..))

import qualified Data.Text                  as T
import qualified Data.Text.Encoding         as T
import qualified Data.ByteString.Builder    as BS
import qualified Data.ByteString.Lazy.Char8 as BS

-- | A Lucene query.
newtype LuceneQuery = Query { unQuery :: Builder }


-- | A Lucene expression.
newtype LuceneExpr (t :: LuceneType) = Expr { unExpr :: Builder }

-- | This instance is only provided for convenient numeric literals. /ALL/ 'Num'
-- functions besides 'fromInteger' are not implemented and will cause a runtime
-- crash.
instance Num (LuceneExpr TInt) where
  (+) = error "LuceneExpr.Num.(+): not implemented"
  (*) = error "LuceneExpr.Num.(*): not implemented"
  abs = error "LuceneExpr.Num.abs: not implemented"
  signum = error "LuceneExpr.Num.signum: not implemented"
  negate = error "LuceneExpr.Num.negate: not implemented"

  fromInteger i = int (fromInteger i)

instance IsString (LuceneExpr TWord) where
  fromString s = word (T.pack s)

instance IsList (LuceneExpr TPhrase) where
  type Item (LuceneExpr TPhrase) = LuceneExpr TWord

  fromList = phrase
  toList = map (Expr . BS.lazyByteString) . BS.words . BS.toLazyByteString . unExpr


instance Lucene LuceneExpr LuceneQuery where
  int n = Expr (BS.lazyByteString (BS.pack (show n)))

  true = Expr "true"

  false = Expr "false"

  word s = Expr (T.encodeUtf8Builder s)

  wild s = Expr (T.encodeUtf8Builder s)

  regex s = Expr ("/" <> T.encodeUtf8Builder s <> "/")

  phrase ss = Expr ("\"" <> spaces ss <> "\"")
   where
    spaces [] = ""
    spaces [w] = unExpr w
    spaces (w:ws) = unExpr w <> " " <> spaces ws

  fuzz e n = Expr (unExpr e <> "~" <> BS.lazyByteString (BS.pack (show n)))

  to b1 b2 =
    case (b1, b2) of
      (Inclusive e1, Inclusive e2) -> go '[' ']' e1 e2
      (Inclusive e1, Exclusive e2) -> go '[' '}' e1 e2
      (Exclusive e1, Inclusive e2) -> go '{' ']' e1 e2
      (Exclusive e1, Exclusive e2) -> go '{' '}' e1 e2
   where
    go :: Char -> Char -> LuceneExpr a -> LuceneExpr a -> LuceneExpr TRange
    go c1 c2 e1 e2 =
      Expr (BS.char8 c1 <>
            unExpr e1   <>
            " TO "      <>
            unExpr e2   <>
            BS.char8 c2)

  boost e n = Expr (unExpr e <> "^" <> BS.lazyByteString (BS.pack (show n)))

  f =: e = Query (T.encodeUtf8Builder f <> ":" <> unExpr e)

  q1 &&: q2 = Query ("(" <> unQuery q1 <> " AND " <> unQuery q2 <> ")")

  q1 ||: q2 = Query ("(" <> unQuery q1 <> " OR " <> unQuery q2 <> ")")

  q1 -: q2 = Query ("(" <> unQuery q1 <> " NOT " <> unQuery q2 <> ")")


-- | Compile a 'LuceneQuery' to a lazy 'ByteString'. Because the underlying
-- expressions are correct by consutruction, this function is total.
compileLuceneQuery :: LuceneQuery -> ByteString
compileLuceneQuery = BS.toLazyByteString . unQuery


-- $note-simplicity
-- For simplicity, the type signatures in the examples below monomorphise the
-- functions to use 'LuceneQuery' (and therefore 'LuceneExpr', due to the
-- functional dependency).
