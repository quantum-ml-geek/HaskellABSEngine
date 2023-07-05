{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}

module Deal.DealBase (TestDeal(..),SPV(..)) 
  where
import qualified Accounts as A
import qualified Asset as P
import qualified Expense as F
import qualified Liability as L
import qualified CreditEnhancement as CE
import qualified Waterfall as W
import qualified Cashflow as CF
import qualified Assumptions as AP
import qualified AssetClass.AssetBase as ACM
import qualified Call as C
import qualified InterestRate as IR
import Stmt
import Lib
import Util
import Types
import Revolving
import Triggers

import qualified Data.Map as Map
import qualified Data.Time as T
import qualified Data.Set as S
import Data.List
import Data.Fixed
import Data.Maybe
import Data.Aeson hiding (json)
import qualified Data.Aeson.Encode.Pretty as Pretty
import Language.Haskell.TH
import Data.Aeson.TH
import Data.Aeson.Types
import GHC.Generics

class SPV a where
  getBondByName :: a -> Maybe [String] -> Map.Map String L.Bond
  getBondBegBal :: a -> String -> Balance
  getBondStmtByName :: a -> Maybe [String] -> Map.Map String (Maybe Statement)
  getFeeByName :: a -> Maybe [String] -> Map.Map String F.Fee
  getAccountByName :: a -> Maybe [String] -> Map.Map String A.Account
  

class DealDates a where 
  getClosingDate :: a -> Date
  getFirstPayDate :: a -> Date


data TestDeal a = TestDeal {
  name :: String
  ,status :: DealStatus
  ,dates :: DateDesp
  ,accounts :: Map.Map String A.Account
  ,fees :: Map.Map String F.Fee
  ,bonds :: Map.Map String L.Bond
  ,pool ::  P.Pool a 
  ,waterfall :: Map.Map W.ActionWhen W.DistributionSeq
  ,collects :: [W.CollectionRule]
  ,call :: Maybe [C.CallOption]
  ,liqProvider :: Maybe (Map.Map String CE.LiqFacility)
  ,rateSwap :: Maybe (Map.Map String CE.RateSwap)
  ,currencySwap :: Maybe (Map.Map String CE.CurrencySwap)
  ,custom:: Maybe (Map.Map String CustomDataType)
  ,triggers :: Maybe (Map.Map DealCycle [Trigger])
  ,overrides :: Maybe [OverrideType]
} deriving (Show,Generic)

instance SPV (TestDeal a) where
  getBondByName t bns
    = case bns of
         Nothing -> bonds t
         Just _bns -> Map.filterWithKey (\k _ -> S.member k (S.fromList _bns)) (bonds t)

  getBondStmtByName t bns
    = Map.map L.bndStmt bndsM
      where
      bndsM = Map.map L.consolStmt $ getBondByName t bns

  getBondBegBal t bn 
    = case L.bndStmt b of
        Just (Statement stmts) -> getTxnBegBalance $ head stmts -- `debug` ("Getting beg bal"++bn++"Last smt"++show (head stmts))
        Nothing -> L.bndBalance b  -- `debug` ("Getting beg bal nothing"++bn)
        where
            b = bonds t Map.! bn

  getFeeByName t fns
    = case fns of
         Nothing -> fees t
         Just _fns -> Map.filterWithKey (\k _ ->  S.member k (S.fromList _fns)) (fees t)
  
  getAccountByName t ans
    = case ans of
         Nothing -> accounts t
         Just _ans -> Map.filterWithKey (\k _ ->  S.member k (S.fromList _ans)) (accounts t)

instance DealDates DateDesp where 
  getClosingDate (PatternInterval _m)
    = let 
        (sd,dp,ed) = _m Map.! ClosingDate 
      in 
         sd
         
  getClosingDate (CustomDates _ _ cd _) = cd

  getClosingDate (FixInterval _m _p1 _p2) = _m Map.! ClosingDate

  getClosingDate (PreClosingDates _ x _ _ _ _) = x

  getClosingDate (CurrentDates (_,cd) _ _ _ _ ) = cd

  getFirstPayDate (PatternInterval _m) 
    = let 
        (sd,dp,ed) = _m Map.! FirstPayDate
      in 
         sd
  
  getFirstPayDate (CustomDates _ _ _ bActions )
    = getDate $ head bActions
  
  getFirstPayDate (FixInterval _m _p1 _p2)  
    = _m Map.! FirstPayDate
  
  getFirstPayDate (PreClosingDates _ _ _ _ _ (fp,_)) = fp
  
  getFirstPayDate (CurrentDates _ _ _ _ (cpay,_)) = cpay    


$(deriveJSON defaultOptions ''TestDeal)
