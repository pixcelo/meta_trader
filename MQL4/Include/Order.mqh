// Order.mqh
class OrderManager
{
public:
    int PlaceBuyOrder(double lotSize, double stopLoss, double riskRewardRatio, color orderColor = Green) {
        double entryPrice = MarketInfo(Symbol(), MODE_ASK);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        double takeProfitPrice = NormalizeDouble((entryPrice + (entryPrice - stopLossPrice) * riskRewardRatio), Digits());

        int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Buy Order", 0, 0, orderColor);

        if (ticket < 0) {
            int lastError = GetLastError();
            Print("Error in Buy Order: ", lastError);
        } else {
            // Order was successful
            // Print("Buy Order successfully placed with ticket: ", ticket);
        }

        return ticket;
    }

    int PlaceSellOrder(double lotSize, double stopLoss, double riskRewardRatio, color orderColor = Red) {
        double entryPrice = MarketInfo(Symbol(), MODE_BID);
        double stopLossPrice = NormalizeDouble(stopLoss, Digits());
        double takeProfitPrice = NormalizeDouble((entryPrice - (stopLossPrice - entryPrice) * riskRewardRatio), Digits());

        int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Sell Order", 0, 0, orderColor);

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
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS)) {
                if (OrderSymbol() == Symbol()) {
                    if (OrderType() == OP_BUY) {
                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), 2, Green);
                    } else if (OrderType() == OP_SELL) {
                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), 2, Red);
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
                    OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrNONE);
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
                            OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, White); //ポジションを決済
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
};
