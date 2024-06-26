#include <Trade\Trade.mqh>
CTrade trade;

// Include the ONNX model as a resource
#resource "forexmodel-2.onnx" as uchar ExtModel[]
const long ExtOutputShape[] = {1, 2};   // Binary classification output
const long ExtInputShape[] = {1, 10, 10}; // Input shape matching the model

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("HighLeverageEA initialized.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("HighLeverageEA deinitialized.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    double initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double target_balance = 300;
    int days_to_target = 5;
    double daily_growth_rate = pow(target_balance / initial_balance, 1.0 / days_to_target);
    double account_balance, account_leverage, account_free_margin, account_equity;
    double sl_pips = 50;  // Example stop-loss in pips
    double tp_pips = 100; // Example take-profit in pips

    account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    account_leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    account_free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    account_equity = AccountInfoDouble(ACCOUNT_EQUITY);

    if (account_balance < target_balance) {
        ExecuteTrade(sl_pips, tp_pips);
        ManageRisk(sl_pips);
        account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if (account_balance >= initial_balance * daily_growth_rate) {
            initial_balance = account_balance;
            sl_pips = MathMax(10, sl_pips * 0.9); // Adjust stop-loss as balance grows
            tp_pips = MathMin(200, tp_pips * 1.1); // Adjust take-profit as balance grows
        }
    }
}

//+------------------------------------------------------------------+
//| Execute trade function                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(double sl_pips, double tp_pips) {
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double account_leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    double account_free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Calculate lot size dynamically
    double lot_size = MathMin(0.01, account_free_margin * account_leverage * 0.01 / 10000); // Example calculation

    // Fetch OHLC data for feature engineering
    MqlRates rates[];
    if (CopyRates(_Symbol, PERIOD_H1, 0, 10, rates) != 10) {
        Print("Failed to get rates data.");
        return;
    }

    // Feature engineering
    double Change_Open_Close[10];
    double Change_High_Low[10];
    double Profit_Between_Time_Series[10];
    for (int i = 1; i < 10; i++) {
        Change_Open_Close[i] = ((rates[i].close - rates[i].open) / rates[i].open) * 100;
        Change_High_Low[i] = ((rates[i].high - rates[i].low) / rates[i].high) * 100;
        Profit_Between_Time_Series[i] = Change_Open_Close[i] - Change_Open_Close[i - 1];
    }

    // Normalize the input data
    double m[3] = {Mean(Change_Open_Close), Mean(Change_High_Low), Mean(Profit_Between_Time_Series)};
    double s[3] = {StdDev(Change_Open_Close), StdDev(Change_High_Low), StdDev(Profit_Between_Time_Series)};
    double x_norm[10][3];
    for (int i = 0; i < 10; i++) {
        x_norm[i][0] = (Change_Open_Close[i] - m[0]) / s[0];
        x_norm[i][1] = (Change_High_Low[i] - m[1]) / s[1];
        x_norm[i][2] = (Profit_Between_Time_Series[i] - m[2]) / s[2];
    }

    // Create the model
    long handle = OnnxCreateFromBuffer(ExtModel, ONNX_DEBUG_LOGS);

    // Specify the shape of the input data
    if (!OnnxSetInputShape(handle, 0, ExtInputShape)) {
        Print("OnnxSetInputShape failed, error ", GetLastError());
        OnnxRelease(handle);
        return;
    }

    // Specify the shape of the output data
    if (!OnnxSetOutputShape(handle, 0, ExtOutputShape)) {
        Print("OnnxSetOutputShape failed, error ", GetLastError());
        OnnxRelease(handle);
        return;
    }

    // Convert normalized input data to float type
    float x_normf[10][3];
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 3; j++) {
            x_normf[i][j] = (float)x_norm[i][j];
        }
    }

    // Get the output data of the model here, i.e., the buy/sell signal
    float y_norm[2];
    if (!OnnxRun(handle, ONNX_DEBUG_LOGS | ONNX_NO_CONVERSION, x_normf, y_norm)) {
        Print("OnnxRun failed, error ", GetLastError());
        OnnxRelease(handle);
        return;
    }

    // Print model output for debugging
    Print("Model output: ", y_norm[0], ", ", y_norm[1]);

    // Determine the buy/sell signal
    int buy_signal = y_norm[0] > y_norm[1] ? 1 : 0;

    // Print buy signal for debugging
    Print("Buy signal: ", buy_signal);

    // Release the model handle
    OnnxRelease(handle);

    // Execute trades based on the model's prediction
    if (buy_signal == 1) {
        double price_open = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double sl_price = price_open - sl_pips * _Point;
        double tp_price = price_open + tp_pips * _Point;

        // Calculate margin and profit
        double margin_required = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot_size, price_open, sl_price);
        double potential_profit = OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, lot_size, price_open, tp_price, sl_price);

        // Ensure there is enough free margin
        if (account_free_margin >= margin_required) {
            // Place a Buy Limit order
            double buy_limit_price = price_open - 20 * _Point; // Example Buy Limit Price
            if (!trade.BuyLimit(lot_size, buy_limit_price, _Symbol, sl_price, tp_price, ORDER_TIME_GTC, 0, "Buy Limit Order")) {
                Print("OrderSend failed with error #", GetLastError());
            } else {
                Print("Buy Limit Order placed successfully");
            }
        } else {
            Print("Not enough free margin to place the order");
        }
    } else {
        Print("No buy signal, no trade executed");
    }
}


//+------------------------------------------------------------------+
//| Manage risk function                                             |
//+------------------------------------------------------------------+
void ManageRisk(double sl_pips) {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (PositionSelect(PositionGetSymbol(i))) {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY || PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double new_stop_loss = current_price - (sl_pips * _Point);
                if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && new_stop_loss > PositionGetDouble(POSITION_SL)) ||
                    (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && new_stop_loss < PositionGetDouble(POSITION_SL))) {
                    trade.PositionModify(PositionGetInteger(POSITION_TICKET), new_stop_loss, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
double Mean(const double &array[]) {
    int size = ArraySize(array);
    double sum = 0;
    for (int i = 0; i < size; i++) {
        sum += array[i];
    }
    return sum / size;
}

double StdDev(const double &array[]) {
    int size = ArraySize(array);
    double mean = Mean(array);
    double sum = 0;
    for (int i = 0; i < size; i++) {
        sum += pow(array[i] - mean, 2);
    }
    return sqrt(sum / size);
}
