//+------------------------------------------------------------------+
//|                                                     MyExpert.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             http://www.mql5.com/ |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

// Inputs
input double TakeProfitPoints = 50;  // Take profit in points
input double StopLossPoints = 20;    // Stop loss in points
input double InitialBalance = 100; // Initial balance
input double TargetBalance = 200000; // Target balance
input int Leverage = 200;     // Leverage
input double RiskPercent = 2; // Risk percentage per trade

// Global variables
double LotSize;
CTrade trade;
double PreviousBalance = 0; // To store previous balance for compounding

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Expert Initialized");
   PreviousBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Expert Deinitialized");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

   Print("Balance: ", balance, ", Equity: ", equity, ", Free Margin: ", freeMargin);

   // Check if target balance is reached
   if(balance >= TargetBalance)
     {
      Print("Target balance reached!");
      ExpertRemove();
      return;
     }

   // Manage existing positions
   ManageOpenPositions();

   // Check if new trade needs to be placed based on profit compounding
   if(balance > PreviousBalance)
     {
      LotSize = CalculateLotSize(balance, Leverage, RiskPercent);
      PreviousBalance = balance;

      // Place a Buy Limit order
      PlaceBuyLimitOrder(LotSize, StopLossPoints, TakeProfitPoints);
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double balance, int leverage, double riskPercent)
  {
   // Calculate risk amount per trade
   double riskAmount = balance * (riskPercent / 100.0);

   // Calculate pip value (assuming GBP/USD where pip value is approximately $10 for 1 lot)
   double pipValue = 10.0;

   // Calculate maximum lot size based on risk amount and stop loss
   double maxLot = riskAmount / (StopLossPoints * pipValue);

   // Normalize lot size based on leverage
   double lotSize = NormalizeDouble(maxLot, 2); // Normalize to 2 decimal places

   Print("Calculated Lot Size: ", lotSize);
   return(lotSize);
  }

//+------------------------------------------------------------------+
//| Place Buy Limit Order                                            |
//+------------------------------------------------------------------+
void PlaceBuyLimitOrder(double lotSize, double stopLossPoints, double takeProfitPoints)
  {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = currentPrice - 10 * _Point; // Adjust price to be below the current market price
   double sl = price - stopLossPoints * _Point;
   double tp = price + takeProfitPoints * _Point;

   Print("Placing Buy Limit Order: Lot Size: ", lotSize, ", Price: ", price, ", SL: ", sl, ", TP: ", tp);
   
   if(trade.BuyLimit(lotSize, price, _Symbol, sl, tp))
     {
      Print("Buy Limit Order placed successfully!");
     }
   else
     {
      Print("Error placing Buy Limit Order: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Check for Open Positions and Manage Them                         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelect(PositionGetSymbol(i)))
        {
         double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double stopLoss = PositionGetDouble(POSITION_SL);
         double takeProfit = PositionGetDouble(POSITION_TP);

         // Implement any additional logic to manage open positions here
         // For example, trailing stop, moving take profit, etc.
        }
     }
  }
