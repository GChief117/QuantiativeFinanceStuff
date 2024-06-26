#include <stdlib.mqh>
#include <Trade\Trade.mqh>
#include <Math\Stat\Stat.mqh>

// Resource for the ONNX model
#resource "forexmodel-2.onnx" as uchar ExtModel[]

// Global variables for trading parameters
double leverage;
double stop_loss_percentage; // Use percentage
double target_capital;
double minimum_percentage; // Use percentage
double profit_cap_percentage;
double profit;
double entry_price;
double positions;
double initial_balance; // Initial balance to start with
double current_balance; // Current balance during operations
double total_initial_balance; // Total initial balance available

CTrade trade;
long session_handle = INVALID_HANDLE;

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
    profit = 0;
    entry_price = 0;
    positions = 0;
    initial_balance = 100; // Use only $100 of the initial capital
    total_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE); // Starting with $1000 total initial balance
    current_balance = initial_balance; // Set initial current balance to $100

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);

    PrintFormat("Expert initialized with balance: %f and leverage: %f", current_balance, leverage);
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
    if (!ONNXPredict(features, predicted_signals)) {
        Print("ONNX prediction failed");
        return;
    }

    double current_price = rates[0].close;
    datetime date_time = rates[0].time;

    double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double account_margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, balance: %f, equity: %f, margin: %f, free margin: %f",
                TimeToString(date_time), current_price, positions, current_balance, account_equity, account_margin, account_free_margin);

    if (current_balance >= target_capital) {
        PrintFormat("Target capital of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        return;
    }

    if (predicted_signals[0] == 1 && positions == 0) {
        // Recalculate volume based on current balance
        double min_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MIN);
        double max_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MAX);
        double volume_step = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);

        double raw_volume = NormalizeDouble(leverage * ((current_balance) / current_price), 2);
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
                        TimeToString(date_time), entry_price, volume, current_balance, margin, account_equity, account_margin, account_free_margin);
        } else {
            positions = 0;
            Print("Failed to place BuyLimit order");
        }
    }
}

//+------------------------------------------------------------------+
//| Tick event function                                              |
//+------------------------------------------------------------------+
void OnTick() {
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

        double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double account_margin = AccountInfoDouble(ACCOUNT_MARGIN);
        double account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

        PrintFormat("OnTick: current price: %f, entry price: %f, profit: %f, balance: %f, margin: %f, volume: %f, equity: %f, free margin: %f",
                    current_price, entry_price, profit, current_balance, margin, positions, account_equity, account_margin, account_free_margin);

        // Calculate profit/loss as a percentage of entry price
        double profit_percentage = (profit / entry_price) * 100;

        // Check for stop loss condition
        if (current_price <= entry_price * (1 + stop_loss_percentage)) {
            double close_price = current_price;
            bool result = trade.Sell(positions, "GBPUSD");
            if (result) {
                profit = (close_price - entry_price) * positions * SymbolInfoDouble("GBPUSD", SYMBOL_TRADE_TICK_VALUE);

                PrintFormat("Stop loss triggered at time %s, price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                            TimeToString(TimeCurrent()),
                            close_price,
                            profit,
                            current_balance,
                            positions,
                            account_equity,
                            account_margin,
                            account_free_margin);

                // Reset positions
                positions = 0;
                entry_price = 0;

                // Update current_balance for further calculations
                current_balance += profit;
            } else {
                Print("Failed to place Sell order for closing position");
            }
        } else if (profit_percentage >= profit_cap_percentage || profit_percentage >= minimum_percentage) {
            double close_price = current_price;
            bool result = trade.Sell(positions, "GBPUSD");
            if (result) {
                PrintFormat("Take profit or minimum profit percentage reached at time %s, price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                            TimeToString(TimeCurrent()),
                            close_price,
                            profit,
                            current_balance,
                            positions,
                            account_equity,
                            account_margin,
                            account_free_margin);

                // Reset positions
                positions = 0;
                entry_price = 0;

                // Update current_balance for further calculations
                current_balance += profit;
            } else {
                Print("Failed to place Sell order for closing position");
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

bool ONNXPredict(double &features[], double &predicted_signals[]) {
    static long session_handle = INVALID_HANDLE;

    if (session_handle == INVALID_HANDLE) {
        // Create the ONNX session from buffer
        session_handle = OnnxCreateFromBuffer(ExtModel, ONNX_DEBUG_LOGS);
        if (session_handle == INVALID_HANDLE) {
            Print("Failed to create ONNX session");
            return false;
        }

        // Define input and output shapes
        const long input_shape[] = {1, 500, 10}; // batch_size, sequence_length, num_features
        if (!OnnxSetInputShape(session_handle, 0, input_shape)) {
            Print("OnnxSetInputShape error ", GetLastError());
            OnnxRelease(session_handle);
            session_handle = INVALID_HANDLE;
            return false;
        }

        const long output_shape[] = {1, 2}; // batch_size, num_classes
        if (!OnnxSetOutputShape(session_handle, 0, output_shape)) {
            Print("OnnxSetOutputShape error ", GetLastError());
            OnnxRelease(session_handle);
            session_handle = INVALID_HANDLE;
            return false;
        }
    }

    // Prepare the input data
    static matrixf input_data(10, 10); // sequence_length, num_features
    static vectorf output_data(2); // num_classes
    static matrix mm(10, 10);
    static matrix ms(10, 10);

    // Normalize features
    matrix x_norm(10, 10); // Initialize x_norm with the appropriate size
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 10; j++) {
            x_norm[i][j] = features[i * 10 + j]; // Assign features to x_norm
        }
    }
    
    vector m = x_norm.Mean(0);
    vector s = x_norm.Std(0);
    for (int i = 0; i < 10; i++) {
        mm.Row(m, i);
        ms.Row(s, i);
    }
    x_norm -= mm;
    x_norm /= ms;

    input_data.Assign(x_norm); // Ensure input_data is assigned correctly

    // Run the model
    if (!OnnxRun(session_handle, ONNX_DEBUG_LOGS, input_data, output_data)) {
        Print("OnnxRun error ", GetLastError());
        return false;
    }

    // Process the output
    double y_pred_0 = output_data[0];
    double y_pred_1 = output_data[1];
    predicted_signals[0] = (y_pred_1 > y_pred_0) ? 1 : 0;

    return true;
}

// Function to release the ONNX session when the expert advisor is deinitialized
void OnDeinit(const int reason) {
    if (session_handle != INVALID_HANDLE) {
        OnnxRelease(session_handle);
        session_handle = INVALID_HANDLE;
    }
}
