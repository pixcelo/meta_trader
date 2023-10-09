// TradingLogic.mqh
input double LargeCandleBodyPips = 5.0;        // 大陽線・大陰線のローソク足の実体のpips
input double RiskRewardRatio = 1.0;            // リスクリワード比
input double ResetPipsDistance = 20;           // トレンド転換ラインがローソク足と何pips離れたらリセットするか
input int lineToucedCount = 3;                 // トレンド転換ラインに価格が接触した回数(回数が多いと固いライン)
input int Depth = 7;                           // ZigzagのDepth設定
input int Deviation = 5;                       // ZigzagのDeviation設定
input int Backstep = 3;                        // ZigzagのBackstep設定
input int SpreadThresholdPips = 5;             // スプレッド閾値(pips)
input int ConsecutiveCount = 6;                // 連続して上昇・下降した回数
input int StableCount = 2;                     // 上昇・下降の後に安定した回数
input int zigzagTerm = 240;                    // 極値を計算する期間
input int MaxHoldingMinutes = 60;              // ポジション保有時間の最大
input int MaxProfitPips = 10;                  // ポジションを閉じる際に許容する利益幅
input int MinLossPips = 10;                    // ポジションを閉じる際に許容する損切り幅
input int Magic = 19850001;                    // マジックナンバー（EAの識別番号）
input int lastTradeIntervalSeconds = 300;      // 最後のトレードからの間隔(秒)

input bool EnableLogging = true;               // ログ出力
input bool Visualmode = true;                  // 描画

#include "ZigzagSeeker.mqh"
#include "ChartDrawer.mqh"
#include "OrderManager.mqh"
#include "LotManager.mqh"
#include "PrintManager.mqh"
#include "Utility.mqh"

class TradingLogic
{
private:
    ZigzagSeeker zzSeeker;
    ChartDrawer chartDrawer;
    OrderManager orderMgr;
    LotManager lotMgr;
    PrintManager printer;
    Utility utility;

    double highestPrice;      // 最高値（ショートの損切ライン）
    double lowestPrice;       // 最安値（ロングの損切ライン）
    datetime lastTradeTime;   // 最後にトレードした時間

    enum TradeAction
    {
        WAIT = 0,
        BUY  = 1,
        SELL = 2
    };

    double trendReversalLineForLong;
    double trendReversalLineForShort;

    struct TrendLine {
        double value;
        double touchedValues[];
        TradeAction action;
    };

    TrendLine trendLine;

    // 関数呼び出しは計算コストが掛かるため変数に格納する
    string symbol;
    int timeframe;

public:
    TradingLogic() {
        zzSeeker.Initialize(Depth, Deviation, Backstep);
        lotMgr.SetRiskPercentage(2.0);
        printer.EnableLogging(EnableLogging);

        symbol = Symbol();
        timeframe = PERIOD_CURRENT;
    }
        
    void Initialize() {
        highestPrice = -1;
        lowestPrice = -1;
        trendReversalLineForLong = 0;
        trendReversalLineForShort = 0;

        trendLine.value = 0;
        ArrayResize(trendLine.touchedValues, 0);
        trendLine.action = WAIT;
    }

    void Execute() {
        printer.PrintLog("Trade executed.");
        printer.ShowCounts();
    }
   
    void TradingStrategy() 
    {
        if (utility.IsSpreadTooHigh(symbol, SpreadThresholdPips)) {
             printer.PrintLog("Spread too high");
             return;
        }

        if (OrdersTotal() > 0) {
            // トレイルストップ
            //orderMgr.ApplyTrailingStop(10, 10);

            // 途中決済
            orderMgr.CheckAndCloseStagnantPositions(MaxHoldingMinutes, -MinLossPips, MaxProfitPips);
            Initialize();
            return;
        }

        // Set up
        zzSeeker.UpdateExtremaArray(zigzagTerm, 50);

        /// ==========================test=====================
        // Print values to check if they are populated correctly
        // Print("zigzag Values: ");
        // for (int k = 0; k < ArraySize(ExtremaArray); k++) {
        //     Print("Timestamp: ", ExtremaArray[k].timestamp, ", Value: ", ExtremaArray[k].value, " isPeak:", ExtremaArray[k].isPeak);
        // }

        // Entry check
        JudgeEntryCondition();

        // Draw objects
        if (Visualmode) {
            chartDrawer.DrawTrendReversalLine(trendReversalLineForLong, trendReversalLineForShort);
            chartDrawer.DrawPeaksAndValleys(ExtremaArray, 50);
        }
    }

private:
    // 下降トレンド転換ラインを取得
    double GetTrendReversalLineForShort(int term) {
        int len = ArraySize(ExtremaArray);
        double highestValue = -DBL_MAX;
        double trendReversalLine = 0;

        // 直近の期間内で最高の極大値の起点となった谷をトレンド転換ラインとする
        for (int i = 0; i < term; i++) {
            Extremum ex = ExtremaArray[i];
            if (!ex.isPeak) {
                continue;
            }
            if (highestValue <= ex.value) {
                highestValue = ex.value;
                trendReversalLine = ex.prevValue;
                
                // 損切ラインとして保存
                highestPrice = ex.value;
            }
        }

        return trendReversalLine;
    }

    // 上昇トレンド転換ラインを取得
    double GetTrendReversalLineForLong(int term) {
        int len = ArraySize(ExtremaArray);
        double lowestValue = DBL_MAX;
        double trendReversalLine = 0;

        // 直近の期間内で最安の極小値の起点となったピークをトレンド転換ラインとする
        for (int i = 0; i < term; i++) {
            Extremum ex = ExtremaArray[i];
            if (ex.isPeak) {
                continue;
            }
            if (lowestValue >= ex.value) {
                lowestValue = ex.value;
                trendReversalLine = ex.prevValue;
                
                // 損切ラインとして保存
                lowestPrice = ex.value;
            }
        }

        return trendReversalLine;
    }

    void JudgeEntryCondition() {
        // 値動きから行動を選択
        TradeAction action = JudgeTradeAction();

        // レンジの場合
        if (action == WAIT) {
            return;
        }

        if (action == BUY && IsLongBreakOut(10)) {
            BuyOrder();
            //BuyTrailOrder();
        }

        if (action == SELL && IsShortBreakOut(10)) {
            SellOrder();
            //SellTrailOrder();
        }
    }
    
    // N本以内での上抜け + 大陽線の確定でロングブレイクアウト
    bool IsLongBreakOut(int term) {
        if (TimeCurrent() - lastTradeTime < lastTradeIntervalSeconds) {
            return false;
        }

        if (!IsConsecutiveRise(2, 5)) {
            return false;
        }

        if (FilterByLineTouchedValues(lineToucedCount)) {
            return false;
        }

        int passCount = 0;
        for (int i = 0; i < term; i++) {
            if (Close[i + 1] < trendReversalLineForLong && trendReversalLineForLong < Close[i]) {
                passCount++;
                break;
            }
        }
        
        if (passCount == 0) {
            return false;
        }

        if (!IsExceptionallyLargeCandle(0)) {
            return false;
        }
        
        if (Close[0] < iMA(symbol, timeframe, 100, 0, MODE_EMA, PRICE_CLOSE, 0)) {
            return false;
        }

        return true;
    }

    // N本以内での下抜け + 大陰線の確定でショートブレイクアウト
    bool IsShortBreakOut(int term) {
        if (TimeCurrent() - lastTradeTime < lastTradeIntervalSeconds) {
            return false;
        }

        if (!IsConsecutiveFall(2, 5)) {
            return false;
        }

        if (FilterByLineTouchedValues(lineToucedCount)) {
            return false;
        }

        int passCount = 0; 
        for (int i = 0; i < term; i++) {
            if (Close[i] < trendReversalLineForShort && trendReversalLineForShort < Close[i + 1]) {
                passCount++;
                break;
            }
        }
        
        if (passCount == 0) {
            return false;
        }

        if (!IsExceptionallyLargeCandle(0)) {
            return false;
        }
        
        if (Close[0] > iMA(symbol, timeframe, 100, 0, MODE_EMA, PRICE_CLOSE, 0)) {
            return false;
        }

        return true;
    }

    // 反発回数が多い場合、ブレイクアウトが困難になる
    bool FilterByLineTouchedValues(int n) {
        int len = ArraySize(trendLine.touchedValues);
        return len >= n;
    }

    // ローソク足の大きさを確認
    bool IsExceptionallyLargeCandle(int shift)
    {
        double openPrice = iOpen(symbol, timeframe, shift);
        double closePrice = iClose(symbol, timeframe, shift);
        double highPrice = iHigh(symbol, timeframe, shift);
        double lowPrice = iLow(symbol, timeframe, shift);

        double bodyLength = MathAbs(closePrice - openPrice); // 実体の絶対値を取得
        double compareBody = MaximumBodyLength(20, shift +1);
        double wickLength;

        if(closePrice > openPrice) // 陽線の場合
            wickLength = highPrice - closePrice; // 上ヒゲの長さ
        else
            wickLength = openPrice - lowPrice; // 下ヒゲの長さ

        // 直近20本で比較的大きい（またはNpips以上）でヒゲが小さいローソク足
        return (bodyLength > compareBody
            && bodyLength >= LargeCandleBodyPips * Point * utility.GetPointCoefficient())
            && wickLength < bodyLength * 0.3;
    }

    double MaximumBodyLength(int barsToConsider, int startShift)
    {
        double maxBodyLength = 0;
        for(int i = 0; i < barsToConsider; i++)
        {
            double openPrice = iOpen(symbol, timeframe, i + startShift);
            double closePrice = iClose(symbol, timeframe, i + startShift);
            double bodyLength = MathAbs(closePrice - openPrice);
            
            if(bodyLength > maxBodyLength)
                maxBodyLength = bodyLength;
        }
        return maxBodyLength;
    }

    // ローソク足の値動きからエントリータイミングをチェックする
    // レンジ：  "WAIT"  スキップして待つ
    // 下降傾向："BUY"   ロングへのトレンド転換を狙う
    // 上昇傾向："SELL"  ショートへのトレンド転換を狙う
    TradeAction JudgeTradeAction() { 
        // 連続で上昇しているかを確認する
        if (IsConsecutiveRiseAndStabilize(ConsecutiveCount, StableCount, 0.05)
            || IsContinuouslyAwayFromEMA100ByPips(10, 60, true)
            ) { //IsConsecutiveRise(ConsecutiveCount)) {
            // 下降トレンド転換ラインの設定
            trendReversalLineForShort = GetTrendReversalLineForShort(10);
            if (trendReversalLineForShort <= 0) {
                printer.PrintLog("下降トレンド転換ラインが設定できなかった");
            } else {
                trendReversalLineForLong = 0;
                trendLine.value = trendReversalLineForShort;
                trendLine.action = SELL;
                GetTouchedValues(5);
            }
        }

        // 連続で下降しているかを確認する
        if (IsConsecutiveFallAndStabilize(ConsecutiveCount, StableCount, 0.05)
            || IsContinuouslyAwayFromEMA100ByPips(10, 60, false)
            ) { //IsConsecutiveFall(ConsecutiveCount)) {
            // 上昇トレンド転換ラインの設定
            trendReversalLineForLong = GetTrendReversalLineForLong(10);
            if (trendReversalLineForLong <= 0) {
                printer.PrintLog("上昇トレンド転換ラインが設定できなかった");
            } else {
                trendReversalLineForShort = 0;
                trendLine.value = trendReversalLineForLong;
                trendLine.action = BUY;
                GetTouchedValues(5);
            }
        }

        //double hLine = FindMostTouchedPrice(highBuffer, lowBuffer, 5, 2);
        //Print("hLine: ", hLine);

        //ResetTrendReversalLineIfTooFar(ResetPipsDistance);

        // if (trendLine.value > 0) {
        //     int len = ArraySize(trendLine.touchedValues);

        //     if (trendLine.action == BUY && len >= 3) {
        //         Print("反発狙い1");
        //         // buy狙いだが反発の可能せいがありため　 sell
        //         // たっちで反対売買
        //         if (Close[1] > trendLine.value
        //             && Close[0] < trendLine.value) {
        //                 // 直近高値を損切ラインに設定
        //                 // 利確は逆方向に計算
        //                 SellOrder();
        //                 Print("反発sell");
        //             }
        //     }
            
        //     if (trendLine.action == SELL && len >= 3) {
        //         Print("反発狙い2");
        //         // sell狙いだが反発の可能せいがありため　return sell
        //         if (Close[1] < trendLine.value
        //             && Close[0] > trendLine.value) {
        //                 // 直近高値を損切ラインに設定
        //                 // 利確は逆方向に計算
        //                 BuyOrder();
        //                 Print("反発buy");
        //             }
        //     }
        // }

        if (trendReversalLineForShort > 0) {
            return SELL;
        }

        if (trendReversalLineForLong > 0) {
            return BUY;
        }

        return WAIT;
    }

    // トレンド転換ラインがローソク足と逆方向に指定したpips離れている場合、リセット
    void ResetTrendReversalLineIfTooFar(double pipsDistance) {
        pipsDistance *= Point * utility.GetPointCoefficient(); // pips to price value

        if (trendReversalLineForShort > 0) {
            if (Close[0] < trendReversalLineForShort - pipsDistance) { 
                trendReversalLineForShort = 0;
            }
        }

        if (trendReversalLineForLong > 0) {
            if (Close[0] > trendReversalLineForLong + pipsDistance) {
                trendReversalLineForLong = 0;
            }
        }
    }

    // ピークと谷が連続してN回下降した後に、横ばいか上昇をした価格の推移を検知する（ショートエントリー用）
    // ダウ理論の更新が続くことが条件（高値が上に更新しない限りは下降トレンドとみる）
    bool IsConsecutiveFallAndStabilize(int N, int M, double epsilon) {
        int len = ArraySize(ExtremaArray);
        int highCount = 0;
        int lowCount = 0;
        int stableCount = 0;
        double lastHighValue = DBL_MAX;
        double lastLowValue = DBL_MAX;

        for (int i = len - 1; i >= 0; i--) {
            Extremum ex = ExtremaArray[i];

            if (ex.isPeak) {
                if (ex.value < lastHighValue) {
                    lastHighValue = ex.value;
                    highCount++;
                } else {
                    highCount = 0;
                    lowCount = 0;
                    lastHighValue = DBL_MAX;
                    lastLowValue = DBL_MAX;
                }
            } else {
                if (ex.value < lastLowValue) {
                    lastLowValue = ex.value;
                    lowCount++;
                }
            }

            if (highCount >= N && lowCount >= N) {
                // N回の連続下落を確認した後に、M回の安定を確認する
                for (int j = i; j >= 0; j--) {
                    Extremum nextEx = ExtremaArray[j];

                    if (!nextEx.isPeak) {
                        if (MathAbs(nextEx.value - lastLowValue) <= epsilon) {
                            stableCount++;
                            lastLowValue = nextEx.value;
                        } else {
                            break;
                        }
                    }

                    if (stableCount >= M) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    // ピークと谷が連続してN回上昇した後に、横ばいか下降をした価格の推移を検知する（ロングエントリー用）
    // ダウ理論の上昇の更新が続くことが条件（安値が下に更新しない限りは上昇トレンドとみる）
    bool IsConsecutiveRiseAndStabilize(int N, int M, double epsilon) {
        int len = ArraySize(ExtremaArray);
        int highCount = 0;
        int lowCount = 0;
        int stableCount = 0; // 安定しているかをカウントする新しい変数
        double lastHighValue = -DBL_MAX; // 上昇を検知するための変数を初期化
        double lastLowValue = -DBL_MAX;  // 上昇を検知するための変数を初期化

        for (int i = len - 1; i >= 0; i--) {
            Extremum ex = ExtremaArray[i];

            if (ex.isPeak) {
                if (ex.value > lastHighValue) {
                    lastHighValue = ex.value;
                    highCount++;
                }
            } else {
                if (ex.value > lastLowValue) {
                    lastLowValue = ex.value;
                    lowCount++;
                } else {
                    highCount = 0;
                    lowCount = 0;
                    lastHighValue = -DBL_MAX;
                    lastLowValue = -DBL_MAX;
                }
            }

            if (highCount >= N && lowCount >= N) {
                // N回の連続上昇を確認した後に、M回の安定を確認する
                for (int j = i; j >= 0; j--) {
                    Extremum nextEx = ExtremaArray[j];

                    if (!nextEx.isPeak) { 
                        if (MathAbs(nextEx.value - lastLowValue) <= epsilon) {
                            stableCount++;
                            lastLowValue = nextEx.value;
                        } else {
                            break; 
                        }
                    }

                    if (stableCount >= M) {
                        return true; 
                    }
                }
            }
        }

        return false; 
    }

    // 期間内で直近のピークと谷が連続してN回上昇したかを判定する
    bool IsConsecutiveRise(int N, int term) {
        int len = ArraySize(ExtremaArray);
        int highCount = 0;
        int lowCount = 0;
        double lastHighValue = DBL_MAX;
        double lastLowValue = DBL_MAX;

        for (int i = 0; i < term; i++) {
            Extremum ex = ExtremaArray[i];

            if (ex.isPeak) {
                if (ex.value < lastHighValue) {
                    lastHighValue = ex.value;
                    highCount++;
                }
            } else {
                if (ex.value < lastLowValue) {
                    lastLowValue = ex.value;
                    lowCount++;
                } else {
                    highCount = 0;
                    lowCount = 0;
                    lastHighValue = DBL_MAX;
                    lastLowValue = DBL_MAX;
                }
            }

            if (highCount >= N && lowCount >= N) {
                break;
            }
        }

        return highCount >= N && lowCount >= N;
    }

    // 期間内で直近のピークと谷が連続してN回下降したかを判定する
    bool IsConsecutiveFall(int N, int term) {
        int len = ArraySize(ExtremaArray);
        int highCount = 0;
        int lowCount = 0;
        double lastHighValue = -DBL_MAX;
        double lastLowValue = -DBL_MAX;

        for (int i = 0; i < term; i++) {
            Extremum ex = ExtremaArray[i];

            if (ex.isPeak) {
                if (ex.value > lastHighValue) {
                    lastHighValue = ex.value;
                    highCount++;
                } else {
                    highCount = 0;
                    lowCount = 0;
                    lastHighValue = -DBL_MAX;
                    lastLowValue = -DBL_MAX;
                }
            } else {
                if (ex.value > lastLowValue) {
                    lastLowValue = ex.value;
                    lowCount++;
                }
            }

            if (highCount >= N && lowCount >= N) {
                break;
            }
        }

        return highCount >= N && lowCount >= N;
    }

    double FindMostTouchedPrice(double &highs[], double &lows[], double zoneWidth, int minTouches)
    {
        double allExtremas[];
        ArrayResize(allExtremas, ArraySize(highs) + ArraySize(lows));
        ArrayCopy(allExtremas, highs);
        ArrayCopy(allExtremas, lows, 0, ArraySize(highs), WHOLE_ARRAY);
        
        int mostTouches = minTouches;
        double mostTouchedPrice = -1;
        for(int i = 0; i < ArraySize(allExtremas); ++i)
        {
            int touches = 0;
            for(int j = 0; j < ArraySize(allExtremas); ++j)
            {
                if(i != j && MathAbs(allExtremas[i] - allExtremas[j]) <= zoneWidth)
                    touches++;
            }
            if(touches >= mostTouches)
            {
                mostTouches = touches;
                mostTouchedPrice = allExtremas[i];
            }
        }
        return mostTouchedPrice;
    }

    // EMA100から特定のpips数以上離れて連続しているかを判定する関数
    bool IsContinuouslyAwayFromEMA100ByPips(double pipsDistance, int barsToCheck = 100, bool checkAbove = false) {
        double distance = pipsDistance * Point * utility.GetPointCoefficient();

        int countAwayFromEMA = 0;
        for (int i = 0; i < barsToCheck; i++) {
            double ema100 = iMA(NULL, 0, 100, 0, MODE_EMA, PRICE_CLOSE, i);
            if (checkAbove) {
                if (Close[i] > ema100 + distance) {
                    countAwayFromEMA++;
                } else {
                    break;
                }
            } else {
                if (Close[i] < ema100 - distance) {
                    countAwayFromEMA++;
                } else {
                    break;
                }
            }
        }

        return countAwayFromEMA == barsToCheck;
    }

    // 損切り幅が10pips未満なら10pipsを損切り幅とする
    double CalculateStopLoss(TradeAction action, double entryPrice, double recentExtremum, double pipsDistance) {
        double minStopDistance = pipsDistance * Point * utility.GetPointCoefficient();
        
        if(action == BUY) {
            if (entryPrice - recentExtremum < minStopDistance) {
                return entryPrice - minStopDistance;
            } else {
                return recentExtremum;
            }
        } else if(action == SELL) {
            if (recentExtremum - entryPrice < minStopDistance) {
                return entryPrice + minStopDistance;
            } else {
                return recentExtremum;
            }
        }
        return 0;
    }

    // 資金に対して適切なロットサイズを計算する
    double GetLotSize(TradeAction action, double stopLossPrice) {
        double entryPrice = MarketInfo(symbol, MODE_BID);

        if (action == BUY) {
            entryPrice = MarketInfo(symbol, MODE_ASK);
            stopLossPrice = lowestPrice;
        }
        
        double stopLossPips = lotMgr.PriceDifferenceToPips(entryPrice, stopLossPrice);
        double lotSize = lotMgr.CalculateLot(stopLossPips);
        return lotSize;
    }

     void BuyOrder() {
        int lowBar = iLowest(symbol, timeframe, MODE_LOW, 1, 1);
        double latestLow = iLow(symbol, timeframe, lowBar);
        double stopLossPrice = CalculateStopLoss(BUY, MarketInfo(symbol, MODE_ASK), latestLow, 10);
        double lotSize = GetLotSize(BUY, stopLossPrice);
        int result = orderMgr.PlaceBuyOrder(lotSize, stopLossPrice, RiskRewardRatio, Magic);
        if (result > 0) {
            Initialize();
            lastTradeTime = TimeCurrent();
        }
    }

    void SellOrder() {
        int highBar = iHighest(symbol, timeframe, MODE_HIGH, 1, 1);
        double latestHigh = iHigh(symbol, timeframe, highBar);
        double stopLossPrice = CalculateStopLoss(SELL, MarketInfo(symbol, MODE_BID), latestHigh, 10);
        double lotSize = GetLotSize(SELL, stopLossPrice);
        int result = orderMgr.PlaceSellOrder(lotSize, stopLossPrice, RiskRewardRatio, Magic);
        if (result > 0) {
            Initialize();
            lastTradeTime = TimeCurrent();
        }
    }

    void BuyTrailOrder() {
        int lowBar = iLowest(symbol, timeframe, MODE_LOW, 1, 1);
        double latestLow = iLow(symbol, timeframe, lowBar);
        double stopLossPrice = CalculateStopLoss(BUY, MarketInfo(symbol, MODE_ASK), latestLow, 10);
        double lotSize = GetLotSize(BUY, stopLossPrice);
        int result = orderMgr.PlaceBuyOrderForTrailingStop(lotSize, stopLossPrice, Magic);
        if (result > 0) {
            Initialize();
            lastTradeTime = TimeCurrent();
        }
    }

    void SellTrailOrder() {
        int highBar = iHighest(symbol, timeframe, MODE_HIGH, 1, 1);
        double latestHigh = iHigh(symbol, timeframe, highBar);
        double stopLossPrice = CalculateStopLoss(SELL, MarketInfo(symbol, MODE_BID), latestHigh, 10);
        double lotSize = GetLotSize(SELL, stopLossPrice);
        int result = orderMgr.PlaceSellOrderForTrailingStop(lotSize, stopLossPrice, Magic);
        if (result > 0) {
            Initialize();
            lastTradeTime = TimeCurrent();
        }
    }

    // トレンド転換ラインに近い値の極値を反発（または近づいた値）として格納する => ±N pips以内の値
    void GetTouchedValues(double pips) {
        double pipsRange = pips * Point * utility.GetPointCoefficient();
        ArrayResize(trendLine.touchedValues, 0);
        int len = ArraySize(ExtremaArray);
        
        for (int i = 0; i < len; i++) {
            // 現在のトレンドラインの価格とExtremaArrayの各価格との差が範囲内であれば配列に追加
            // Print(MathAbs(trendLine.value - ExtremaArray[i].value));
            // Print("range", pipsRange);
            if (MathAbs(trendLine.value - ExtremaArray[i].value) <= pipsRange) {
                ArrayResize(trendLine.touchedValues, ArraySize(trendLine.touchedValues) + 1);
                trendLine.touchedValues[ArraySize(trendLine.touchedValues) - 1] = ExtremaArray[i].value;
            }
        }
    }

};