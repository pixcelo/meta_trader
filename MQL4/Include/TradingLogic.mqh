// TradingLogic.mqh
input double LargeCandleBodyPips = 5.0;        // 大陽線・大陰線のローソク足の実態のpips
input double RiskRewardRatio = 1.0;            // リスクリワード比
input int Depth = 7;                           // ZigzagのDepth設定
input int Backstep = 3;                        // ZigzagのBackstep設定
input double lotSize = 0.01;
input double SpreadThreshold = 0.05;           // スプレッド閾値

#include "LocalExtremaSeeker.mqh"
#include "ChartDrawer.mqh"

class TradingLogic
{
private:
    LocalExtremaSeeker extremaSeeker;
    ChartDrawer chartDrawer;
    double highestHigh; // 最高値（ショートの損切ライン）
    double lowestLow;   // 最安値（ロングの損切ライン）

    bool isConsecutiveDeclineDetected; // 連続した下落を検知しているか
    bool isConsecutiveRiseDetected;    // 連続した上昇を検知しているか
    bool isBottomReached;              // 下げ止まったか
    bool isCeilingReached;             // 上げ止まったか
    double trendReversalLineForLong;   // 上昇トレンド転換ライン
    double trendReversalLineForShort;  // 下降トレンド転換ライン

public:
    TradingLogic() {
            Initialize();
        }
        
    void Initialize() {
        highestHigh = -1;
        lowestLow = -1;
        isConsecutiveDeclineDetected = false;
        isConsecutiveRiseDetected = false;
        isBottomReached = false;
        isCeilingReached = false;
        trendReversalLineForLong = 0.0;
        trendReversalLineForShort = 0.0;
    }
   
    void TradingStrategy() 
    {        
        if (IsSpreadTooHigh()) {
             Print("Spread too high");
             return;
        }

        if (ShouldGoLong()) {
           PlaceBuyOrder();
        } else if (ShouldGoShort()) {
            PlaceSellOrder();
        }

        // エントリー・エグジットを描画
        // chartDrawer.DrawFromHistory();

        // トレンド転換ラインを描画
        // chartDrawer.DrawTrendReversalLine(trendReversalLineForLong);
        // chartDrawer.DrawTrendReversalLine(trendReversalLineForShort);
    }

private:
    // スプレッド拡大への対応
    bool IsSpreadTooHigh()
    {
        double bid = MarketInfo(Symbol(), MODE_BID);
        double ask = MarketInfo(Symbol(), MODE_ASK);

        return (ask - bid) > SpreadThreshold;
    }

    // ピークの配列から最高のピークの位置を走査し、ひとつ前の谷を下降トレンド転換ラインとして返す
    double GetTrendReversalLineForShort() {
        if (ArraySize(extremaSeeker.peakValues) == 0 ||
            ArraySize(extremaSeeker.valleyValues) == 0) {
            return -1;
        }

        // 最高のピークを見つける
        double highestPeak = extremaSeeker.peakValues[0];
        int highestPeakIndex = 0;
        for (int i = 1; i < ArraySize(extremaSeeker.peakValues); i++) {
            if (extremaSeeker.peakValues[i] > highestPeak) {
                highestPeak = extremaSeeker.peakValues[i];
                highestPeakIndex = i;
            }
        }

        // 損切ラインとして最高のピークを保存
        highestHigh = highestPeak;

        // 最高のピークの一つ前の谷を見つける
        double previousValley = -1;
        for (int j = 0; j <= highestPeakIndex && j < ArraySize(extremaSeeker.valleyValues); j++) {
            previousValley = extremaSeeker.valleyValues[j];
        }

        return previousValley;
    }

    // 谷の配列から最低の谷の位置を走査し、ひとつ前のピークを上昇トレンド転換ラインとして返す
    double GetTrendReversalLineForLong() {
        if (ArraySize(extremaSeeker.peakValues) == 0 ||
            ArraySize(extremaSeeker.valleyValues) == 0) {
            return -1;
        }

        // 最低の谷を見つける
        double lowestValley = extremaSeeker.valleyValues[0];
        int lowestValleyIndex = 0;
        for (int i = 1; i < ArraySize(extremaSeeker.valleyValues); i++) {
            if (extremaSeeker.valleyValues[i] < lowestValley) {
                lowestValley = extremaSeeker.valleyValues[i];
                lowestValleyIndex = i;
            }
        }

        // 損切ラインとして最低の谷を保存
        lowestLow = lowestValley;

        // 最低の谷の一つ前のピークを見つける
        double previousPeak = -1;
        for (int j = 0; j <= lowestValleyIndex && j < ArraySize(extremaSeeker.peakValues); j++) {
            previousPeak = extremaSeeker.peakValues[j];
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
            double openPrice = iOpen(Symbol(), PERIOD_M1, i + startShift);
            double closePrice = iClose(Symbol(), PERIOD_M1, i + startShift);
            double bodyLength = MathAbs(closePrice - openPrice);
            
            if(bodyLength > maxBodyLength)
                maxBodyLength = bodyLength;
        }
        return maxBodyLength;
    }

    // ロングエントリー判断
    bool ShouldGoLong() {
        // 連続した下落を検知していない場合、それをチェックする
        if (!isConsecutiveDeclineDetected) {
            extremaSeeker.UpdatePeaksAndValleys(960);
            isConsecutiveDeclineDetected = IsConsecutiveFall(5);
        }

        // 連続した下落を検知した場合、下げ止まりを確認する
        if (!isBottomReached) {
            extremaSeeker.UpdatePeaksAndValleys(60); // こちらでは直近の動きを見る
            isBottomReached = IsConsecutiveRise(2);
        }

        // 下げ止まりを確認したら、トレンド転換ラインを取得する
        if (trendReversalLineForLong == 0) {
            trendReversalLineForLong = GetTrendReversalLineForLong();
        }

        // 損切ラインに設定した最安値を抜けてきたら、トレンド転換ラインを引き直す
        double currentClosePrice = iClose(Symbol(), Period(), 0);
        if (trendReversalLineForLong > 0 && currentClosePrice < lowestLow) {
            extremaSeeker.UpdatePeaksAndValleys(60);
            trendReversalLineForLong = GetTrendReversalLineForLong();
        }

        // トレンド転換ラインが設定されている場合、大陽線で上抜けしたかを判定する
        if (trendReversalLineForLong > 0) {
            // ローソク足の大きさとEMA100を確認する
            if (iClose(Symbol(), Period(), 0) > trendReversalLineForLong) {
                if (Close[1] > iMA(Symbol(), 0, 100, 0, MODE_EMA, PRICE_CLOSE, 1)
                    && IsExceptionallyLargeCandle(1)) {
                    return true;
                }
            }
        }

        return false;
    }

    // ショートエントリー判断
    bool ShouldGoShort() {
        // 連続した上昇を検知していない場合、それをチェックする
        if (!isConsecutiveRiseDetected) {
            extremaSeeker.UpdatePeaksAndValleys(960);
            isConsecutiveRiseDetected = IsConsecutiveRise(5);
        }

        // 連続した上昇を検知した場合、上げ止まりを確認する
        if (!isCeilingReached) {
            extremaSeeker.UpdatePeaksAndValleys(60); // こちらでは直近の動きを見る
            isCeilingReached = IsConsecutiveFall(2);
        }

        // 上げ止まりを確認したら、トレンド転換ラインを取得する
        if (trendReversalLineForShort == 0) {
            trendReversalLineForShort = GetTrendReversalLineForShort();
        }

        // 損切ラインに設定した最高値を抜けてきたら、トレンド転換ラインを引き直す
        double currentClosePrice = iClose(Symbol(), Period(), 0);
        if (trendReversalLineForShort > 0 && currentClosePrice > highestHigh) {
            extremaSeeker.UpdatePeaksAndValleys(60);
            trendReversalLineForShort = GetTrendReversalLineForShort();
        }

        // トレンド転換ラインが設定されている場合、大陰線で下抜けしたかを判定する
        if (trendReversalLineForShort > 0) {
            // ローソク足の大きさとEMA100を確認する
            if (iClose(Symbol(), Period(), 0) < trendReversalLineForShort) {
                if (Close[1] < iMA(Symbol(), 0, 100, 0, MODE_EMA, PRICE_CLOSE, 1)
                    && IsExceptionallyLargeCandle(1)) {
                    return true;
                }
            }
        }

        return false;
    }

    // ピークと谷が連続してN回上昇した回数の最大値を判定する（ショートエントリー用）
    bool IsConsecutiveRise(int N) {
        if (ArraySize(extremaSeeker.peakValues) < N || ArraySize(extremaSeeker.valleyValues) < N) {
            return false;
        }

        int highCount = 0;
        int maxHighCount = 0;
        double lastValue = -DBL_MAX; // 初期値を非常に小さな値に設定

        for (int i = 0; i < ArraySize(extremaSeeker.peakValues); i++) {
            if (extremaSeeker.peakValues[i] > lastValue) {
                lastValue = extremaSeeker.peakValues[i];
                highCount++;
                if (highCount > maxHighCount) {
                    maxHighCount = highCount;
                }
            } else {
                highCount = 0;
            }
        }
        //Print("high 最大の連続した上昇回数は: ", maxHighCount);

        int lowCount = 0;
        int maxLowCount = 0;
        double lastLowValue = -DBL_MAX; // 初期値を非常に小さな値に設定

        for (int j = 0; j < ArraySize(extremaSeeker.valleyValues); j++) {
            if (extremaSeeker.valleyValues[j] > lastLowValue) {
                lastLowValue = extremaSeeker.valleyValues[j];
                lowCount++;
                if (lowCount > maxLowCount) {
                    maxLowCount = lowCount;
                }
            } else {
                lowCount = 0;
            }
        }
        //Print("low 最大の連続した上昇回数は: ", maxLowCount);
        return maxHighCount >= N && maxLowCount >= N;
    }

    // ピークと谷が連続してN回下降した回数の最大値を判定する（ロングエントリー用）
    bool IsConsecutiveFall(int N) {
        if (ArraySize(extremaSeeker.peakValues) < N || ArraySize(extremaSeeker.valleyValues) < N) {
            return false;
        }

        int highCount = 0;
        int maxHighCount = 0;
        double lastValue = DBL_MAX; // 初期値を非常に大きな値に設定

        for (int i = 0; i < ArraySize(extremaSeeker.peakValues); i++) {
            if (extremaSeeker.peakValues[i] < lastValue) {
                lastValue = extremaSeeker.peakValues[i];
                highCount++;
                if (highCount > maxHighCount) {
                    maxHighCount = highCount;
                }
            } else {
                highCount = 0;
            }
        }
        //Print("high 最大の連続した下降回数は: ", maxHighCount);

        int lowCount = 0;
        int maxLowCount = 0;
        double lastLowValue = DBL_MAX; // 初期値を非常に大きな値に設定

        for (int j = 0; j < ArraySize(extremaSeeker.valleyValues); j++) {
            if (extremaSeeker.valleyValues[j] < lastLowValue) {
                lastLowValue = extremaSeeker.valleyValues[j];
                lowCount++;
                if (lowCount > maxLowCount) {
                    maxLowCount = lowCount;
                }
            } else {
                lowCount = 0;
            }
        }
        //Print("low 最大の連続した下降回数は: ", maxLowCount);
        return maxHighCount >= N && maxLowCount >= N;
    }

    void PlaceBuyOrder()
    {
        double entryPrice = MarketInfo(Symbol(), MODE_ASK);
        double stopLossPrice = lowestLow;
        double takeProfitPrice = entryPrice + (entryPrice - stopLossPrice) * RiskRewardRatio;

        int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Buy Order", 0, 0, Green);
        Initialize();
    }

    void PlaceSellOrder()
    {
        double entryPrice = MarketInfo(Symbol(), MODE_BID);
        double stopLossPrice = highestHigh;
        double takeProfitPrice = entryPrice - (stopLossPrice - entryPrice) * RiskRewardRatio;

        int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Sell Order", 0, 0, Red);
        Initialize();
    }

    // 週末にポジションを閉じる関数
    void CloseAllPositionsBeforeWeekend(int hourToClose = 22) {
        // 現在の曜日と時刻を取得
        datetime currentTime = TimeCurrent();
        int dayOfWeek = TimeDayOfWeek(currentTime);
        int currentHour = TimeHour(currentTime);

        // 金曜日で指定された時刻以降である場合
        if (dayOfWeek == 5 && currentHour >= hourToClose) {
            for (int i = OrdersTotal() - 1; i >= 0; i--) {
                if (OrderSelect(i, SELECT_BY_POS)) {
                    OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE);
                }
            }
        }
    }

};
