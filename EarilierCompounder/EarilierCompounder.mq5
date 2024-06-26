#include <Trade\Trade.mqh>

CTrade trade;

// Global variables
double initial_balance;
double target_balance = 400;
double leverage = 200;
double risk_percentage = 0.01; // 1% risk per trade
double peak_equity = 0;


int OnInit()
{
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("Initial Balance: ", initial_balance);
    return INIT_SUCCEEDED;
}

void OnTick()
{
    ExecuteTrades();
}

void ExecuteTrades()
{
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

    // Update peak equity
    if (current_equity > peak_equity)
    {
        peak_equity = current_equity;
    }

    // Check if equity has reached a peak and should be locked in
    if (current_equity >= peak_equity * 1.05) // Example threshold: 5% above peak
    {
        CloseAllTrades();
        peak_equity = 0; // Reset peak equity after closing trades
    }

    if (current_balance >= target_balance)
    {
        Print("Target balance achieved. Stopping trading.");
        return;
    }

    double lot_size = CalculateLotSize(current_balance);
    double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double stop_loss = CalculateStopLoss(price);
    double take_profit = CalculateTakeProfit(price);

    if (ConditionsToBuy())
    {
        datetime expiration = TimeCurrent() + PeriodSeconds(); // Set expiration time to 1 period ahead (e.g., 1 minute if on M1)
        trade.BuyLimit(lot_size, price, Symbol(), stop_loss, take_profit, 0, "Buy GBPUSD", expiration);
    }
}

void CloseAllTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        trade.PositionClose(ticket);
    }
}

double CalculateLotSize(double balance)
{
    double risk_amount = balance * risk_percentage;
    double lot_size = (risk_amount / (100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)));
    lot_size = lot_size / 100000; // Convert to standard lots (e.g., 1,000 units = 0.01 lot)
    lot_size = NormalizeDouble(lot_size, 2);
    return lot_size;
}

double CalculateStopLoss(double price)
{
    double stop_loss = price - (50 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // 50 pips SL
    return NormalizeDouble(stop_loss, SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

double CalculateTakeProfit(double price)
{
    double take_profit = price + (100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // 100 pips TP
    return NormalizeDouble(take_profit, SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

bool ConditionsToBuy()
{
    // Add your custom logic to determine buy conditions
    // Example: simple Moving Average cross or RSI
    
    /*
    
    This is where we input our model and snce this is a boolean this will work perfect withour conditions to buy
    
    
    We will impleent our forexmodel here 
    
    
    */
    
    return true;
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
    // Handle trade events
    if (result.retcode == TRADE_RETCODE_DONE)
    {
        Print("Trade executed successfully: ", request.comment);
    }
    else
    {
        Print("Trade failed: ", result.comment);
    }
}
