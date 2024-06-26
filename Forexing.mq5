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

// Create an instance of CTrade
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize trading parameters
    leverage = 200; // Reflect initial leverage
    profit_cap_percentage = 2.0;
    stop_loss_percentage = -0.004;
    target_capital = 200000;
    capital = 100;  // Reflect initial deposit
    minimum_percentage = 0.005;
    profit = 0;
    entry_price = 0;
    positions = 0;

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
    double features[][10];
    ArrayResize(features, copied);
    for (int i = 0; i < copied; i++) {
        features[i][0] = (rates[i].close - rates[i].open) / rates[i].open * 100;
        features[i][1] = (rates[i].high - rates[i].low) / rates[i].high * 100;
        features[i][2] = (i > 0) ? features[i][0] - features[i-1][0] : 0;
        features[i][3] = (i > 0 && features[i][2] > 0.01) ? 1 : 0;
        features[i][4] = (i < copied - 1) ? features[i+1][3] : 0;
    }

    int num_features = 5; // Number of features used

    // Scale features
    double scaled_features[][10];
    ArrayResize(scaled_features, copied);
    for (int i = 0; i < copied; i++) {
        for (int j = 0; j < num_features; j++) {
            double mean_val = mean(features, copied, num_features, j);
            double std_val = std(features, copied, num_features, j);
            if (std_val != 0) {
                scaled_features[i][j] = (features[i][j] - mean_val) / std_val;
            } else {
                scaled_features[i][j] = 0;
            }
        }
    }

    // Predicting buy signals using ONNX model
    double predicted_signals[];
    ArrayResize(predicted_signals, copied);
    if (!ONNXPredict(scaled_features, predicted_signals, onnx_model_path)) {
        Print("Failed to predict signals using ONNX model");
        return;
    }

    double current_price = rates[0].close;
    datetime date_time = rates[0].time;

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, capital: %f", TimeToString(date_time), current_price, positions, capital);

    if (capital >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Limit the amount used to a fixed value (e.g., 100)
        double amount_to_use = 100.0;
        double lot_size = amount_to_use / current_price; // Corrected calculation
        lot_size = NormalizeDouble(lot_size, 2); // Ensuring lot size is rounded to the nearest 0.01

        // Check if lot size is valid
        double min_lot = 0.01;
        double lot_step = 0.01;
        double max_lot = 200.00;

        if (lot_size < min_lot) {
            lot_size = min_lot;
        } else if (lot_size > max_lot) {
            lot_size = max_lot;
        } else {
            lot_size = MathCeil(lot_size / lot_step) * lot_step;
            lot_size = NormalizeDouble(lot_size, 2); // Ensure rounding correctness
        }

        PrintFormat("Attempting to buy with lot size: %f", lot_size);

        if (trade.Buy(lot_size, "GBPUSD")) {
            positions = lot_size;
            entry_price = current_price;
            PrintFormat("Entered position at time %s, price: %f, positions: %f, capital: %f", TimeToString(date_time), entry_price, positions, capital);
        } else {
            int error_code = GetLastError();
            PrintFormat("Failed to enter position at time %s, error: %d", TimeToString(date_time), error_code);
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
            if (trade.PositionClose("GBPUSD")) {
                profit = positions * (profit_percentage);
                capital += (capital * profit_percentage);
                PrintFormat("Stop loss triggered at time %s, price: %f, capital: %f", TimeToString(TimeCurrent()), current_price, profit_percentage, profit, capital);

                // Reset positions
                positions = 0;
                entry_price = 0;
            } else {
                int error_code = GetLastError();
                PrintFormat("Failed to close position at stop loss at time %s, error: %d", TimeToString(TimeCurrent()), error_code);
            }
        }

        if (profit_percentage >= minimum_percentage) {
            // Exit the positions and capture the profit
            if (trade.PositionClose("GBPUSD")) {
                profit = positions * (current_price - entry_price);
                capital += profit;
                PrintFormat("Profit target reached at time %s, price: %f, profit_percentage: %f, profit: %f, capital: %f", TimeToString(TimeCurrent()), current_price, profit_percentage, profit, capital);

                // Reset positions
                positions = 0;
                entry_price = 0;
            } else {
                int error_code = GetLastError();
                PrintFormat("Failed to close position at profit target at time %s, error: %d", TimeToString(TimeCurrent()), error_code);
            }
        }
    }
}

// Helper functions
double mean(double &array[][10], int rows, int cols, int column) {
    if (rows == 0 || cols == 0) {
        Print("Array size is zero in mean function");
        return 0.0;
    }

    if (column >= cols) {
        PrintFormat("Column %d out of range in mean function", column);
        return 0.0;
    }

    double sum = 0;
    for (int i = 0; i < rows; i++) {
        sum += array[i][column];
    }
    return sum / rows;
}

double std(double &array[][10], int rows, int cols, int column) {
    if (rows == 0 || cols == 0) {
        Print("Array size is zero in std function");
        return 0.0;
    }

    if (column >= cols) {
        PrintFormat("Column %d out of range in std function", column);
        return 0.0;
    }

    double mean_value = mean(array, rows, cols, column);
    double sum = 0;
    for (int i = 0; i < rows; i++) {
        sum += MathPow(array[i][column] - mean_value, 2);
    }
    return MathSqrt(sum / rows);
}

// Placeholder for ONNX prediction function
bool ONNXPredict(double &features[][10], double &predicted_signals[], string onnx_model_path) {
    // Implement ONNX prediction logic
    // This is a placeholder function, replace it with actual ONNX inference code
    ArrayResize(predicted_signals, ArraySize(features));
    for (int i = 0; i < ArraySize(features); i++) {
        predicted_signals[i] = 1;  // Example prediction
    }
    return true;
}