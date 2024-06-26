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
    profit_cap_percentage = 50;
    stop_loss_percentage = -20;
    target_capital = 200000;
    capital = AccountInfoDouble(ACCOUNT_BALANCE);  // Reflect initial deposit
    minimum_percentage = 20;
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
    double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, capital: %f, stop loss price: %f, take profit price: %f, equity: %f, margin used: %f, free margin: %f", 
                TimeToString(date_time), current_price, positions, capital, stop_loss_price, take_profit_price, equity, margin_used, free_margin);

    if (capital >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Enter position based on available free margin
        double lots = 0.01;  // Start with the minimum lot size
        double margin = 0;
        
        while (true) {
            if (OrderCalcMargin(ORDER_TYPE_BUY, "GBPUSD", lots, current_price, margin)) {
                if (free_margin < margin) {
                    // Decrease lot size if not enough free margin
                    lots -= 0.01;
                    break;
                }
                lots += 0.01;  // Increment lot size
            } else {
                PrintFormat("Failed to calculate margin for lots: %f at price: %f", lots, current_price);
                break;
            }
        }

        if (lots > 0) {
            positions = lots;
            entry_price = current_price;
            stop_loss_price = entry_price * (1 + stop_loss_percentage);
            take_profit_price = entry_price * (1 + minimum_percentage);

            if (trade.Buy(lots, "GBPUSD", current_price, stop_loss_price, take_profit_price)) {
                UpdateAccountMetrics(); // Update account metrics after entering position
                double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
                double new_margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
                double new_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
                capital = AccountInfoDouble(ACCOUNT_BALANCE);

                PrintFormat("Entered position at time %s, price: %f, positions: %f, capital: %f, stop loss price: %f, take profit price: %f, equity: %f, margin used: %f, free margin: %f", 
                            TimeToString(date_time), entry_price, positions, capital, stop_loss_price, take_profit_price, new_equity, new_margin_used, new_free_margin);
            } else {
                PrintFormat("Failed to enter position at time %s, price: %f, positions: %f", 
                            TimeToString(date_time), current_price, positions);
            }
        } else {
            PrintFormat("Not enough free margin to open any position. Available: %f", free_margin);
        }
    }
}

//+------------------------------------------------------------------+
//| Tick event function                                              |
//+------------------------------------------------------------------+
void UpdateAccountMetrics() {
    capital = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
    double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    PrintFormat("Account updated - Capital: %f, Equity: %f, Margin Used: %f, Free Margin: %f", 
                capital, equity, margin_used, free_margin);
}

void OnTick() {
    if (positions != 0) {
        double current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID);
        double profit = 0.0;

        if (OrderCalcProfit(ORDER_TYPE_BUY, "GBPUSD", entry_price, current_price, positions, profit)) {
            double profit_percentage = profit / (positions * 100000) * 100;

            if (profit_percentage <= stop_loss_percentage) {
                // Apply the stop loss and exit the trade
                if (trade.Sell(positions, "GBPUSD", current_price)) {
                    UpdateAccountMetrics(); // Update account metrics after stop-loss
                    double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
                    double new_margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
                    double new_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

                    PrintFormat("Stop loss triggered at time %s, price: %f, capital: %f, equity: %f, margin used: %f, free margin: %f", 
                                TimeToString(TimeCurrent()), current_price, capital, new_equity, new_margin_used, new_free_margin);

                    // Reset positions
                    positions = 0;
                    entry_price = 0;
                    stop_loss_price = 0;
                    take_profit_price = 0;
                } else {
                    PrintFormat("Failed to exit position at stop loss at time %s, price: %f, positions: %f", 
                                TimeToString(TimeCurrent()), current_price, positions);
                }
            }

            if (profit_percentage >= minimum_percentage) {
                // Exit the positions and capture the profit
                if (trade.Sell(positions, "GBPUSD", current_price)) {
                    UpdateAccountMetrics(); // Update account metrics after taking profit
                    double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
                    double new_margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
                    double new_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

                    PrintFormat("Profit target reached at time %s, price: %f, profit_percentage: %f, profit: %f, capital: %f, stop loss price: %f, take profit price: %f, equity: %f, margin used: %f, free margin: %f", 
                                TimeToString(TimeCurrent()), current_price, profit_percentage, profit, capital, stop_loss_price, take_profit_price, new_equity, new_margin_used, new_free_margin);
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
        } else {
            PrintFormat("Failed to calculate profit at time %s, price: %f, positions: %f", 
                        TimeToString(TimeCurrent()), current_price, positions);
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
