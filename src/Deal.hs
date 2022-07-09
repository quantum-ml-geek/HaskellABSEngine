{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Deal (TestDeal,run2,getInits,runDeal,ExpectReturn(..)
            ,bonds,accounts,fees) where

import qualified Accounts as A
import qualified Asset as P
import qualified Equity as E
import qualified Expense as F
import qualified Liability as L
import qualified Waterfall as W
import qualified Cashflow as CF
import qualified Assumptions as AP
import qualified Call as C
import Lib

import qualified Data.Map as Map
import qualified Data.Time as T
import qualified Data.Set as S
import qualified Control.Lens as LS
import Data.List
import Data.Maybe
import Data.Aeson hiding (json)
import Language.Haskell.TH
import Data.Aeson.TH
import Data.Aeson.Types

import Debug.Trace
debug = flip trace

_startDate = (T.fromGregorian 1970 1 1)

class SPV a where
  projBondCashflow :: a -> ()
  projAssetCashflow :: a -> ()


data TestDeal = TestDeal {
  name :: String
  ,dates :: Map.Map String T.Day
  ,payPeriod :: Period
  ,collectPeriod :: Period
  ,accounts :: Map.Map String A.Account
  ,fees :: Map.Map String F.Fee
  ,bonds :: Map.Map String L.Bond
  ,pool ::  (P.Pool P.Mortgage)
  ,waterfall :: Map.Map String W.DistributionSeq
  ,collects :: [W.CollectionRule]
  ,call :: Maybe (String ,[C.CallOption])
} deriving (Show)

$(deriveJSON defaultOptions ''TestDeal)

td = TestDeal {
  name = "test deal1"
  ,dates = (Map.fromList [("closing-date",(T.fromGregorian 2022 1 1))
                         ,("cutoff-date",(T.fromGregorian 2022 1 1))
                         ,("first-pay-date",(T.fromGregorian 2022 2 25))
                         ])
  ,payPeriod = Monthly
  ,collectPeriod = Monthly
  ,accounts = (Map.fromList 
  [("General", (A.Account { A.accName="General" ,A.accBalance=0.0 ,A.accType=Nothing, A.accInterest=Nothing ,A.accStmt=Nothing
  })),
   ("Reserve", (A.Account { A.accName="General" ,A.accBalance=0.0 ,A.accType=Just (A.FixReserve 500), A.accInterest=Nothing ,A.accStmt=Nothing
  }))
  ])
  ,fees = (Map.fromList [("Service-Fee"
                         ,F.Fee{F.feeName="service-fee"
                                ,F.feeType = (F.FixFee 500)
                                ,F.feeStart = (T.fromGregorian 2022 1 1)
                                ,F.feeDue = 0
                                ,F.feeDueDate = Nothing
                                ,F.feeArrears = 0
                                ,F.feeLastPaidDay = Nothing
                                ,F.feeStmt = Nothing})])
  ,bonds = (Map.fromList [("A"
                          ,L.Bond{
                              L.bndName="A"
                             ,L.bndType=L.Sequential
                             ,L.bndOriginInfo= L.OriginalInfo{
                                                L.originBalance=3000
                                                ,L.originDate= (T.fromGregorian 2022 1 1)
                                                ,L.originRate= 0.08}
                             ,L.bndInterestInfo= L.Fix 0.08
                             ,L.bndBalance=3000
                             ,L.bndRate=0.08
                             ,L.bndDuePrin=0.0
                             ,L.bndDueInt=0.0
                             ,L.bndLastIntPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndLastPrinPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndStmt=Nothing})
                         ,("B"
                          ,L.Bond{
                              L.bndName="B"
                             ,L.bndType=L.PAC (AmountCurve
                                            [(TsPoint (T.fromGregorian 2022 3 1) 100.0)
                                            ,(TsPoint (T.fromGregorian 2022 3 1) 100.0)])
                             ,L.bndOriginInfo= L.OriginalInfo{
                                                L.originBalance=3000
                                                ,L.originDate= (T.fromGregorian 2022 1 1)
                                                ,L.originRate= 0.08}
                             ,L.bndInterestInfo= L.Floater LIBOR6M 0.01 0.085 Quarterly Nothing Nothing
                             ,L.bndBalance=3000
                             ,L.bndRate=0.08
                             ,L.bndDuePrin=0.0
                             ,L.bndDueInt=0.0
                             ,L.bndLastIntPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndLastPrinPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndStmt=Nothing})
                        ,("C"
                          ,L.Bond{
                              L.bndName="C"
                             ,L.bndType=L.Lockout (T.fromGregorian 2022 6 1)
                             ,L.bndOriginInfo= L.OriginalInfo{
                                                L.originBalance=3000
                                                ,L.originDate= (T.fromGregorian 2022 1 1)
                                                ,L.originRate= 0.08}
                             ,L.bndInterestInfo= L.Floater LIBOR6M 0.01 0.085 Quarterly Nothing Nothing
                             ,L.bndBalance=3000
                             ,L.bndRate=0.08
                             ,L.bndDuePrin=0.0
                             ,L.bndDueInt=0.0
                             ,L.bndLastIntPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndLastPrinPay = Just (T.fromGregorian 2022 1 1)
                             ,L.bndStmt=Nothing})
                         ]
           )
  ,pool = P.Pool {P.assets=[P.Mortgage
                                         P.OriginalInfo{
                                           P.originBalance=4000
                                           ,P.originRate=P.Fix 0.085
                                           ,P.originTerm=60
                                           ,P.period=Monthly
                                           ,P.startDate=(T.fromGregorian 2022 1 1)}
                                         4000
                                         0.085
                                         60]
                 ,P.futureCf=Nothing
                 ,P.asOfDate = T.fromGregorian 2022 1 1}
   ,waterfall = Map.fromList [("Base", [
   W.PayFee ["General"] ["Service-Fee"]
   ,W.PayFeeBy (W.DuePct 0.5) ["General"] ["Service-Fee"]
   ,W.TransferReserve W.TillSource  "General" "General" Nothing
   ,W.TransferReserve W.TillTarget  "General" "General" Nothing
   ,W.PayInt "General" ["A"]
   ,W.PayPrin "General" ["A"]
   ])]
 ,collects = [W.Collect W.CollectedInterest "General"
             ,W.Collect W.CollectedPrincipal "General"]
 ,call = Nothing
}


performAction :: T.Day -> TestDeal -> W.Action -> TestDeal
performAction d t (W.Transfer an1 an2 tags) =
  t {accounts = accMapAfterDeposit}
  where
    accMap = (accounts t)
    sourceAcc = Map.lookup an1 accMap
    transferAmt = case sourceAcc of
                    Just acc -> (A.accBalance acc)
                    Nothing -> 0
    _tags = case tags of
              Just x -> x
              Nothing -> ""
    accMapAfterDraw = Map.adjust (A.draw transferAmt d ("To:"++an2++"|"++_tags)) an1 accMap
    accMapAfterDeposit = Map.adjust (A.deposit transferAmt d ("From:"++an1++"|"++_tags)) an2 accMapAfterDraw

performAction d t (W.TransferBy an1 an2 formula) =
  t {accounts = accMapAfterDeposit}
  where
    accMap = (accounts t)
    sourceAcc = accMap Map.! an1
    targetAcc = accMap Map.! an2 -- `debug` ("Target>>"++an2)

    formulaAmount =
      case formula of
        W.ABCD -> (queryDeal t (CumulativeDefaultBalance d))
                  + (queryStmtAmt (A.accStmt targetAcc) ("SupportPay:"++an1) )
                  - (queryStmtAmt (A.accStmt sourceAcc) ("To:"++an2) )
        _ -> -1

    transferAmt = min formulaAmount (A.accBalance sourceAcc)

    accMapAfterDraw = Map.adjust (A.draw transferAmt d ("To:"++an2++"|"++show(formula))) an1 accMap
    accMapAfterDeposit = Map.adjust (A.deposit transferAmt d ("From:"++an1++"|"++show(formula))) an2 accMapAfterDraw

performAction d t (W.TransferReserve meetAcc sa ta tags) =
    t {accounts = accMapAfterTransfer }
  where
    accMap = (accounts t)
    sourceAcc = accMap Map.! sa
    targetAcc = accMap Map.! ta
    sourceAccBal = (A.accBalance sourceAcc)
    targetAccBal = (A.accBalance targetAcc) 
    transferAmt = 
        case meetAcc of 
             W.TillSource -> 
                 let 
                     sourceTarBal = calcTargetAmount t sourceAcc
                 in 
                     max (sourceAccBal - sourceTarBal ) 0
             W.TillTarget ->
                 let 
                   targetBal = calcTargetAmount t targetAcc
                   transferAmtTarget = max (targetBal - targetAccBal) 0
                 in 
                     min transferAmtTarget sourceAccBal

    accMapAfterTransfer
      = case transferAmt of
          0 -> accMap
          amt ->  Map.adjust (A.draw amt d "withdraw") sa  $ Map.adjust (A.deposit amt d "transfer") ta $ accMap

performAction d t (W.PayFee ans fns) =
  t {accounts = accMapUpdated, fees = feeMapUpdated}
  where
    feeMap = (fees t)
    accSet = S.fromList ans
    accMap = Map.filterWithKey (\k _ -> (S.member k accSet)) (accounts t)

    feesToPay = map (\x -> feeMap Map.! x ) fns
    feesWithDue = map (\x -> calcDueFee t d x) feesToPay
    feeDueAmts = map (\x -> (F.feeDue x) ) feesWithDue

    accNList = Map.toList accMap
    availBalLst = [ (n,(A.accBalance x)) | (n,x) <- accNList ]
    availAccBals = map snd availBalLst
    availAccNames = map fst availBalLst
    accList = map (\x -> accMap Map.! x) ans

    availBal = sum availAccBals

    actualPaidOut = min availBal $ sum feeDueAmts
    feesAmountToBePaid = zip feesWithDue  $ prorataFactors feeDueAmts availBal
    feesPaid = map (\(f,amt) -> (F.payFee d amt f)) feesAmountToBePaid

    feeMapUpdated = Map.union (Map.fromList $ zip fns feesPaid) feeMap

    accsAfterPay = A.supportPay accList d actualPaidOut ("Pay Fee",("SupportPay:"++(head ans)))
    accMapUpdated = Map.union (Map.fromList (zip ans accsAfterPay)) (accounts t)


performAction d t (W.PayFeeBy limit ans fns) =
  t {accounts = accMapUpdated, fees = feeMapUpdated}
  where
    feeMap = (fees t)
    accSet = S.fromList ans
    accMap = Map.filterWithKey (\k _ -> (S.member k accSet)) (accounts t)

    feesToPay = map (\x -> feeMap Map.! x ) fns
    feesWithDue = map (\x -> calcDueFee t d x) feesToPay
    feeDueAmts = case limit of
                   (W.DuePct pct) -> map (\x -> (F.feeDue x) * pct ) feesWithDue
                   (W.DueCapAmt amt) -> map (\x -> (min (F.feeDue x) amt)) feesWithDue

    accNList = Map.toList accMap
    availBalLst = [ (n,(A.accBalance x)) | (n,x) <- accNList]
    availAccBals = map snd availBalLst
    availAccNames = map fst availBalLst
    accList = map (\x -> accMap Map.! x) ans

    availBal = sum availAccBals

    actualPaidOut = min availBal $ sum feeDueAmts
    feesAmountToBePaid = zip feesWithDue  $ prorataFactors feeDueAmts availBal
    feesPaid = map (\(f,amt) -> (F.payFee d amt f)) feesAmountToBePaid

    feeMapUpdated = Map.union (Map.fromList $ zip fns feesPaid) feeMap

    accsAfterPay = A.supportPay accList d actualPaidOut ("Pay Fee",("SupportPay:"++(head ans)))
    accMapUpdated = Map.union (Map.fromList (zip ans accsAfterPay)) (accounts t)

performAction d t (W.PayInt an bnds) =
  t {accounts = accMapAfterPay, bonds = bndMapUpdated}
  where
    bndMap = (bonds t)
    accMap = (accounts t)
    acc = accMap Map.! an 

    bndsToPay = map (\x -> bndMap Map.! x ) bnds
    bndsWithDue = filter (\x -> ((L.bndDueInt x) > 0)) $ map (\x -> calcDueInt t d x) bndsToPay
    bndsDueAmts = map (\x -> (L.bndDueInt x) ) bndsWithDue

    availBal = A.accBalance acc
    actualPaidOut = min availBal $ foldl (+) 0 bndsDueAmts
    bndsAmountToBePaid = zip bndsWithDue  $ prorataFactors bndsDueAmts availBal
    bndsPaid = map (\(l,amt) -> (L.payInt d amt l)) bndsAmountToBePaid

    bndMapUpdated =   Map.union (Map.fromList $ zip bnds bndsPaid) bndMap
    accMapAfterPay = Map.adjust (A.draw actualPaidOut d "Pay Int") an accMap

performAction d t (W.PayPrin an bnds) =
  t {accounts = accMapAfterPay, bonds = bndMapUpdated}
  where
    bndMap = (bonds t)
    accMap = (accounts t)
    acc = accMap Map.! an 

    bndsToPay = filter (\x -> ((L.bndBalance x) > 0)) $ map (\x -> bndMap Map.! x ) bnds
    -- TODO  add filter lockout bonds here 
    bndsWithDue = map (\x -> calcDuePrin t d x) bndsToPay  --`debug` ("bonds to pay->"++show(bndsToPay))
    bndsDueAmts = map (\x -> (L.bndDuePrin x) ) bndsWithDue

    availBal = A.accBalance acc
    actualPaidOut = min availBal $ foldl (+) 0 bndsDueAmts
    bndsAmountToBePaid = zip bndsWithDue (prorataFactors bndsDueAmts availBal)  
            -- `debug` ("BndDueAmts"++show(bndsDueAmts)++"DueBonds>>"++show(bndsWithDue))
    bndsPaid = map (\(l,amt) -> (L.payPrin d amt l)) bndsAmountToBePaid   -- `debug` ("BTO pay ->>>"++show(bndsAmountToBePaid))

    bndMapUpdated =  Map.union (Map.fromList $ zip bnds bndsPaid) bndMap
    accMapAfterPay = Map.adjust (A.draw actualPaidOut d "Pay Prin") an accMap

data ActionOnDate = CollectPoolIncome T.Day
                   |RunWaterfall T.Day String
                   deriving (Show)

instance Ord ActionOnDate where
  compare (CollectPoolIncome d1) (CollectPoolIncome d2) = compare d1 d2
  compare (RunWaterfall d1 _) (RunWaterfall d2 _) = compare d1 d2
  compare (CollectPoolIncome d1) (RunWaterfall d2 _) = compare d1 d2
  compare (RunWaterfall d1 _) (CollectPoolIncome d2) = compare d1 d2

instance Eq ActionOnDate where
  (CollectPoolIncome d1) == (CollectPoolIncome d2) = d1 == d2
  (RunWaterfall d1 _) == (RunWaterfall d2 _) = d1 == d2
  (CollectPoolIncome d1) == (RunWaterfall d2 _) = d1 == d2
  (RunWaterfall d1 _) == (CollectPoolIncome d2) = d1 == d2


setBondNewRate :: T.Day -> [RateAssumption] -> L.Bond -> L.Bond
setBondNewRate d ras b@(L.Bond _ _ _ ii _ _ _ _ _ _ _) 
  = b { L.bndRate = (applyFloatRate ii d ras) }

applyFloatRate :: L.InterestInfo -> T.Day -> [RateAssumption] -> Float 
applyFloatRate (L.Floater idx spd rt p f c) d ras
  = idx_rate + spd
    where 
      idx_rate = case ra of 
        Just (RateCurve _idx _ts) -> getValByDate _ts d 
        Nothing -> -0.5 
      ra = find (\(RateCurve _idx _ts) -> (_idx==idx)) ras 

setBndsNextIntRate :: TestDeal -> T.Day -> Maybe [RateAssumption] -> TestDeal 
setBndsNextIntRate t d (Just ras) = t {bonds = updatedBonds}
    where 
        isFloat (L.Bond _ _ _ (L.Floater _ _ _ _ _ _) _ _ _ _ _ _ _ ) = True
        isFloat (L.Bond _ _ _ (L.Fix _ ) _ _ _ _ _ _ _ ) = False
        floatBonds = filter (\x -> isFloat x) $ Map.elems (bonds t)
        floatBondNames = map (\x -> (L.bndName x)) floatBonds
        updatedBonds = foldr (Map.adjust (setBondNewRate d ras)) (bonds t) floatBondNames

setBndsNextIntRate t d Nothing = t 


testCall :: TestDeal -> T.Day -> C.CallOption -> Bool 
testCall t d opt = 
    case opt of 
       C.PoolBalance x -> (queryDeal t (FutureCurrentPoolBalance d)) < x
       C.BondBalance x -> (queryDeal t CurrentBondBalance) < x
       C.PoolFactor x ->  ((queryDeal t (FutureCurrentPoolBalance d)) / (queryDeal t FutureOriginalPoolBalance))  < x
       C.BondFactor x ->  (queryDeal t BondFactor) < x
       C.OnDate x -> ( x == d )
       C.AfterDate x -> d > x
       C.And xs -> all (testCall t d) xs
       C.Or xs -> any (testCall t d) xs

testCalls :: TestDeal -> T.Day -> [C.CallOption] -> Bool
testCalls t d [] = False
testCalls t d opts = any (\x -> testCall t d x) opts -- `debug` ("testing call options")


run2 :: TestDeal -> Maybe CF.CashFlowFrame -> Maybe [ActionOnDate]
    -> Maybe [RateAssumption] -> Maybe [C.CallOption]-> TestDeal


run2 t (Just _poolFlow) (Just []) _ _    -- stop at a date
  = (prepareDeal t) -- `debug` ("In B")-- `debug` "Preparing"

run2 t (Just _poolFlow) (Just (ad:ads)) rates clls
  | ((CF.sizeCashFlowFrame _poolFlow) == 0) || ((length ads) == 0) = (prepareDeal t) -- `debug` "In A"
  | ((CF.sizeCashFlowFrame _poolFlow) > 0) && (length ads > 0) -- `debug` ("in C with ad"++show(ad)++"Rest of Ads"++show(length ads))
  = case ad of
        CollectPoolIncome d ->
          run2
            (t {accounts=accs})
            (CF.removeTsCashFlowFrameByDate _poolFlow d)
            (Just ads)
            rates
            clls  --  `debug` ("running Pool ad to next period ->>>"++show(ad))
          where
            accs = depositPoolInflow (collects t) d _poolFlow (accounts t) --  `debug` ("Deposit->"++show(d))

        RunWaterfall d waterfallName->
          if callFlag  then
              prepareDeal $ cleanUp (BalanceFactor 1.0 1.0) d "acc-prin" t --  `debug` ("Called !"++show(d))
          else
              (run2
                dAfterRateSet
                (Just _poolFlow)
                (Just ads)
                rates
                clls) -- `debug` ("Deal waterfall action RunTime =>"++show(clls))
          where
              waterfallToExe = (waterfall t)Map.!waterfallName -- `debug` ("AD->"++show(ad)++"remain ads"++show(length ads))
              dAfterWaterfall = (foldl (performAction d) t waterfallToExe)
              dAfterRateSet = dAfterWaterfall --setBndsNextIntRate dAfterWaterfall d rates `debug` ("After Rate Set")
              callOpts = fromMaybe [] clls
              callFlag = testCalls dAfterWaterfall d callOpts   -- `debug` ("Call Flag->"++show(callOpts))


run2 t Nothing Nothing Nothing Nothing
  = run2 t (Just pcf) (Just ads) Nothing Nothing
  where
    (ads,pcf,rcurves,clls,_) = getInits t Nothing

run2 t Nothing _ _ _ = (prepareDeal t) -- `debug` "End ????"

data AssetLiquidationMethod = BalanceFactor Float Float -- performing & default


cleanUp :: AssetLiquidationMethod -> T.Day -> String -> TestDeal -> TestDeal
cleanUp lq d accName t = 
    case lq of 
      BalanceFactor currentFactor defaultFactor 
        -> t {accounts = Map.adjust updateFn accName accs} -- `debug` ("Accs->"++show(accs)) 
           where 
               currenBal = 
                   case (P.futureCf (pool t)) of -- 
                      Nothing -> 0    -- `debug` ("Zero in currenBal")
                      Just (_futureCf) -> 
                        let 
                          currentPoolInflow =  CF.getEarlierTsCashFlowFrame _futureCf d
                        in
                          case currentPoolInflow of 
                            Nothing -> 0
                            Just (_ts) -> (CF.mflowBalance _ts)  --  `debug` ("current pool inflow"++show(currentPoolInflow))
                                 
               proceeds = currenBal * currentFactor -- `debug` ("procees->"++show(currenBal))
               updateFn = A.deposit proceeds d "Liquidation Proceeds" 
               accs = (accounts t) 



data ExpectReturn = DealStatus
                  | DealPoolFlow
                  | DealTxns
                  | ExecutionSummary
                  deriving (Show)

data TxnComponent = Account String
                   | Expense String
                   | Bond String
                   | Pool String
                   deriving (Show)

instance Eq TxnComponent where 
    (Account s1) == (Account s2) = s1 ==  s2
    (Bond s1) == (Bond s2) = s1 ==  s2
    (Expense s1) == (Expense s2) = s1 == s2

instance Ord TxnComponent where 
    compare (Account s1) (Account s2) = compare s1 s2
    compare (Bond s1) (Bond s2) = compare s1 s2
    compare (Expense s1) (Expense s2) = compare s1 s2
-- type EntityTxnByDay = Map (Component T.Day) (Maybe [Txn])

pairTxn :: (Map.Map TxnComponent (Maybe Statement)) -> [(TxnComponent, Txn)]
pairTxn m = Map.foldrWithKey (\k v t ->  [ (k,txn) | txn <- (getTxns v)]++t) [] m 

extractExecutionTxns:: TestDeal ->  [(TxnComponent, Txn)]
extractExecutionTxns td  = 
      (pairTxn bndStmts)++(pairTxn accStmts) ++(pairTxn feeStmts)
  where 
      bndStmts = Map.mapKeys (\x -> Bond x) $ Map.mapWithKey (\k v -> (L.bndStmt v)) (bonds td)
      accStmts = Map.mapKeys (\x -> Account x) $ Map.mapWithKey (\k v -> (A.accStmt v)) (accounts td)
      feeStmts = Map.mapKeys (\x -> Expense x) $ Map.mapWithKey (\k v -> (F.feeStmt v)) (fees td)



runDeal :: TestDeal -> ExpectReturn -> Maybe [AP.AssumptionBuilder] 
        -> (TestDeal,Maybe CF.CashFlowFrame, Maybe [(TxnComponent, Txn)])
runDeal t er assumps =
  case er of
    DealStatus ->  (finalDeal, Nothing, Nothing)
    DealPoolFlow -> (finalDeal, Just pcf, Nothing)
    DealTxns -> (finalDeal, Just pcf, Just (extractExecutionTxns(finalDeal)))
  where
    finalDeal = run2 t2 (Just pcf) (Just ads) (Just rcurves) (Just clls) -- `debug` (">>ADS==>> "++show(ads))
    (ads,pcf,rcurves,clls,t2) = getInits t assumps

prepareDeal :: TestDeal -> TestDeal 
prepareDeal t = t {bonds = Map.map L.consolStmt (bonds t)}


buildRateCurves :: [RateAssumption]-> [AP.AssumptionBuilder] -> [RateAssumption] 
buildRateCurves rs (assump:assumps) = 
    case assump of 
      AP.InterestRateConstant i f -> 
        buildRateCurves ((RateFlat i f):rs) assumps
      AP.InterestRateCurve i ds ->  -- Index [(T.Day, Float)]
        buildRateCurves ((RateCurve i (dsToTs ds)):rs) assumps
      _ -> buildRateCurves rs assumps    
    where  
        dsToTs ds = FloatCurve $ map (\(d,f) -> (TsPoint d f) ) ds
buildRateCurves rs [] = rs

buildCallOptions :: [C.CallOption] -> [AP.AssumptionBuilder] -> [C.CallOption]
buildCallOptions rs (assump:assumps) = 
    case assump of  
      AP.CallWhen opts -> buildCallOptions (rs++opts) assumps --`debug` ("assump in build"++show(assumps))
      _ -> buildCallOptions rs assumps    

buildCallOptions rs [] =  rs


setFutureCF :: TestDeal -> CF.CashFlowFrame -> TestDeal
setFutureCF t cf = 
    t {pool = newPool}
    where 
        _pool = (pool t)
        newPool = _pool {P.futureCf = (Just cf)}


getInits :: TestDeal -> Maybe [AP.AssumptionBuilder] -> 
    ([ActionOnDate], CF.CashFlowFrame, [RateAssumption],[C.CallOption]
      ,TestDeal)
getInits t (Just assumps) =
    (actionDates
    ,pCollectionCfAfterCutoff
    ,rateCurves
    ,callOptions  
    ,t_with_cf)
  where
    startDate = Map.findWithDefault _startDate "cutoff-date" (dates t)
    firstPayDate = Map.findWithDefault _startDate "first-pay-date" (dates t)

    pCollectionInt = (collectPeriod t)
    bPayInt = (payPeriod t)


    projNum = 512
    bPayDates = map (\x -> RunWaterfall (afterNPeriod firstPayDate x bPayInt) "base") [0..projNum]
    pCollectionDates = map (\x -> (afterNPeriod startDate x pCollectionInt)) [0..projNum]
    pCollectionDatesA = map (\x -> CollectPoolIncome x) pCollectionDates

    stopDate = find (\x -> case x of    
                            (AP.StopRunBy d) -> True
                            _ -> False) assumps -- `debug` (">>Assumps"++show(assumps))

    _actionDates = sort $ bPayDates ++ pCollectionDatesA
    actionDates = case stopDate of
                    Just (AP.StopRunBy d) ->  filter (\x -> case x of
                                                  (RunWaterfall _d _) -> _d < d
                                                  CollectPoolIncome _d -> _d < d ) _actionDates
                    Nothing ->  _actionDates  -- `debug` (">>stop date"++show(stopDate))

    poolCf = P.aggPool $ P.runPool2 (pool t)  assumps  -- `debug` ("Assets Agged pool Cf->"++show(pool t))
    poolCfTs = filter (\txn -> (CF.tsDate txn) > startDate)  $ CF.getTsCashFlowFrame poolCf
    pCollectionCfAfterCutoff = CF.CashFlowFrame $  CF.aggTsByDates poolCfTs pCollectionDates  `debug` ("poolCf Dates"++show(pCollectionDates)) `debug` ("pool cf ts"++show(poolCfTs))
    t_with_cf  = setFutureCF t pCollectionCfAfterCutoff -- `debug` ("aggedCf:->>"++show(pCollectionCfAfterCutoff))
    rateCurves = buildRateCurves [] assumps   -- [RateCurve LIBOR6M (FloatCurve [(TsPoint (T.fromGregorian 2022 1 1) 0.01)])]
    callOptions = buildCallOptions [] assumps -- `debug` ("Assump"++show(assumps))


queryDeal :: TestDeal -> DealStats ->  Float
queryDeal t s =
  case s of
    CurrentBondBalance ->
       Map.foldr (\x acc -> ((L.bndBalance x) + acc)) 0.0 (bonds t)
    OriginalBondBalance ->
       Map.foldr (\x acc -> (L.originBalance (L.bndOriginInfo x)) + acc) 0.0 (bonds t)
    CurrentPoolBalance ->
       foldl (\acc x -> (acc + (P.getCurrentBal x))) 0.0 (P.assets (pool t))
    OriginalPoolBalance ->
       foldl (\acc x -> (acc + (P.getOriginBal x))) 0.0 (P.assets (pool t))
    BondFactor -> 
        (queryDeal t CurrentBondBalance) / (queryDeal t OriginalBondBalance)
    PoolFactor -> 
        (queryDeal t CurrentPoolBalance) / (queryDeal t OriginalPoolBalance)

    FutureOriginalPoolBalance ->
      CF.mflowBalance $ head (CF.getTsCashFlowFrame _pool_cfs)
     where
      _pool_cfs = fromMaybe (CF.CashFlowFrame []) (P.futureCf (pool t))

    FutureCurrentPoolBalance asOfDay ->
         case _poolSnapshot of
            Just ts -> CF.mflowBalance ts
            Nothing -> 0
        where
         _pool_cfs = fromMaybe (CF.CashFlowFrame []) (P.futureCf (pool t))
         _poolSnapshot = CF.getEarlierTsCashFlowFrame _pool_cfs asOfDay

    FutureCurrentPoolFactor asOfDay ->
        (queryDeal t (FutureCurrentPoolBalance asOfDay)) / (queryDeal t FutureOriginalPoolBalance)

    CurrentPoolCollectionInt asOfDay ->
      case (P.futureCf (pool t)) of
        Nothing -> 0
        Just _futureCf ->
          case (CF.getTxnLatestAsOf _futureCf asOfDay) of
            Just flow -> CF.mflowInterest flow
            Nothing -> 0

    CumulativeDefaultBalance asOfDay ->
        case (P.futureCf (pool t)) of
          Just futureCf ->  foldr (\r a -> (CF.tsDefaultBal r) + a)  0  $ CF.getTxnAsOf futureCf asOfDay -- `debug` (">>as of day"++show(asOfDay))
          Nothing -> 0.0


calcDueFee :: TestDeal -> T.Day -> F.Fee -> F.Fee
calcDueFee t calcDay f@(F.Fee fn (F.FixFee amt)  fs fd (Just _fdDay) fa _ _)
  | _fdDay /= calcDay = f{ F.feeDue = amt, F.feeDueDate = Just calcDay}
  | otherwise = f
  
calcDueFee t calcDay f@(F.Fee fn (F.FixFee amt)  fs fd Nothing fa _ _)
  = f{ F.feeDue = amt, F.feeDueDate = Just calcDay}

calcDueFee t calcDay f@(F.Fee fn (F.AnnualRateFee feeBase r) fs fd Nothing fa lpd _)
  = calcDueFee t calcDay f {F.feeDueDate = Just _startDate }

calcDueFee t calcDay f@(F.Fee fn (F.AnnualRateFee feeBase r) fs fd (Just _fdDay) fa lpd _)
  | _fdDay == calcDay = f
  | otherwise = f{ F.feeDue = fd + baseBal * r * (periodToYear feeStartDate calcDay ACT_360)
                            , F.feeDueDate = Just calcDay }
                 where
                     feeStartDate = case lpd of
                                        (Just _lpd) -> _lpd
                                        Nothing -> tClosingDate 
                     baseBal = queryDeal t feeBase
                     tClosingDate = Map.findWithDefault _startDate "closing-date" (dates t)


calcDueInt :: TestDeal -> T.Day -> L.Bond -> L.Bond
calcDueInt t calc_date b@(L.Bond bn L.Z bo bi bond_bal bond_rate _ _ lstIntPay _ _) 
  = b {L.bndDueInt = 0 } 

calcDueInt t calc_date b@(L.Bond bn (L.InterestByYield y) bo bi bond_bal _ _ intDue lstIntPay _ mStmt)
  = b {L.bndDueInt = newDue }
  where
  newDue = L.backoutDueIntByYield calc_date b bond_bal

calcDueInt t calc_date b@(L.Bond bn bt bo bi bond_bal bond_rate _ _ lstIntPay _ _) =
  b {L.bndDueInt = (dueInt+int_arrears) }
  where
    int_arrears = 0
    lastIntPayDay = case lstIntPay of
                      Just pd -> pd
                      Nothing -> Map.findWithDefault _startDate "closing-date" (dates t)
    dueInt = calcInt bond_bal lastIntPayDay calc_date bond_rate ACT_365


calcDuePrin :: TestDeal -> T.Day -> L.Bond -> L.Bond
calcDuePrin t calc_date b@(L.Bond bn L.Sequential bo bi bond_bal _ prin_arr int_arrears _ _ _) =
  b {L.bndDuePrin = duePrin} 
  where
    duePrin = bond_bal 

calcDuePrin t calc_date b@(L.Bond bn (L.Lockout cd) bo bi bond_bal _ prin_arr int_arrears _ _ _) =
  if (cd > calc_date)  then 
    b {L.bndDuePrin = 0}
  else
    b {L.bndDuePrin = duePrin}
  where
    duePrin = bond_bal 

calcDuePrin t calc_date b@(L.Bond bn (L.PAC schedule) bo bi bond_bal _ prin_arr int_arrears _ _ _) =
  b {L.bndDuePrin = duePrin} -- `debug` ("bn >> "++bn++"Due Prin set=>"++show(duePrin) )
  where
    scheduleDue = getValOnByDate schedule calc_date  
    duePrin = max (bond_bal - scheduleDue) 0 -- `debug` ("In PAC ,target balance"++show(schedule)++show(calc_date)++show(scheduleDue))

calcDuePrin t calc_date b@(L.Bond bn L.Z bo bi bond_bal bond_rate prin_arr int_arrears lstIntPay _ _) =
  if (all (\x -> (isZbond x)) activeBnds) then
      b {L.bndDuePrin = bond_bal} -- `debug` ("bn >> "++bn++"Due Prin set=>"++show(duePrin) )
  else 
      b {L.bndDuePrin = 0, L.bndBalance = new_bal, L.bndLastIntPay=Just calc_date} -- `debug` ("bn >> "++bn++"Due Prin set=>"++show(duePrin) )
  where
    isZbond (L.Bond _ bt _ _ _ _ _ _ _ _ _) 
      = case bt of
          L.Z -> True
          _ -> False
    activeBnds = filter (\x -> (L.bndBalance x) > 0) (Map.elems (bonds t))
    new_bal = bond_bal + dueInt
    lastIntPayDay = case lstIntPay of
                      Just pd -> pd
                      Nothing -> Map.findWithDefault _startDate "closing-date" (dates t)
    dueInt = calcInt bond_bal lastIntPayDay calc_date bond_rate ACT_365

calcTargetAmount :: TestDeal -> A.Account -> Float
calcTargetAmount t (A.Account _ n i (Just r) _ ) =
   eval r
   where
     eval ra = case ra of
       A.PctReserve ds _rate -> (queryDeal t ds) * _rate
       A.FixReserve amt -> amt
       A.Max ra1 ra2 -> max (eval ra1) (eval ra2)

depositPoolInflow :: [W.CollectionRule] -> T.Day -> CF.CashFlowFrame -> Map.Map String A.Account -> Map.Map String A.Account
depositPoolInflow rules d cf amap =
  foldl fn amap rules
  where
      currentPoolInflow = CF.getSingleTsCashFlowFrame cf d
      fn _acc _r@(W.Collect _ _accName) =
          Map.adjust (A.deposit collectedCash d "Deposit CF from Pool") _accName _acc
          where 
              collectedCash = collectCash _r currentPoolInflow
      collectCash r ts =
        case  r of
          (W.Collect W.CollectedInterest _)   -> CF.mflowInterest ts
          (W.Collect W.CollectedPrincipal _)  -> CF.mflowPrincipal ts
          (W.Collect W.CollectedRecoveries _) -> CF.mflowRecovery ts
          (W.Collect W.CollectedPrepayment _) -> CF.mflowPrepayment ts

$(deriveJSON defaultOptions ''ExpectReturn)
$(deriveJSON defaultOptions ''TxnComponent)
