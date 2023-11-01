// TradingLogic.mqh
input double LargeCandleBodyPips = 5.0;        // 大陽線・大陰線のローソク足の実体のpips
input double RiskRewardRatio = 1.0;            // リスクリワード比
input int MinStopLossPips = 10;                // ストップロスの下限(pips)

// Zigzag
input int Depth = 7;                           // ZigzagのDepth設定
input int Deviation = 5;                       // ZigzagのDeviation設定
input int Backstep = 3;                        // ZigzagのBackstep設定
input int zigzagTerm = 240;                    // 極値を計算する期間

// Threshold
input int SpreadThresholdPips = 5;             // スプレッド閾値(pips)
input int MaxHoldingMinutes = 60;              // ポジション保有時間の最大(分)

// EA Settings
input int Magic = 19850001;                    // マジックナンバー（EAの識別番号）
input bool EnableLogging = true;               // ログ出力

#include "ZigzagSeeker.mqh"
#include "RangeBox.mqh"
#include "ChartDrawer.mqh"
#include "OrderManager.mqh"
#include "PrintManager.mqh"
#include "Utility.mqh"

class TradingLogic
{
private:
    // Instances of Classes
    ZigzagSeeker zzSeeker;
    RangeBox rangeBox;
    ChartDrawer chartDrawer;
    OrderManager orderMgr;
    PrintManager printer;
    Utility ut;

    datetime lastTradeTime;
    datetime lastObjTime;
    int lastTimeChecked;

    // 関数呼び出しは計算コストが掛かるため変数に格納する
    string symbol;
    int timeframe;

public:
    TradingLogic() {
        zzSeeker.Initialize(Depth, Deviation, Backstep, PERIOD_M15);
        rangeBox.Init(15, 10, 100);
        printer.EnableLogging(EnableLogging);
        lastObjTime = TimeCurrent();
        symbol = Symbol();
        timeframe = PERIOD_CURRENT;
    }

    void Execute() {
        printer.PrintLog("Trade executed.");
        printer.ShowCounts();
    }
   
    void TradingStrategy() {
        if (ut.IsSpreadTooHigh(symbol, SpreadThresholdPips)) {
             printer.PrintLog("Spread too high");
             return;
        }

        // Set up
        // zzSeeker.UpdateExtremaArray(zigzagTerm, 50);
        // zzSeeker.UpdateExShortArray(zigzagTerm, 200, PERIOD_M1);

        // Draw objects
        // chartDrawer.DrawPeaksAndValleys(ExtremaArray, 50);
        //chartDrawer.DrawTrendLineFromPeaksAndValleys(ExtremaArray);

        // 15分ごとに描画
        // datetime currentTime = TimeCurrent();
        // datetime last15MinTime = iTime(NULL, PERIOD_M15, 0);
        // if (last15MinTime > lastTimeChecked) {
        //     lastTimeChecked = last15MinTime;
        //     chartDrawer.DrawTrendLineFromPeaksAndValleys(ExtremaArray);
        // }

        // Startegy
        Run();
    }

private:
    void Run() {
        if (OrdersTotal() > 0) {
            // 途中決済
            orderMgr.CheckAndCloseStagnantPositions(MaxHoldingMinutes, Magic);
        }

        // if (!ut.IsVolatilityAcceptable(symbol, 14, 0.04)) {
        //     return;
        // }

        // if (ut.IsWithinTradeInterval(lastTradeTime)) {
        //     return;
        // }

        int action = rangeBox.OnTick();
        double stopLossPrice = rangeBox.GetStopLossPrice();
        double takeProfitPrice = 0;
        int ticket = 0;

        if (OrdersTotal() > 0) {
            return;
        }

        // Buy
        if (action == 1) {
            // orderMgr.ClosePositionOnSignal(OP_SELL, Magic);
            // stopLossPrice = AdjustStopLoss(1, MarketInfo(symbol, MODE_ASK), stopLossPrice, MinStopLossPips);
            ticket = orderMgr.PlaceBuyOrder(action, stopLossPrice, takeProfitPrice, RiskRewardRatio, Magic);
            if (ticket > 0) {
                lastTradeTime = TimeCurrent();
            }
        }

        // Sell
        if (action == 2) {
            // orderMgr.ClosePositionOnSignal(OP_BUY, Magic);
            // stopLossPrice = AdjustStopLoss(2, MarketInfo(symbol, MODE_BID), stopLossPrice, MinStopLossPips);
            ticket = orderMgr.PlaceSellOrder(action, stopLossPrice, takeProfitPrice, RiskRewardRatio, Magic);
            if (ticket > 0) {
                lastTradeTime = TimeCurrent();
            }
        }
    }

    bool IsPerfectOrder(int action)
    {
        double maShort = 0;
        double maMiddle = 0;
        double maLong = 0;

        if (action == 1) {
            maShort = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE, 0);
            maMiddle = iMA(symbol, timeframe, 100, 0, MODE_SMA, PRICE_CLOSE, 0);
            maLong = iMA(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE, 0);
            return maShort > maMiddle && maMiddle > maLong;
        }

        if (action == 2) {
            maShort = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE, 0);
            maMiddle = iMA(symbol, timeframe, 100, 0, MODE_SMA, PRICE_CLOSE, 0);
            maLong = iMA(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE, 0);
            return maShort < maMiddle && maMiddle < maLong;
        }

        return false;
    }

    // ローソク足の大きさを確認
    bool IsExceptionallyLargeCandle(int action)
    {
        double openPrice = iOpen(symbol, timeframe, 0);
        double closePrice = iClose(symbol, timeframe, 0);
        double highPrice = iHigh(symbol, timeframe, 0);
        double lowPrice = iLow(symbol, timeframe, 0);

        if (action == 1 && closePrice < openPrice) {
            return false; // 陰線の場合
        }
        if (action == 2 && closePrice > openPrice) {
            return false; // 陽線の場合
        }

        double bodyLength = MathAbs(closePrice - openPrice); // 実体の絶対値を取得
        double compareBody = MaximumBodyLength(20, 1);
        double wickLength;

        if (closePrice > openPrice) // 陽線の場合
            wickLength = highPrice - closePrice; // 上ヒゲの長さ
        else
            wickLength = openPrice - lowPrice; // 下ヒゲの長さ

        // 直近20本で比較的大きい（またはNpips以上）でヒゲが小さいローソク足
        return (bodyLength > compareBody
            && bodyLength >= LargeCandleBodyPips * Point * ut.GetPointCoefficient())
            && wickLength < bodyLength * 0.1;
    }

    double MaximumBodyLength(int barsToConsider, int startShift)
    {
        double maxBodyLength = 0;
        for (int i = 0; i < barsToConsider; i++)
        {
            double openPrice = iOpen(symbol, timeframe, i + startShift);
            double closePrice = iClose(symbol, timeframe, i + startShift);
            double bodyLength = MathAbs(closePrice - openPrice);
            
            if (bodyLength > maxBodyLength)
                maxBodyLength = bodyLength;
        }
        return maxBodyLength;
    }

    // 直近N分間の最高価格を返す
    double GetHighestPrice(int n) {
        int highBar = iHighest(symbol, timeframe, MODE_HIGH, n, 1);
        return iHigh(symbol, timeframe, highBar);
    }

    // 直近N分間の最低価格を返す
    double GetLowestPrice(int n) {
        int lowBar = iLowest(symbol, timeframe, MODE_LOW, n, 1);
        return iLow(symbol, timeframe, lowBar);
    }

    // ストップロスの下限を指定したpipsに設定
    double AdjustStopLoss(int action, double currentPrice, double stopLossValue, int minPips) {
        double minStopLoss = 0;

        if (action == 1) {
            minStopLoss = currentPrice - ut.PipsToPrice(minPips);
            if (stopLossValue > minStopLoss) {
                return minStopLoss;
            }
        } else if (action == 2) {
            minStopLoss = currentPrice + ut.PipsToPrice(minPips);
            if (stopLossValue < minStopLoss) {
                return minStopLoss;
            }
        }
        
        return stopLossValue;
    }

};