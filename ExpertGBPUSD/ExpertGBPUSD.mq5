#include <stdlib.mqh>
#include <Trade\Trade.mqh>
#include <Math\Stat\Stat.mqh>

// Global variables for trading parameters
double leverage;
double stop_loss_percentage; // Use percentage
double target_capital;
double minimum_percentage; // Use percentage
double profit_cap_percentage;
double entry_price;
double positions;
double initial_balance; // Initial balance to start with
string onnx_model_path = "C:\\Users\\gunne\\Documents\\PriceNeuralNetwork\\Forex\\forexmodel-1.onnx";

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize trading parameters
    leverage = AccountInfoInteger(ACCOUNT_LEVERAGE); // Reflect initial leverage
    profit_cap_percentage = 2.0;
    stop_loss_percentage = -0.004;
    target_capital = 200000;
    minimum_percentage = 0.005; // 5 points for minimum profit
    entry_price = 0;
    positions = 0;
    initial_balance = 100; // Use only $100 of the initial capital

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);

    PrintFormat("Expert initialized with balance: %f and leverage: %f", initial_balance, leverage);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick event function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // Fetch live data
    MqlRates rates[];
    int copied = CopyRates("GBPUSD", PERIOD_H1, 0, 750, rates);
    if (copied <= 0) {
        Print("Failed to copy rates: ", GetLastError());
        return;
    }

    ArraySetAsSeries(rates, true);

    // Check array size before proceeding
    if (ArraySize(rates) == 0) {
        Print("No rates fetched.");
        return;
    }

    // Feature engineering
    double features[];
    ArrayResize(features, copied * 10);
    for (int i = 0; i < copied; i++) {
        features[i*10+0] = (rates[i].close - rates[i].open) / rates[i].open * 100;
        features[i*10+1] = (rates[i].high - rates[i].low) / rates[i].high * 100;
        features[i*10+2] = (i > 0) ? features[(i-1)*10+0] - features[i*10+0] : 0;
        features[i*10+3] = (i > 0 && features[i*10+2] > 0.01) ? 1 : 0;
        features[i*10+4] = (i < copied - 1) ? features[(i+1)*10+3] : 0;
    }

    // Placeholder for predicted signals
    double predicted_signals[];
    ArrayResize(predicted_signals, copied); 
    for (int i = 0; i < copied; i++) {
        predicted_signals[i] = 1;  // Set all predicted signals to 1
    }

    double current_price = rates[0].close;
    datetime date_time = rates[0].time;

    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double account_margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, balance: %f, equity: %f, margin: %f, free margin: %f",
                TimeToString(date_time), current_price, positions, account_balance, account_equity, account_margin, account_free_margin);

    if (account_balance >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Recalculate volume based on current balance
        double min_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MIN);
        double max_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MAX);
        double volume_step = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);

        double raw_volume = NormalizeDouble(leverage * ((account_balance-5) / current_price), 2);
        double volume = NormalizeDouble(raw_volume / 100000, 2);  // Convert to X.XX format and round to 2 decimal places

        // Ensure the volume is within the allowed range
        volume = MathMax(volume, min_volume);
        volume = MathMin(volume, max_volume);

        // Calculate margin required for the trade
        double margin;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, "GBPUSD", volume, current_price, margin)) {
            PrintFormat("Error calculating margin: %d", GetLastError());
            return;
        }

        entry_price = current_price;
        double stop_loss_price = entry_price * (1 + stop_loss_percentage); // Calculate stop loss by percentage
        double take_profit_price = entry_price * (1 + minimum_percentage); // Calculate take profit by percentage

        PrintFormat("Attempting to enter trade at %s: volume: %f, stop_loss: %f, take_profit: %f, equity: %f, margin: %f, free margin: %f",
                    TimeToString(date_time), volume, stop_loss_price, take_profit_price, account_equity, account_margin, account_free_margin);

        if (trade.BuyLimit(volume, entry_price, "GBPUSD", stop_loss_price, take_profit_price, ORDER_TIME_GTC, 0, "BuyLimit Order")) {
            positions = volume;
            PrintFormat("Entered position at time %s, price: %f, volume: %f, balance: %f, margin: %f, equity: %f, free margin: %f",
                        TimeToString(date_time), entry_price, volume, account_balance, margin, account_equity, account_margin, account_free_margin);
        } else {
            positions = 0;
            Print("Failed to place BuyLimit order");
        }
    }

    if (positions != 0) {
        double current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID);

        double profit;
        if (!OrderCalcProfit(ORDER_TYPE_BUY, "GBPUSD", positions, entry_price, current_price, profit)) {
            PrintFormat("Error calculating profit: %d", GetLastError());
            return;
        }

        double margin;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, "GBPUSD", positions, entry_price, margin)) {
            PrintFormat("Error calculating margin: %d", GetLastError());
            return;
        }

        double account_margin = AccountInfoDouble(ACCOUNT_MARGIN);
        double account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

        PrintFormat("OnTick: current price: %f, entry price: %f, profit: %f, balance: %f, margin: %f, volume: %f, equity: %f, free margin: %f",
                    current_price, entry_price, profit, account_balance, margin, positions, account_equity, account_margin, account_free_margin);

        // Calculate profit/loss as a percentage of entry price
        double profit_percentage = (profit / entry_price) * 100;

        // Check for stop loss condition
        if (current_price <= entry_price * (1 + stop_loss_percentage)) {
            if (trade.PositionClose(Symbol())) {
                PrintFormat("Stop loss triggered at time %s, price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                            TimeToString(TimeCurrent()), current_price, profit, account_balance, positions, account_equity, account_margin, account_free_margin);

                // Reset positions
                positions = 0;
                entry_price = 0;
            } else {
                Print("Failed to close position at stop loss");
            }
        } else if (profit_percentage >= profit_cap_percentage || profit_percentage >= minimum_percentage) {
            if (trade.PositionClose(Symbol())) {
                PrintFormat("Take profit or minimum profit percentage reached at time %s, price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                            TimeToString(TimeCurrent()), current_price, profit, account_balance, positions, account_equity, account_margin, account_free_margin);

                // Reset positions
                positions = 0;
                entry_price = 0;
            } else {
                Print("Failed to close position at take profit");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
double mean(double &array[], int rows, int cols, int column) {
    if (rows == 0 || cols == 0) {
        Print("Array size is zero in mean function");
        return 0.0;
    }

    double sum = 0;
    for (int i = 0; i < rows; i++) {
        sum += array[i*cols + column];
    }
    return sum / rows;
}

double std(double &array[], int rows, int cols, int column) {
    if (rows == 0 || cols == 0) {
        Print("Array size is zero in std function");
        return 0.0;
    }

    double mean_value = mean(array, rows, cols, column);
    double sum = 0;
    for (int i = 0; i < rows; i++) {
        sum += MathPow(array[i*cols + column] - mean_value, 2);
    }
    return MathSqrt(sum / rows);
}

bool ONNXPredict(double &features[], double &predicted_signals[], string onnx_model_path) {
    // Placeholder for ONNX session creation--for the onnx create we get the session already setup
    int session_handle = OnnxCreate(onnx_model_path, 0);
    if (session_handle == -1) {
        Print("Failed to create ONNX session");
        return false;
    }

    // Setting up prediction logic---and connect it with the ONNX model we loaded
    int rows = ArraySize(predicted_signals);
    for (int i = 0; i < rows; i++) {
        // Implement the placeholder prediction logic
        // Buying is when features[i*10+3] is 1, else 0
        predicted_signals[i] = (features[i*10+3] == 1) ? 1 : 0;
    }

    return true;
}


