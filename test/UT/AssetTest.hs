module UT.AssetTest(mortgageTests)
where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Time as T
import qualified Lib as L
import qualified Asset as P
import qualified Assumptions as A
import qualified Cashflow as CF

import Debug.Trace
debug = flip trace

tm = P.Mortgage
     (P.OriginalInfo 10000 (P.Fix 0.08) 24 L.Monthly (L.toDate "20210101") P.Level)
     8000 0.08 19 P.Current

tm1 = P.Mortgage
     (P.OriginalInfo 240 (P.Fix 0.08) 24 L.Monthly (L.toDate "20210101") P.Even)
     240 0.08 19 P.Current

tm2 = P.Mortgage
     (P.OriginalInfo 240 (P.Fix 0.08) 24 L.Monthly (L.toDate "20210101") P.Even)
     240 0.08 19 (P.Defaulted Nothing)

asOfDate = L.toDate "20210605"
tmcf_00 = P.projCashflow tm asOfDate []
trs = CF.getTsCashFlowFrame tmcf_00
tmcf_default = P.projCashflow tm asOfDate [A.DefaultConstant 0.015]


mortgageTests = testGroup "Mortgage cashflow Tests"
  [
    testCase "Fix rate mortgage" $
     --  19 @=? (CF.sizeCashFlowFrame tmcf_00)
     assertEqual "total size of cf" 19 (CF.sizeCashFlowFrame tmcf_00) -- `debug` ("result"++show(tmcf_00))
     ,
     testCase "first Date" $
     assertEqual "first date" (L.toDate "20210701")  (CF.tsDate (head trs)) -- `debug` ("result"++show(tmcf_00))
     --assertEqual "total size of cf" 19 19
     ,
     testCase "Even Principal Type of Mortgage" $
     let
        tm1cf_00 = P.calcCashflow tm1 asOfDate
        trs = CF.getTsCashFlowFrame tm1cf_00
     in
        assertEqual "first row" 12.63  (CF.mflowPrincipal (head trs)) -- `debug` ("result"++show(tmcf_00))
     ,
     testCase "Default asset won't have cashflow if no assumption" $
     let
        asDay = (L.toDate "20220101")
        tm2cf_00 = P.projCashflow tm2 asDay  []
        trs = CF.getTsCashFlowFrame tm2cf_00
     in
        assertEqual "Empty for principal"
                    -- [0.0, asDay, 1]
                    (0.0, asDay, 1)
                    ((CF.mflowPrincipal (head trs))
                    ,(CF.mflowDate (head trs))
                    ,(length trs))

     --testCase "Even Principal Type of Mortgage proj with assumption" $
     --let
     --   tm1cf_00 = P.projCashflow tm1
     --   trs = CF.getTsCashFlowFrame tm1cf_00
     --in
     --   assertEqual "first row" 10.0  (CF.mflowPrincipal (head trs)) -- `debug` ("result"++show(tmcf_00))
  ]