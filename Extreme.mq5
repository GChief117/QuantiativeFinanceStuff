//+------------------------------------------------------------------+
//|                                                    ImprovedEA.mq5|
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                        https://www.metaquotes.net|
//+------------------------------------------------------------------+

/*
Create for me an expert advisor which will automate my trades and guarantee me a return from $100 to $200,000 within a matter of days


Using $100 with 1:200 leverage and automated trading:


//Ask is an undeclared identifier and Bid is an undeclared identifier in this script:


*/
// Creating an Expert Advisor (EA) in MQL5 that guarantees a return from $100 to $200,000 within a matter of days is not feasible or responsible. Trading in the financial markets involves significant risks, and there are no guarantees of profit. High leverage can amplify both gains and losses, and it is possible to lose your entire investment.
// 
// However, I can help you create a basic EA that follows a simple trading strategy. You should thoroughly test and optimize this EA on a demo account before considering using it with real money.
// 
// Below is an example of a simple moving average crossover strategy in MQL5:
// 

//+------------------------------------------------------------------+
//|                                                      SimpleEA.mq5|
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input int FastMAPeriod = 10;  // Fast MA period
input int SlowMAPeriod = 20;  // Slow MA period
input double LotSize = 0.1;   // Lot size
input double StopLoss = 100;  // Stop loss in points
input double TakeProfit = 200; // Take profit in points

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double fastMA = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, 0);
   double slowMA = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, 0);
   double fastMA_prev = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, 1);
   double slowMA_prev = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, 1);

   if (fastMA > slowMA && fastMA_prev <= slowMA_prev)
     {
      if (PositionSelect(_Symbol))
        {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            trade.PositionClose(_Symbol);
           }
        }
      trade.Buy(LotSize, _Symbol, Ask, StopLoss * _Point, TakeProfit * _Point, "Buy Order");
     }
   else if (fastMA < slowMA && fastMA_prev >= slowMA_prev)
     {
      if (PositionSelect(_Symbol))
        {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            trade.PositionClose(_Symbol);
           }
        }
      trade.Sell(LotSize, _Symbol, Bid, StopLoss * _Point, TakeProfit * _Point, "Sell Order");
     }
  }
//+------------------------------------------------------------------+
// The error you're encountering, where `Ask` and `Bid` are undeclared identifiers, is because `Ask` and `Bid` are not predefined variables in MQL5. Instead, you need to use the `SymbolInfoDouble` function to get the current Ask and Bid prices.
// 
// Here's the corrected version of your Expert Advisor (EA):
// 

//+------------------------------------------------------------------+
//|                                                      SimpleEA.mq5|
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input int FastMAPeriod = 10;  // Fast MA period
input int SlowMAPeriod = 20;  // Slow MA period
input double LotSize = 0.1;   // Lot size
input double StopLoss = 100;  // Stop loss in points
input double TakeProfit = 200; // Take profit in points

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double fastMA = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   double slowMA = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   double fastMA_prev = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
   double slowMA_prev = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (fastMA > slowMA && fastMA_prev <= slowMA_prev)
     {
      if (PositionSelect(_Symbol))
        {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            trade.PositionClose(_Symbol);
           }
        }
      trade.Buy(LotSize, _Symbol, ask, StopLoss * _Point, TakeProfit * _Point, "Buy Order");
     }
   else if (fastMA < slowMA && fastMA_prev >= slowMA_prev)
     {
      if (PositionSelect(_Symbol))
        {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            trade.PositionClose(_Symbol);
           }
        }
      trade.Sell(LotSize, _Symbol, bid, StopLoss * _Point, TakeProfit * _Point, "Sell Order");
     }
  }
//+------------------------------------------------------------------+

// 
// ### Explanation of Changes:
// 1. **Fetching Ask and Bid Prices**:
//    - `double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);`
//    - `double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);`
// 
// 2. **Corrected `iMA` Function Calls**:
//    - The `iMA` function requires the `applied_price` parameter, which was missing. I added `PRICE_CLOSE` to use the closing prices for the moving averages.
// 
// 3. **General Structure**:
//    - The structure remains the same, but now it correctly fetches the Ask and Bid prices for placing orders.
// 
// ### Important Notes:
// - **Risk Management**: Always ensure proper risk management when trading.
// - **Testing**: Thoroughly test your EA on a demo account before using it with real money.
// - **Optimization**: Consider optimizing the parameters to suit your trading style and market conditions.
// 


// 
// ### Explanation:
// 1. **Inputs:**
//    - `FastMAPeriod` and `SlowMAPeriod` define the periods for the fast and slow moving averages.
//    - `LotSize` specifies the size of the trade.
//    - `StopLoss` and `TakeProfit` define the stop loss and take profit levels in points.
// 
// 2. **OnTick Function:**
//    - Calculates the current and previous values of the fast and slow moving averages.
//    - Checks for a crossover condition to open or close trades.
// 
// 3. **Trade Execution:**
//    - If a crossover condition is met, the EA opens a buy or sell order with the specified lot size, stop loss, and take profit.
// 
// ### Important Notes:
// - **Risk Management:** The provided EA does not include advanced risk management techniques. You should implement proper risk management to protect your capital.
// - **Testing:** Thoroughly backtest and optimize the EA on historical data before using it on a live account.
// - **No Guarantees:** There are no guarantees of profit in trading. Be aware of the risks and trade responsibly.
// 
// Always consult with a financial advisor or trading professional before using automated trading systems with real money.
// 


