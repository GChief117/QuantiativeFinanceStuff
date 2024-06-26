#include <stdlib.mqh>
#include <Trade\Trade.mqh>
#include <Math\Stat\Stat.mqh>

// Include the ONNX model as a resource
#resource "forexmodel-2.onnx" as uchar ExtModel[]

double leverage;
double stop_loss_percentage;
double target_capital;
double minimum_percentage;
double profit_cap_percentage;
double profit;
double entry_price;
double positions;
double initial_balance;
double current_balance;
double total_initial_balance;

CTrade trade;
long onnx_handle;

int OnInit() {
    // Initialize trading parameters
    leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    profit_cap_percentage = 2.0;
    stop_loss_percentage = -0.004;
    target_capital = 200000;
    minimum_percentage = 0.005;
    profit = 0;
    entry_price = 0;
    positions = 0;
    initial_balance = 100;
    total_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    current_balance = initial_balance;

    // Load the ONNX model from the resource buffer
    Print("Attempting to load ONNX model from resource buffer");
    onnx_handle = OnnxCreateFromBuffer(ExtModel, 0);
    if (onnx_handle == INVALID_HANDLE) {
        int error_code = GetLastError();
        Print("Error loading ONNX model: ", error_code);
        return INIT_FAILED;
    } else {
        Print("ONNX model loaded successfully.");
    }

    // Set the input shape for the ONNX model
    const long input_shape[] = {1, 10, 10};  // batch_size, sequence_length, 10 features
    if (!OnnxSetInputShape(onnx_handle, 0, input_shape)) {
        Print("Error setting input shape: ", GetLastError());
        OnnxRelease(onnx_handle);
        return INIT_FAILED;
    }

    // Set the output shape for the ONNX model
    const long output_shape[] = {1, 2};  // batch_size, num_classes (2 for buy and sell)
    if (!OnnxSetOutputShape(onnx_handle, 0, output_shape)) {
        Print("Error setting output shape: ", GetLastError());
        OnnxRelease(onnx_handle);
        return INIT_FAILED;
    }

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);

    PrintFormat("Expert initialized with balance: %f and leverage: %f", current_balance, leverage);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    if (onnx_handle != INVALID_HANDLE) {
        OnnxRelease(onnx_handle);
    }
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer() {
    // Fetch live data
    MqlRates rates[];
    int copied = CopyRates("GBPUSD", PERIOD_H1, 0, 10, rates);
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

    // Prepare input data for the ONNX model
    float input_data[1][10][10];  // batch_size, sequence_length, 10 features
    for (int i = 0; i < 10; i++) {
        input_data[0][i][0] = (rates[i].close - rates[i].open) / rates[i].open * 100;
        input_data[0][i][1] = (rates[i].high - rates[i].low) / rates[i].high * 100;
        input_data[0][i][2] = (i > 0) ? input_data[0][i-1][0] - input_data[0][i][0] : 0;
        input_data[0][i][3] = (i > 0 && input_data[0][i][2] > 0.01) ? 1 : 0;
        input_data[0][i][4] = (i < 9) ? input_data[0][i+1][3] : 0;
        // Fill the rest with zeros or other meaningful features
        for (int j = 5; j < 10; j++) {
            input_data[0][i][j] = 0;
        }
    }

    // Placeholder for predicted signals
    float output_data[1][2];  // batch_size, num_classes (2 for buy and sell)

    // Run the ONNX model for predictions
    if (!OnnxRun(onnx_handle, 0, input_data, output_data)) {
        Print("Error running ONNX model: ", GetLastError());
        return;
    }

    // Interpret the model output
    double predicted_buy_signal = output_data[0][0];
    double predicted_sell_signal = output_data[0][1];

    PrintFormat("Predicted Buy Signal: %f, Predicted Sell Signal: %f", predicted_buy_signal, predicted_sell_signal);

    // Implement your trading logic based on the predicted signals
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

    if (predicted_buy_signal > 0.5 && positions == 0) {
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
        sum += array[i * cols + column];
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
        sum += MathPow(array[i * cols + column] - mean_value, 2);
    }
    return MathSqrt(sum / rows);
}

bool ONNXPredict(double &features[], double &predicted_signals[], string model_path) {
    // Create ONNX session
    long session_handle = OnnxCreate(model_path, 0);
    if (session_handle == INVALID_HANDLE) {
        Print("Failed to create ONNX session");
        return false;
    }

    // Prepare input data for the ONNX model
    float input_data[];
    int rows = ArraySize(features) / 10; // Assuming each row has 10 features
    ArrayResize(input_data, rows * 10);
    for (int i = 0; i < rows * 10; i++) {
        input_data[i] = (float)features[i];
    }

    float output_data[1]; // Assuming a single output prediction

    // Run the ONNX model for predictions
    if (!OnnxRun(session_handle, 0, input_data, 0, output_data)) {
        Print("Error running ONNX model: ", GetLastError());
        OnnxRelease(session_handle);
        return false;
    }

    // Assign predictions to predicted_signals
    for (int i = 0; i < rows; i++) {
        predicted_signals[i] = output_data[0]; // Assuming the model returns 1 for buy and 0 for sell
    }

    OnnxRelease(session_handle);
    return true;
}
