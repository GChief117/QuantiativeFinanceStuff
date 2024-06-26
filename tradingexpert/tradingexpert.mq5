//+------------------------------------------------------------------+
//|                                                      SampleEA.mq5|
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input double lotSize = 0.1; // Lot size for trading
input double takeProfit = 50; // Take Profit in points
input double stopLoss = 50; // Stop Loss in points

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Print the initial balance and leverage
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   Print("Initial Balance: ", balance);
   Print("Leverage: ", leverage);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Print the final balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("Final Balance: ", balance);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Example: Open a trade if no orders are currently open
   if (PositionsTotal() == 0)
     {
      // Open a buy trade
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      trade.Buy(lotSize, _Symbol, price - stopLoss * _Point, price + takeProfit * _Point, "Sample Buy Trade");

      // Print the order details
      Print("Buy Order placed at price: ", price);
     }

   // Example: Close trade if certain conditions are met (e.g., price reaches a certain level)
   for (int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0 && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         if (SymbolInfoDouble(_Symbol, SYMBOL_BID) > openPrice + 20 * _Point)
           {
            trade.PositionClose(ticket);
            Print("Buy Order closed.");
           }
        }
     }
  }
//+------------------------------------------------------------------+
