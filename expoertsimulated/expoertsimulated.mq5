#include <stdlib.mqh>
#include <Trade\Trade.mqh>
#include <Math\Stat\Stat.mqh>

// Global variables for trading parameters
double leverage;
double profit_cap_percentage;
double stop_loss_percentage;
double target_capital;
double capital;
double minimum_percentage;
double profit;
double entry_price;
double positions;
string onnx_model_path = "C:\\Users\\gunne\\Documents\\PriceNeuralNetwork\\Forex\\forexmodel-1.onnx";
double stop_loss_price;
double take_profit_price;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize trading parameters
    leverage = AccountInfoInteger(ACCOUNT_LEVERAGE); // Reflect initial leverage
    profit_cap_percentage = 2.0;
    stop_loss_percentage = -0.004;
    target_capital = 400;
    capital = AccountInfoDouble(ACCOUNT_BALANCE);  // Reflect initial deposit
    minimum_percentage = 0.005;
    profit = 0;
    entry_price = 0;
    positions = 0;
    stop_loss_price = 0;
    take_profit_price = 0;

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);

    PrintFormat("Expert initialized with capital: %f and leverage: %f", capital, leverage);
    return(INIT_SUCCEEDED);
}

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

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
    double available_margin = equity - margin_used;

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, capital: %f, stop loss price: %f, take profit price: %f, equity: %f, available margin: %f", 
                TimeToString(date_time), current_price, positions, capital, stop_loss_price, take_profit_price, equity, available_margin);

    if (capital >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Enter position
        positions = leverage * (capital / current_price);
        positions = NormalizeDouble(positions / 10000, 2);  // Convert to lot size format X.XX
        entry_price = current_price;
        stop_loss_price = entry_price * (1 + stop_loss_percentage);
        take_profit_price = entry_price * (1 + minimum_percentage);

        // Execute trade
        if(trade.Buy(positions, "GBPUSD", current_price, stop_loss_price, take_profit_price)) {
            PrintFormat("Entered position at time %s, price: %f, positions: %f, capital: %f, stop loss price: %f, take profit price: %f", 
                        TimeToString(date_time), entry_price, positions, capital, stop_loss_price, take_profit_price);
        } else {
            PrintFormat("Failed to enter position at time %s, price: %f, positions: %f", 
                        TimeToString(date_time), current_price, positions);
        }
    }
}

//+------------------------------------------------------------------+
//| Tick event function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    if (positions != 0) {
        double current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID);
        double profit_percentage = (current_price - entry_price) / entry_price * 100;

        if (profit_percentage <= stop_loss_percentage) {
            // Apply the stop loss and exit the trade
            capital += (capital * profit_percentage);
            PrintFormat("Stop loss triggered at time %s, price: %f, capital: %f", TimeToString(TimeCurrent()), current_price, capital);

            // Reset positions
            positions = 0;
            entry_price = 0;
            stop_loss_price = 0;
            take_profit_price = 0;
        }

        if (profit_percentage >= minimum_percentage) {
            // Exit the positions and capture the profit
            profit = (positions * (current_price - entry_price));
            capital += profit;
            
            // Execute trade
            if(trade.Sell(positions, "GBPUSD", current_price)) {
                PrintFormat("Profit target reached at time %s, price: %f, profit_percentage: %f, profit: %f, capital: %f, stop loss price: %f, take profit price: %f", 
                            TimeToString(TimeCurrent()), current_price, profit_percentage, profit, capital, stop_loss_price, take_profit_price);
            } else {
                PrintFormat("Failed to exit position at time %s, price: %f, positions: %f", 
                            TimeToString(TimeCurrent()), current_price, positions);
            }

            // Reset positions
            positions = 0;
            entry_price = 0;
            stop_loss_price = 0;
            take_profit_price = 0;
        }
    }
}

// Helper functions
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
