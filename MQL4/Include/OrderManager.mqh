// OrderManager.mqh

#include "Utility.mqh"

class OrderManager
{
private:
    Utility utility;

public:
    int PlaceBuyOrder(double lotSize, double stopLoss, double riskRewardRatio, int magicNumber, color orderColor = Green) {
        double entryPrice = MarketInfo(Symbol(), MODE_ASK);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        double takeProfitPrice = NormalizeDouble((entryPrice + (entryPrice - stopLossPrice) * riskRewardRatio), Digits());

        int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Buy Order", magicNumber, 0, orderColor);

        if (ticket < 0) {
            int lastError = GetLastError();
            Print("Error in Buy Order: ", lastError);
        } else {
            // Order was successful
            // Print("Buy Order successfully placed with ticket: ", ticket);
        }

        return ticket;
    }

    int PlaceSellOrder(double lotSize, double stopLoss, double riskRewardRatio, int magicNumber, color orderColor = Red) {
        double entryPrice = MarketInfo(Symbol(), MODE_BID);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        double takeProfitPrice = NormalizeDouble((entryPrice - (stopLossPrice - entryPrice) * riskRewardRatio), Digits());

        int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Sell Order", magicNumber, 0, orderColor);

        if (ticket < 0) {
            int lastError = GetLastError();
            Print("Error in Sell Order: ", lastError);
        } else {
            // Order was successful
            // Print("Sell Order successfully placed with ticket: ", ticket);
        }

        return ticket;
    }

    // 全ての注文を閉じる
    void CloseAllOrders() {
        bool result;
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS)) {
                if (OrderSymbol() == Symbol()) {
                    if (OrderType() == OP_BUY) {
                        result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), 2, Green);
                    } else if (OrderType() == OP_SELL) {
                        result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), 2, Red);
                    }
                }
            }
        }
    }

    // 週末にポジションを閉じる（ギャップアップ対策）
    void CloseAllPositionsBeforeWeekend(int hourToClose = 22) {
        // 現在の曜日と時刻を取得
        datetime currentTime = TimeCurrent();
        int dayOfWeek = TimeDayOfWeek(currentTime);
        int currentHour = TimeHour(currentTime);

        // 金曜日で指定された時刻以降である場合
        if (dayOfWeek == 5 && currentHour >= hourToClose) {
            for (int i = OrdersTotal() - 1; i >= 0; i--) {
                if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol()) {
                    bool result = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE);
                }
            }
        }
    }

    // 停滞しているポジションを閉じる
    void CheckAndCloseStagnantPositions(int timeLimitMinutes, double minProfitPips, double maxProfitPips)
    {
        for (int i = 0; i < OrdersTotal(); i++)
        {
            if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if (OrderType() == OP_BUY || OrderType() == OP_SELL) //アクティブなポジションを選択
                {
                    datetime orderOpenTime = OrderOpenTime();
                    datetime currentTime = TimeCurrent();
                    int timeDiffMinutes = (int)(TimeDiff(currentTime, orderOpenTime) / 60); //経過時間を分で計算

                    if (timeDiffMinutes >= timeLimitMinutes) //経過時間が指定された限度以上
                    {
                        double floatingProfit = OrderProfit() / MarketInfo(OrderSymbol(), MODE_POINT); //浮動損益をpipsで取得
                        if (floatingProfit >= minProfitPips && floatingProfit <= maxProfitPips)
                        {
                            bool result = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, White); //ポジションを決済
                        }
                    }
                }
            }
        }
    }

    int TimeDiff(datetime startTime, datetime endTime)
    {
        return (int)(startTime - endTime);
    }

    // ストップロスだけ設定する注文(トレイリングストップ用)
    int PlaceBuyOrderForTrailingStop(double lotSize, double stopLoss, int magicNumber, color orderColor = Blue) {
        double entryPrice = MarketInfo(Symbol(), MODE_ASK);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, 2, stopLossPrice, 0, "Buy Order", magicNumber, 0, orderColor);

        if (ticket < 0) {
            int lastError = GetLastError();
            Print("Error in Buy Order: ", lastError);
        }

        return ticket;
    }

    int PlaceSellOrderForTrailingStop(double lotSize, double stopLoss, int magicNumber, color orderColor = Orange) {
        double entryPrice = MarketInfo(Symbol(), MODE_BID);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, 2, stopLossPrice, 0, "Sell Order", magicNumber, 0, orderColor);

        if (ticket < 0) {
            int lastError = GetLastError();
            Print("Error in Sell Order: ", lastError);
        }

        return ticket;
    }

    // トレイリングストップ
    // trailStart: トレイリングストップを開始するためのプロフィット(pips)
    // trailStop: 新しいストップロスと現在の価格との差(pips)
    void ApplyTrailingStop(double trailStart, double trailStop)
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS)) {
                double currentPrice = 0.0;
                double pointValue = Point * utility.GetPointCoefficient();

                if (OrderType() == OP_BUY) {
                    currentPrice = MarketInfo(OrderSymbol(), MODE_BID);
                    if ((currentPrice - OrderOpenPrice()) > (trailStart * pointValue)) {
                        if ((currentPrice - OrderStopLoss()) > (trailStop * pointValue) || OrderStopLoss() == 0) {
                            double stopLossBuy = currentPrice - (trailStop * pointValue);
                            bool resultBuy = OrderModify(OrderTicket(), OrderOpenPrice(), stopLossBuy, OrderTakeProfit(), 0, Green);
                        }
                    }
                }
                
                if (OrderType() == OP_SELL) {
                    currentPrice = MarketInfo(OrderSymbol(), MODE_ASK);
                    if ((OrderOpenPrice() - currentPrice) > (trailStart * pointValue)) {
                        if ((OrderStopLoss() - currentPrice) > (trailStop * pointValue) || OrderStopLoss() == 0) {
                            double stopLossSell = currentPrice + (trailStop * pointValue);
                            bool resultSell = OrderModify(OrderTicket(), OrderOpenPrice(), stopLossSell, OrderTakeProfit(), 0, Red);
                        }
                    }
                }
            }
        }
    }
    
};
