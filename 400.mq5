#include <Trade\Trade.mqh>

CTrade trade;

double initial_balance;
double target_balance = 400.0;
double risk_percentage = 1.0; 
int slippage = 5; 
int take_profit_pips = 50;
int stop_loss_pips = 20;

int OnInit()
{
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("Initial Balance: ", initial_balance);
    
    return INIT_SUCCEEDED;
}

void OnTick()
{
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    Print("Balance: ", account_balance);
    Print("Equity: ", equity);
    Print("Free Margin: ", free_margin);
    Print("Margin: ", margin);

    if (account_balance >= target_balance)
    {
        Print("Target balance reached. Stopping the script.");
        ExpertRemove();
        return;
    }

    double volume = NormalizeDouble((account_balance / 100000), 2);

    if (volume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
    {
        volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    }

    if (PositionsTotal() == 0)
    {
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 10 * _Point; 
        double stop_loss = price - stop_loss_pips * _Point;
        double take_profit = price + take_profit_pips * _Point;

        trade.BuyLimit(volume, price, _Symbol, stop_loss, take_profit, NULL, slippage);
    }
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            double position_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double new_stop_loss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - stop_loss_pips * _Point;
            
            if (new_stop_loss > position_price)
            {
                trade.PositionModify(ticket, new_stop_loss, PositionGetDouble(POSITION_TP));
            }
        }
    }
}

double CalculateRisk(double balance, double risk_percent)
{
    return balance * (risk_percent / 100.0);
}

double CalculateLotSize(double risk, double stop_loss_pips)
{
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lot_size = risk / (stop_loss_pips * pip_value);
    return NormalizeDouble(lot_size, 2);
}
