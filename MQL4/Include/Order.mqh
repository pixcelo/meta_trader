//+------------------------------------------------------------------+
//|                                                        Order.mqh |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property strict
//+------------------------------------------------------------------+
//| defines                                                          |
//+------------------------------------------------------------------+
// #define MacrosHello   "Hello, world!"
// #define MacrosYear    2010
//+------------------------------------------------------------------+
//| DLL imports                                                      |
//+------------------------------------------------------------------+
// #import "user32.dll"
//   int      SendMessageA(int hWnd,int Msg,int wParam,int lParam);
// #import "my_expert.dll"
//   int      ExpertRecalculate(int wParam,int lParam);
// #import
//+------------------------------------------------------------------+
//| EX5 imports                                                      |
//+------------------------------------------------------------------+
// #import "stdlib.ex5"
//   string ErrorDescription(int error_code);
// #import
//+------------------------------------------------------------------+
#ifndef ORDER_MQH
#define ORDER_MQH

// --- 定数定義 ---
#define Green clrGreen
#define Red clrRed

// --- ユーティリティ関数 ---

// 買い注文を配置
void PlaceBuyOrder(double stopLossPrice, double lotSize, double RiskRewardRatio, double take_profit = 0.0) {
    double entryPrice = MarketInfo(Symbol(), MODE_ASK);
    double takeProfitPrice;

    if (take_profit > 0) {
        takeProfitPrice = take_profit;
    } else {
        takeProfitPrice = entryPrice + (entryPrice - stopLossPrice) * RiskRewardRatio;
    }

    int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Buy Order", 0, 0, Green);
}

// 売り注文を配置
void PlaceSellOrder(double stopLossPrice, double lotSize, double RiskRewardRatio, double take_profit = 0.0) {
    double entryPrice = MarketInfo(Symbol(), MODE_BID);
    double takeProfitPrice;

    if (take_profit > 0) {
        takeProfitPrice = take_profit;
    } else {
        takeProfitPrice = entryPrice - (stopLossPrice - entryPrice) * RiskRewardRatio;
    }

    int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, 2, stopLossPrice, takeProfitPrice, "Sell Order", 0, 0, Red);
}

// 全ての注文を閉じる
void CloseAllOrders() {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS)) {
            if(OrderSymbol() == Symbol()) {
                if(OrderType() == OP_BUY) {
                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), 2, Green);
                } else if(OrderType() == OP_SELL) {
                    OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), 2, Red);
                }
            }
        }
    }
}

#endif  // ORDER_MQH