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
    // Instances of Classes
    ZigzagSeeker zzSeeker;
    ChartDrawer chartDrawer;
    OrderManager orderMgr;
    LotManager lotMgr;
    PrintManager printer;
    Utility ut;

    datetime lastTradeTime;
    datetime lastObjTime;
    int lastTimeChecked;

    enum TradeAction {
        WAIT = 0,
        BUY  = 1,
        SELL = 2
    };

    // 関数呼び出しは計算コストが掛かるため変数に格納する
    string symbol;
    int timeframe;

public:
    TradingLogic() {
        zzSeeker.Initialize(Depth, Deviation, Backstep, PERIOD_M15);
        lotMgr.SetRiskPercentage(2.0);
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

        if (OrdersTotal() > 0) {
            // 途中決済
            orderMgr.CheckAndCloseStagnantPositions(MaxHoldingMinutes, Magic);
        }

        // Set up
        zzSeeker.UpdateExtremaArray(zigzagTerm, 200);
        // zzSeeker.UpdateExShortArray(zigzagTerm, 200, PERIOD_M1);

        // Startegy
        Run();

        // Draw objects
        if (Visualmode) {
            // chartDrawer.DrawPeaksAndValleys(ExtremaArray, 50);
            // chartDrawer.DrawTrendLineFromPeaksAndValleys(ExtremaArray);

            // 15分ごとに描画
            // datetime currentTime = TimeCurrent();
            // datetime last15MinTime = iTime(NULL, PERIOD_M15, 0);
            // if (last15MinTime > lastTimeChecked) {
            //     lastTimeChecked = last15MinTime;
            //     chartDrawer.DrawTrendLineFromPeaksAndValleys(ExtremaArray);
            // }
        }
    }

private:
    void Run() {
        // if (!ut.IsVolatilityAcceptable(symbol, 14, 0.04)) {
        //     return;
        // }

        // 1時間MAでフィルタリング
        double maH1 = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 0);
        double maH1Prev = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 4);
        double maH1Diff = maH1 - maH1Prev;

        // 200EMA
        double ema200 = iMA(symbol, 0, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
        double ema200Prev = iMA(symbol, 0, 200, 0, MODE_EMA, PRICE_CLOSE, 10);

        // 100EMA
        double ema100 = iMA(symbol, 0, 100, 0, MODE_EMA, PRICE_CLOSE, 0);
        double ema100Prev = iMA(symbol, 0, 100, 0, MODE_EMA, PRICE_CLOSE, 10);

        // 50EMA
        double ema50 = iMA(symbol, 0, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
        double ema50Prev = iMA(symbol, 0, 50, 0, MODE_EMA, PRICE_CLOSE, 10);

        // オブジェクトの色を取得
        color latestColor = clrNONE;
        double latestValue = 0;
        double objValue = 0;
        datetime objTime = 0;

        for (int i = ObjectsTotal() - 1; i >= 0; i--) {
            string objName = ObjectName(0, i);
            color objColor = ObjectGetInteger(0, objName, OBJPROP_COLOR);
            datetime tmpTime = ObjectGetInteger(0, objName, OBJPROP_TIME1);
            int objType = ObjectGetInteger(0, objName, OBJPROP_TYPE);
            double tmpValue = ObjectGetDouble(0, objName, OBJPROP_PRICE);

            if (tmpTime > objTime && (objColor == clrTomato || objColor == clrLightSkyBlue)) {
                //Print("objName: ", objName, "Color: ", objColor, " objType: ", objType, " Time: ", tmpTime, " Value: ", objValue);
                objTime = tmpTime;
                objValue = tmpValue;
                latestColor = objColor;
            }
        }

        if (objTime > lastObjTime) {
            lastObjTime = objTime;
            latestValue = objValue;
            //Print("last time: ", lastObjTime);
        } else {
            latestColor = clrNONE;
        }
        
        // int lastTradeIntervalSeconds = 300;
        // if (TimeCurrent() - lastTradeTime < lastTradeIntervalSeconds) {
        //     return;
        // }

        // トレンドラインの色で環境認識（オブジェクトが存在しない場合、clrNONE=0を返す）
        // clrGreen: up, clrRed: down, clrNONE: range
        // color plineClr = chartDrawer.GetObjColor("PeakTrendLine");
        // color vlineClr = chartDrawer.GetObjColor("ValleyTrendLine");

        double trendLinePrice = 0;
        double stopLossPrice = 0;
        double takeProfitPrice = 0;
        double lotSize = 0;
        int ticket = 0;

        if (latestColor == clrLightSkyBlue && latestValue != 0) {
            orderMgr.ClosePositionOnSignal(OP_SELL, Magic);
            if (ut.IsWithinTradeInterval(lastTradeTime)) {
                return;
            }
            stopLossPrice = AdjustStopLoss(BUY, MarketInfo(symbol, MODE_ASK), latestValue, MinStopLossPips);
            lotSize = GetLotSize(BUY, stopLossPrice);
            ticket = orderMgr.PlaceBuyOrder(lotSize, stopLossPrice, takeProfitPrice, RiskRewardRatio, Magic);
            if (ticket > 0) {
                lastTradeTime = TimeCurrent();
            }
        }

        if (latestColor == clrTomato && latestValue != 0) {
            orderMgr.ClosePositionOnSignal(OP_BUY, Magic);
            if (ut.IsWithinTradeInterval(lastTradeTime)) {
                return;
            }
            stopLossPrice = AdjustStopLoss(SELL, MarketInfo(symbol, MODE_BID), latestValue, MinStopLossPips);
            lotSize = GetLotSize(SELL, stopLossPrice);
            ticket = orderMgr.PlaceSellOrder(lotSize, stopLossPrice, takeProfitPrice, RiskRewardRatio, Magic);
            if (ticket > 0) {
                lastTradeTime = TimeCurrent();
            }
        }
    }

    // ローソク足の大きさを確認
    bool IsExceptionallyLargeCandle(TradeAction action)
    {
        double openPrice = iOpen(symbol, timeframe, 0);
        double closePrice = iClose(symbol, timeframe, 0);
        double highPrice = iHigh(symbol, timeframe, 0);
        double lowPrice = iLow(symbol, timeframe, 0);

        if (action == SELL && closePrice > openPrice) {
            return false; // 陽線の場合
        }
        if (action == BUY && closePrice < openPrice) {
            return false; // 陰線の場合
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

    // 資金に対して適切なロットサイズを計算する
    double GetLotSize(TradeAction action, double stopLossPrice) {
        double entryPrice = MarketInfo(symbol, MODE_BID);

        if (action == BUY) {
            entryPrice = MarketInfo(symbol, MODE_ASK);
        }

        double stopLossPips = ut.PriceToPips(MathAbs(entryPrice - stopLossPrice));
        double lotSize = lotMgr.CalculateLot(stopLossPips);
        return lotSize;
    }

    // ストップロスの下限を指定したpipsに設定
    double AdjustStopLoss(TradeAction action, double currentPrice, double stopLossValue, int minPips) {
        double minStopLoss = 0;

        if (action == BUY) {
            minStopLoss = currentPrice - ut.PipsToPrice(minPips);
            if (stopLossValue > minStopLoss) {
                return minStopLoss;
            }
        } else if (action == SELL) {
            minStopLoss = currentPrice + ut.PipsToPrice(minPips);
            if (stopLossValue < minStopLoss) {
                return minStopLoss;
            }
        }
        
        return stopLossValue;
    }

};