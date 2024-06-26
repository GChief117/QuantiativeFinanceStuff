#include <stdlib.mqh>
#include <Trade\Trade.mqh>
#include <Math\Stat\Stat.mqh>

// Global variables for trading parameters
double leverage;
double stop_loss_points; // Use points instead of percentage
double take_profit_points; // Use points instead of percentage
double target_capital;
double minimum_points; // Use points instead of percentage
double entry_price;
double positions;
double current_balance; // Current balance during operations
double equity; // Current equity during operations
string onnx_model_path = "C:\\Users\\gunne\\Documents\\PriceNeuralNetwork\\Forex\\forexmodel-1.onnx";

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize trading parameters
    leverage = AccountInfoInteger(ACCOUNT_LEVERAGE); // Reflect initial leverage
    stop_loss_points = 30; // 40 points for stop loss
    take_profit_points = 10; // 40 points for take profit
    target_capital = 200000;
    minimum_points = 5; // 10 points for minimum profit
    entry_price = 0;
    positions = 0;
    current_balance = AccountInfoDouble(ACCOUNT_BALANCE); // Set initial current balance
    equity = AccountInfoDouble(ACCOUNT_EQUITY); // Set initial equity

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);

    PrintFormat("Expert initialized with balance: %f and leverage: %f", current_balance, leverage);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer() {
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

    // Update current balance and equity
    current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    equity = AccountInfoDouble(ACCOUNT_EQUITY);

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, balance: %f, equity: %f", 
                TimeToString(date_time), current_price, positions, current_balance, equity);

    if (current_balance >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Recalculate volume based on current balance
        double min_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MIN);
        double max_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MAX);
        double volume_step = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);

        double raw_volume = NormalizeDouble(leverage * (equity / current_price), 2);
        double volume = NormalizeDouble(raw_volume / 100000, 2);  // Convert to X.XX format and round to 2 decimal places

        // Ensure the volume is within the allowed range
        volume = MathMax(volume, min_volume);
        volume = MathMin(volume, max_volume);

        // Check if there is sufficient balance to enter the trade
        if (equity < volume * current_price) {
            PrintFormat("Insufficient equity to enter trade: equity %f, required %f", equity, volume * current_price);
            return;
        }

        entry_price = current_price;
        double stop_loss_price = entry_price + (stop_loss_points * SymbolInfoDouble("GBPUSD", SYMBOL_POINT)); // Calculate stop loss by points
        double take_profit_price = entry_price - (take_profit_points * SymbolInfoDouble("GBPUSD", SYMBOL_POINT)); // Calculate take profit by points

        // Ensure stop loss and take profit levels are valid
        double stop_level = SymbolInfoInteger("GBPUSD", SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble("GBPUSD", SYMBOL_POINT);
        if (MathAbs(stop_loss_price - entry_price) < stop_level || MathAbs(take_profit_price - entry_price) < stop_level) {
            PrintFormat("Invalid stops: stop_loss: %f, take_profit: %f, stop_level: %f", stop_loss_price, take_profit_price, stop_level);
            return;
        }

        PrintFormat("Attempting to enter trade at %s: volume: %f, stop_loss: %f, take_profit: %f", TimeToString(date_time), volume, stop_loss_price, take_profit_price);

        if (trade.Sell(volume, "GBPUSD", current_price, stop_loss_price, take_profit_price, "Sell Order")) {
            positions = volume;
            PrintFormat("Entered position at time %s, price: %f, volume: %f, balance: %f, equity: %f", 
                        TimeToString(date_time), entry_price, volume, current_balance, equity);
        } else {
            positions = 0;
            Print("Failed to place Sell order");
        }
    }
}


//+------------------------------------------------------------------+
//| Tick event function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    if (positions != 0) {
        double current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID);
        double profit_points = (current_price - entry_price) / SymbolInfoDouble("GBPUSD", SYMBOL_POINT); // Convert profit to points

        PrintFormat("OnTick: current price: %f, entry price: %f, profit points: %f", current_price, entry_price, profit_points);

        if (profit_points <= -stop_loss_points || profit_points >= take_profit_points || profit_points >= minimum_points) {
            double close_price = current_price;
            bool result = trade.Buy(positions, "GBPUSD");
            if (result) {
                PrintFormat("%s triggered at time %s, price: %f, profit points: %f, balance: %f, equity: %f", 
                            profit_points <= -stop_loss_points ? "Stop loss" : 
                            (profit_points >= take_profit_points ? "Take profit" : "Minimum profit points"), 
                            TimeToString(TimeCurrent()), 
                            close_price, 
                            profit_points,
                            AccountInfoDouble(ACCOUNT_BALANCE),
                            AccountInfoDouble(ACCOUNT_EQUITY));

                // Reset positions
                positions = 0;
                entry_price = 0;

                // Update account balance and equity
                current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
                equity = AccountInfoDouble(ACCOUNT_EQUITY);
            } else {
                Print("Failed to place Buy order for closing position");
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
