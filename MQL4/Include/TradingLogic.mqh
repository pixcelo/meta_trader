// TradingLogic.mqh
input double LargeCandleBodyPips = 4.0;        // 大陽線・大陰線のローソク足の実態のpips
input double RiskRewardRatio = 1.0;            // リスクリワード比
input double ResetPipsDistance = 20;           // トレンド転換ラインがローソク足と何pips離れたらリセットするか
input int Depth = 7;                           // ZigzagのDepth設定
input int Backstep = 3;                        // ZigzagのBackstep設定
input double SpreadThreshold = 0.05;           // スプレッド閾値
input int ConsecutiveCount = 5;                // 連続して上昇・下降した回数
input int DataPeriod = 700;                    // 極値を計算する期間
input int MaxHoldingMinutes = 60;              // ポジションの保有時間の最大
input int MaxProfitPips = 10;                  // ポジションを閉じる際に許容する利益幅
input int MinLossPips = 10;                    // ポジションを閉じる際に許容する損切り幅
input int Magic = 19850001;                    // マジックナンバー（EAの識別番号）

#include "LocalExtremaSeeker.mqh"
#include "ChartDrawer.mqh"
#include "OrderManager.mqh"
#include "LotManager.mqh"
#include "PrintManager.mqh"

class TradingLogic
{
private:
    LocalExtremaSeeker extremaSeeker;
    ChartDrawer chartDrawer;
    OrderManager orderMgr;
    LotManager lotMgr;
    PrintManager printer;

    double highestPrice;      // 最高値（ショートの損切ライン）
    double lowestPrice;       // 最安値（ロングの損切ライン）
    datetime highestTime;     // 最高値をつけた時間
    datetime lowestTime;      // 最安値をつけた時間

    double trendReversalLineForLong;
    double trendReversalLineForShort;

    enum TradeAction
    {
        WAIT = 0,
        BUY  = 1,
        SELL = 2
    };

public:
    TradingLogic() {
            extremaSeeker.Initialize(Depth, Backstep);
            lotMgr.SetRiskPercentage(2.0);
            printer.EnableLogging(false);
            Initialize();
        }
        
    void Initialize() {
        highestPrice = -1;
        lowestPrice = -1;
        trendReversalLineForLong = 0;
        trendReversalLineForShort = 0;
    }

    void Execute() {
        printer.PrintLog("Trade executed.");
        printer.ShowCounts();
    }
   
    void TradingStrategy() 
    { 
        DisplayInfo();

        if (IsSpreadTooHigh()) {
             printer.PrintLog("Spread too high");
             return;
        }

        if (OrdersTotal() > 0) {
            // 途中決済
            orderMgr.CheckAndCloseStagnantPositions(MaxHoldingMinutes, -MinLossPips, MaxProfitPips);
            Initialize();
            return;
        }

        chartDrawer.DrawTrendReversalLine(trendReversalLineForLong, trendReversalLineForShort);
   
        // Set up
        extremaSeeker.UpdatePeaksAndValleys(DataPeriod);
        JudgeEntryCondition();
    }

private:
    // スプレッド拡大への対応
    bool IsSpreadTooHigh()
    {
        double bid = MarketInfo(Symbol(), MODE_BID);
        double ask = MarketInfo(Symbol(), MODE_ASK);

        return (ask - bid) > SpreadThreshold;
    }

    // 下降トレンド転換ラインを取得
    double GetTrendReversalLineForShort() {
        int valleyValuesLength = ArraySize(extremaSeeker.valleyValues);
        double previousValley = -1;

        // 最高値の一つ前の谷を見つける
        for (int i = 0; i < valleyValuesLength; i++) {
            if (extremaSeeker.valleyTimestamps[i] < highestTime) {
                previousValley = extremaSeeker.valleyValues[i];
                break;
            }
        }

        return previousValley;
    }

    // 上昇トレンド転換ラインを取得
    double GetTrendReversalLineForLong() {
        int peakValuesLength = ArraySize(extremaSeeker.peakValues);
        double previousPeak = -1;

        // 最安値の一つ前のピークを見つける
        for (int i = 0; i < peakValuesLength; i++) {
            if (extremaSeeker.peakTimestamps[i] < lowestTime) {
                previousPeak = extremaSeeker.peakValues[i];
                break;
            }
        }

        return previousPeak;
    }

    // ローソク足の大きさを確認（直近20本で一番大きく、ヒゲが実態の3割未満）
    bool IsExceptionallyLargeCandle(int shift)
    {
        double openPrice = iOpen(Symbol(), Period(), shift);
        double closePrice = iClose(Symbol(), Period(), shift);
        double highPrice = iHigh(Symbol(), Period(), shift);
        double lowPrice = iLow(Symbol(), Period(), shift);

        double bodyLength = MathAbs(closePrice - openPrice); // 実体の絶対値を取得
        double maxBody = MaximumBodyLength(20, shift + 1);
        double wickLength;

        if(closePrice > openPrice) // 陽線の場合
            wickLength = highPrice - closePrice; // 上ヒゲの長さ
        else
            wickLength = openPrice - lowPrice; // 下ヒゲの長さ

        return bodyLength > maxBody 
            && bodyLength >= LargeCandleBodyPips * Point
            && wickLength < bodyLength * 0.3; // ヒゲが実体の3割未満
    }

    double MaximumBodyLength(int barsToConsider, int startShift)
    {
        double maxBodyLength = 0;
        for(int i = 0; i < barsToConsider; i++)
        {
            double openPrice = iOpen(Symbol(), Period(), i + startShift);
            double closePrice = iClose(Symbol(), Period(), i + startShift);
            double bodyLength = MathAbs(closePrice - openPrice);
            
            if(bodyLength > maxBodyLength)
                maxBodyLength = bodyLength;
        }
        return maxBodyLength;
    }

    void JudgeEntryCondition() {
        // 値動きから行動を選択
        TradeAction action = JudgeTradeAction();

        // レンジの場合
        if (action == WAIT) {
            return;
        }

        // トレンド転換ラインが設定されている場合、大陽線で上抜けしたかを判定する
        if (action == BUY) {
            if (Close[1] < trendReversalLineForLong
                && Close[0] > trendReversalLineForLong
                && IsExceptionallyLargeCandle(0)
                && Close[0] > iMA(Symbol(), Period(), 100, 0, MODE_EMA, PRICE_CLOSE, 0)) {

                int lowBar = iLowest(Symbol(), Period(), MODE_LOW, 1, 1);
                double latestLow = iLow(Symbol(), Period(), lowBar);
                double stopLossPriceBuy = CalculateStopLossForLong(MarketInfo(Symbol(), MODE_ASK), latestLow, 10);
                double lotSizeBuy = GetLotSize(BUY, stopLossPriceBuy);
                int resultBuy = orderMgr.PlaceBuyOrder(lotSizeBuy, stopLossPriceBuy, RiskRewardRatio, Magic);
                if (resultBuy > 0) {
                    Initialize();
                }
            }
        }

        // トレンド転換ラインが設定されている場合、大陰線で下抜けしたかを判定する　(TODO: or 連続陰線 or ローソク足高値安値連続切り下げ)
        if (action == SELL) {
            if (Close[1] > trendReversalLineForShort
                && Close[0] < trendReversalLineForShort
                && IsExceptionallyLargeCandle(0)
                && Close[0] < iMA(Symbol(), Period(), 100, 0, MODE_EMA, PRICE_CLOSE, 0)) {

                int highBar = iHighest(Symbol(), Period(), MODE_HIGH, 1, 1);
                double latestHigh = iLow(Symbol(), Period(), highBar);
                double stopLossPriceSell = CalculateStopLossForShort(MarketInfo(Symbol(), MODE_BID), latestHigh, 10);
                double lotSizeSell = GetLotSize(SELL, stopLossPriceSell);
                int resultSell = orderMgr.PlaceSellOrder(lotSizeSell, stopLossPriceSell, RiskRewardRatio, Magic);
                if (resultSell > 0) {
                    Initialize();
                }
            }
        }
    }

    // ローソク足の値動きからエントリータイミングをチェックする
    // レンジ：  "WAIT"  スキップして待つ
    // 下降傾向："BUY"   ロングへのトレンド転換を狙う
    // 上昇傾向："SELL"  ショートへのトレンド転換を狙う
    TradeAction JudgeTradeAction() { 
        // 連続で上昇しているかを確認する
        //if (IsConsecutiveRise(ConsecutiveCount) || IsContinuouslyRisingAboveEMA100ByPips(10, 100)) {
        if (IsConsecutiveRise(ConsecutiveCount)) {
            // 直近の最高値を取得
            GetHighestValue(20);

            // 下降トレンド転換ラインの設定
            trendReversalLineForShort = GetTrendReversalLineForShort();
            if (trendReversalLineForShort <= 0) {
                printer.PrintLog("下降トレンド転換ラインが設定できなかった");
            }
        }

        // 連続で下降しているかを確認する
        //if (IsConsecutiveFall(ConsecutiveCount) || IsContinuouslyDroppingBelowEMA100ByPips(10, 100)) {
        if (IsConsecutiveFall(ConsecutiveCount)) {
            // 直近の最安値を取得
            GetLowestValue(20);

            // 上昇トレンド転換ラインの設定
            trendReversalLineForLong = GetTrendReversalLineForLong();
            if (trendReversalLineForLong <= 0) {
                printer.PrintLog("上昇トレンド転換ラインが設定できなかった");
            }
        }

        ResetTrendReversalLineIfTooFar(ResetPipsDistance);

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
        pipsDistance *= Point; // pips to price value

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

    // ピークと谷が連続してN回上昇したかを判定する（ショートエントリー用）
    bool IsConsecutiveRise(int N) {
        int peakValuesLength = ArraySize(extremaSeeker.peakValues);
        int valleyValuesLength = ArraySize(extremaSeeker.valleyValues);

        if (peakValuesLength < N || valleyValuesLength < N) {
            return false;
        }

        int highCount = 0;
        double lastValue = DBL_MAX;

        // peakValuesLength[0]が最新の極値        
        for (int i = 0; i < peakValuesLength; i++) {
            if (extremaSeeker.peakValues[i] < lastValue) {
                lastValue = extremaSeeker.peakValues[i];
                highCount++;
                if (highCount == N) {
                    break;
                }
            } else {
                lastValue = DBL_MAX;
                highCount = 0;
            }
        }

        int lowCount = 0;
        double lastLowValue = DBL_MAX;

        for (int j = 0; j < valleyValuesLength; j++) {
            if (extremaSeeker.valleyValues[j] < lastLowValue) {
                lastLowValue = extremaSeeker.valleyValues[j];
                lowCount++;
                if (lowCount == N) {
                    break;
                }
            } else {
                lastLowValue = DBL_MAX;
                lowCount = 0;
            }
        }

        printer.PrintLog("Rise highCount: " + highCount + " lowCount: " +  lowCount);
        return highCount >= N && lowCount >= N;
    }

    // ピークと谷が連続してN回下降した回数の最大値を判定する（ロングエントリー用）
    bool IsConsecutiveFall(int N) {
        int peakValuesLength = ArraySize(extremaSeeker.peakValues);
        int valleyValuesLength = ArraySize(extremaSeeker.valleyValues);

        if (peakValuesLength < N || valleyValuesLength < N) {
            return false;
        }

        int highCount = 0;
        double lastValue = -DBL_MAX;

        // peakValuesLength[0]が最新の極値
        for (int i = 0; i < peakValuesLength; i++) {
            if (extremaSeeker.peakValues[i] > lastValue) {
                lastValue = extremaSeeker.peakValues[i];
                highCount++;
                if (highCount == N) {
                    break;
                }
            } else {
                lastValue = -DBL_MAX;
                highCount = 0;
            }
        }

        int lowCount = 0;
        double lastLowValue = -DBL_MAX;

        for (int j = 0; j < valleyValuesLength; j++) {
            if (extremaSeeker.valleyValues[j] > lastLowValue) {
                lastLowValue = extremaSeeker.valleyValues[j];
                lowCount++;
                if (lowCount == N) {
                    break;
                }
            } else {
                lastValue = -DBL_MAX;
                lowCount = 0;
            }
        }

        printer.PrintLog("Rise highCount: " + highCount + " lowCount: " +  lowCount);
        return highCount >= N && lowCount >= N;
    }

    // TEST : ローソク足が連続で
    // bool IsConsecutiveCandleFall(int N, int startBar, int endBar) {
    //     if (startBar < endBar || endBar >= Bars) {
    //         return false; // 不正な引数またはBarsの数がendBarより少ない場合はfalseを返す
    //     }

    //     int highCount = 0;
    //     double lastHighValue = High[startBar];

    //     for (int i = startBar+1; i <= endBar; i++) {
    //         if (High[i] > lastHighValue) {
    //             highCount++;
    //             lastHighValue = High[i];
    //         } else {
    //             highCount = 0;
    //             lastHighValue = High[i];
    //         }

    //         if (highCount >= N) {
    //             break; // 既にNを超えているのでループを抜ける
    //         }
    //     }

    //     int lowCount = 0;
    //     double lastLowValue = Low[startBar];

    //     for (int j = startBar+1; j <= endBar; j++) {
    //         if (Low[j] > lastLowValue) {
    //             lowCount++;
    //             lastLowValue = Low[j];
    //         } else {
    //             lowCount = 0;
    //             lastLowValue = Low[j];
    //         }

    //         if (lowCount >= N) {
    //             break; // 既にNを超えているのでループを抜ける
    //         }
    //     }

    //     return highCount >= N && lowCount >= N; 
    // }

    // EMA100から特定のpips数以上離れて連続して上昇しているかを判定する関数
    bool IsContinuouslyRisingAboveEMA100ByPips(double pipsDistance, int barsToCheck = 100) {
        int currentBar = 0;
        double ema100;
        double distance = pipsDistance * Point;

        int countAboveEMA = 0;
        for(int i = currentBar; i < currentBar + barsToCheck; i++) {
            ema100 = iMA(NULL, 0, 100, 0, MODE_EMA, PRICE_CLOSE, i);
            if (Close[i] > ema100 + distance) {
                countAboveEMA++;
            } else {
                break; // 連続していない場合はループを抜ける
            }
        }

        return countAboveEMA == barsToCheck;
    }

    // EMA100から特定のpips数以上離れて連続しているかを判定する関数
    bool IsContinuouslyDroppingBelowEMA100ByPips(double pipsDistance, int barsToCheck = 100) {
        int currentBar = 0;
        double ema100;
        double distance = pipsDistance * Point;

        int countBelowEMA = 0;
        for(int i = currentBar; i < currentBar + barsToCheck; i++) {
            ema100 = iMA(NULL, 0, 100, 0, MODE_EMA, PRICE_CLOSE, i);
            if (Close[i] < ema100 - distance) {
                countBelowEMA++;
            } else {
                break; // 連続していない場合はループを抜ける
            }
        }

        return countBelowEMA == barsToCheck;
    }

    // 損切り幅が10pips未満なら10pipsを損切り幅とする
    double CalculateStopLossForLong(double entryPrice, double recentLow, double pipsDistance) {
        double minStopDistance = pipsDistance * Point;

        if (entryPrice - recentLow < minStopDistance) {
            return entryPrice - minStopDistance;
        } else {
            return recentLow;
        }
    }

    // 損切り幅が10pips未満なら10pipsを損切り幅とする
    double CalculateStopLossForShort(double entryPrice, double recentHigh, double pipsDistance) {
        double minStopDistance = pipsDistance * Point;

        if (recentHigh - entryPrice < minStopDistance) {
            return entryPrice + minStopDistance;
        } else {
            return recentHigh;
        }
    }

    void GetLowestValue(int term=100) {
        // 最近N本の中での最低値を持つバーの位置を取得
        int lowestBar = iLowest(Symbol(), Period(), MODE_LOW, term, 1);
        // そのバーの最低値・時間を取得
        lowestPrice = iLow(Symbol(), Period(), lowestBar);
        lowestTime = iTime(Symbol(), Period(), lowestBar);
    }

    void GetHighestValue(int term=100) {
        // 最近N本の中での最高値を持つバーの位置を取得
        int highestBar = iHighest(Symbol(), Period(), MODE_HIGH, term, 1);
        // そのバーの最高値・時間を取得
        highestPrice = iHigh(Symbol(), Period(), highestBar);
        highestTime = iTime(Symbol(), Period(), highestBar);
    }

    // 資金に対して適切なロットサイズを計算する
    double GetLotSize(TradeAction action, double stopLossPrice) {
        double entryPrice = MarketInfo(Symbol(), MODE_BID);

        if (action == BUY) {
            entryPrice = MarketInfo(Symbol(), MODE_ASK);
            stopLossPrice = lowestPrice;
        }
        
        double stopLossPips = lotMgr.PriceDifferenceToPips(entryPrice, stopLossPrice);
        double lotSize = lotMgr.CalculateLot(stopLossPips);
        printer.PrintLog("LotSize " + lotSize);
        return lotSize;
    }

    void DisplayInfo()
    {
        // Account info
        double accountBalance = AccountBalance();
        double accountMargin = AccountFreeMarginCheck(Symbol(), OP_BUY, 1.0);
        
        // Trading info
        double spread = MarketInfo(Symbol(), MODE_SPREAD);
        
        // Last trade info
        string lastTradeResult = "No trades yet";
        if (OrdersHistoryTotal() > 0) {
            if (OrderSelect(OrdersHistoryTotal() - 1, SELECT_BY_POS, MODE_HISTORY)) {
                lastTradeResult = OrderType() == OP_BUY ? "BUY" : "SELL";
                lastTradeResult += " " + DoubleToStr(OrderProfit(), 2);
            }
        }
        
        // Position status
        string positionStatus = (OrdersTotal() > 0) ? "Open" : "Closed";

        Comment(
            "Highest Price: ", highestPrice, "\n",
            "Lowest Price: ", lowestPrice, "\n",
            "Trend Reversal (Long): ", trendReversalLineForLong, "\n",
            "Trend Reversal (Short): ", trendReversalLineForShort, "\n",
            "Position Status: ", positionStatus, "\n",
            "Spread: ", spread, "\n",
            "Account Balance: ", accountBalance, "\n",
            "Available Margin for 1 lot: ", accountMargin, "\n",
            "Last Trade Result: ", lastTradeResult
        );
    }

};
