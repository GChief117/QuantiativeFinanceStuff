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
double initial_balance = 100; // Initial balance to start with
double daily_trading_balance; // Balance used for trading each day
double daily_profit;
datetime trading_day_start;
string onnx_model_path = "C:\\Users\\gunne\\Documents\\PriceNeuralNetwork\\Forex\\forexmodel-1.onnx";
ulong order_ticket;
bool target_reached_today = false; // Flag to check if target is reached today
int days = 0; // Counter for tracking the number of trading days
double previous_day_balance = 0; // Previous day's balance
double start_of_day_balance = 0; // Balance at the start of the trading day
bool is_first_day = true; // Flag to check if it's the first day of trading
double close_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID); // Capture the actual close price
double initial_stop_loss_price;
double profit_array[15]; // Circular buffer for profit values
datetime short_position_time; // Time when short position was opened

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize trading parameters
    leverage = AccountInfoInteger(ACCOUNT_LEVERAGE); // Reflect initial leverage
    profit_cap_percentage = 5.0;
    stop_loss_percentage = -0.002; // Adjusted stop loss percentage
    target_capital = 50000;
    minimum_percentage = 0.005; // 5 points for minimum profit
    entry_price = 0;
    positions = 0;
    trading_day_start = TimeCurrent();
    target_reached_today = false; // Initialize flag
    days = 0; // Initialize day counter
    previous_day_balance = initial_balance; // Initialize previous day's balance
    start_of_day_balance = initial_balance; // Initialize start of day balance

    ArrayInitialize(profit_array, 0.0); // Initialize the profit array with zeros

    // Set timer to call OnTimer function every 60 seconds
    EventSetTimer(60);
    
    PrintFormat("Expert initialized with balance: %f and leverage: %f", initial_balance, leverage);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
    datetime current_time = TimeCurrent();
    MqlDateTime current_time_struct, trading_day_start_struct;
    TimeToStruct(current_time, current_time_struct);
    TimeToStruct(trading_day_start, trading_day_start_struct);

    // Check if it's a new day
    if (current_time_struct.day != trading_day_start_struct.day) {
        // Update the previous day's balance before resetting for the new day
        if (!is_first_day) {
            previous_day_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        } else {
            is_first_day = false;
        }

        trading_day_start = current_time;
        daily_profit = 0; // Reset daily profit
        target_reached_today = false; // Reset target reached flag
        days++;
        daily_trading_balance = initial_balance; // Reset daily trading balance to $100
        start_of_day_balance = AccountInfoDouble(ACCOUNT_BALANCE); // Set start of day balance to current account balance
        PrintFormat("New trading day started. Day: %d, Daily trading balance reset to: %f", days, daily_trading_balance);
    }
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
        features[i*10+0] = (rates[i].close - rates[i].open) / rates[i].open * 100.0;
        features[i*10+1] = (rates[i].high - rates[i].low) / rates[i].high * 100.0;
        features[i*10+2] = (i > 0) ? features[(i-1)*10+0] - features[i*10+0] : 0.0;
        features[i*10+3] = (i > 0 && features[i*10+2] > 0.01) ? 1.0 : 0.0;
        features[i*10+4] = (i < copied - 1) ? features[(i+1)*10+3] : 0.0;
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

    double profit = 0;
    if (order_ticket > 0 && PositionSelectByTicket(order_ticket)) {
        double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double volume = PositionGetDouble(POSITION_VOLUME);
        if (!OrderCalcProfit(ORDER_TYPE_BUY, "GBPUSD", volume, entry_price, current_price, profit)) {
            PrintFormat("Error calculating profit: %d", GetLastError());
            return;
        }
    }

    PrintFormat("Iteration at time %s, current price: %f, positions: %f, balance: %f, profit: %f, equity: %f, margin: %f, free margin: %f",
                TimeToString(date_time), current_price, positions, account_balance, profit, account_equity, account_margin, account_free_margin);
                
    // Update the profit array only if there is an active position
    if (positions > 0) {
        UpdateProfitArray(profit);
        // Print the profit array to observe its behavior
        PrintProfitArray();

        // Calculate the percentage drop in profit
        double significant_drop_threshold = 300.0; // Example threshold for significant drop in percentage
        double recent_profit = profit_array[14]; // Most recent profit
        double previous_profit = profit_array[13]; // Previous profit

        double percentage_drop = CalculatePercentageDrop(previous_profit, recent_profit);
        if (percentage_drop > significant_drop_threshold) {
            // Significant drop detected
            PrintFormat("Significant drop detected: %f%%", percentage_drop);

            // Close the current buy position and open a sell position
            if (order_ticket > 0 && PositionSelectByTicket(order_ticket)) {
                if (ClosePositionByTicket(order_ticket)) {
                    double volume = PositionGetDouble(POSITION_VOLUME); // Use the same volume as the closed buy position
                    current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID); // Get the current price for the sell position

                    // Check if there is enough margin for the sell position
                    if (CheckAndAdjustMargin(volume, current_price)) {
                        if (trade.Sell(volume, "GBPUSD", current_price, 0.0, 0.0, "Sell Market Order")) {
                            order_ticket = trade.ResultOrder();
                            short_position_time = TimeCurrent(); // Record the time when the short position is opened
                            PrintFormat("Entered short position at time %s, executed price: %f, volume: %f",
                                        TimeToString(TimeCurrent()), trade.ResultPrice(), volume);
                        } else {
                            Print("Failed to place Sell Market order");
                        }
                    } else {
                        Print("Not enough margin to open a short position, attempting to close existing positions");

                        // Attempt to close existing positions to free up margin
                        CloseAllPositions();

                        // Recalculate volume after closing positions
                        if (CheckAndAdjustMargin(volume, current_price)) {
                            if (trade.Sell(volume, "GBPUSD", current_price, 0.0, 0.0, "Sell Market Order")) {
                                order_ticket = trade.ResultOrder();
                                short_position_time = TimeCurrent(); // Record the time when the short position is opened
                                PrintFormat("Entered short position at time %s, executed price: %f, volume: %f",
                                            TimeToString(TimeCurrent()), trade.ResultPrice(), volume);
                            } else {
                                Print("Failed to place Sell Market order after closing positions");
                            }
                        } else {
                            Print("Not enough margin to open a short position after closing positions");
                        }
                    }
                } else {
                    Print("Failed to close current buy position");
                }
            }
        }
    }

    // Revert back to buy position based on stop loss or 1-hour timeout
    if (order_ticket > 0 && PositionSelectByTicket(order_ticket) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
        current_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID);
        datetime current_time = TimeCurrent();

        // Check if stop loss is hit or 1 hour has passed
        if (current_price >= initial_stop_loss_price || (current_time - short_position_time) >= 3600) {
            // Close the short position
            if (ClosePositionByTicket(order_ticket)) {
                PrintFormat("Closed short position at time %s, executed price: %f, volume: %f",
                            TimeToString(current_time), current_price, PositionGetDouble(POSITION_VOLUME));

                // Reopen a buy position
                double volume = PositionGetDouble(POSITION_VOLUME); // Use the same volume as the closed short position
                if (CheckAndAdjustMargin(volume, current_price)) {
                    if (trade.Buy(volume, "GBPUSD", current_price, 0.0, 0.0, "Buy Market Order")) {
                        order_ticket = trade.ResultOrder();
                        PrintFormat("Reverted to buy position at time %s, executed price: %f, volume: %f",
                                    TimeToString(current_time), trade.ResultPrice(), volume);
                    } else {
                        Print("Failed to place Buy Market order");
                    }
                } else {
                    Print("Not enough margin to revert to a buy position");
                }
            } else {
                Print("Failed to close short position");
            }
        }
    }

    // If target daily profit is reached, lock the previous day balance and stop trading
    if (daily_trading_balance >= target_capital) {
        PrintFormat("Target daily profit of %f reached at %s, stopping trading.", target_capital, TimeToString(date_time));
        previous_day_balance = account_balance; // Lock previous day balance based on account balance
        target_reached_today = true; // Set target reached flag
        return;
    }
    
    if (!target_reached_today && predicted_signals[0] == 1 && positions == 0) {
        // Recalculate volume based on daily trading balance
        double min_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MIN);
        double max_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MAX);
        double volume_step = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);

        double raw_volume = NormalizeDouble(leverage * ((daily_trading_balance - 4) / current_price), 2);
        double volume = NormalizeDouble(raw_volume / 100000.0, 2);  // Convert to X.XX format and round to 2 decimal places

        // Ensure the volume is within the allowed range
        volume = MathMax(volume, min_volume);
        volume = MathMin(volume, max_volume);

        double stop_loss_price = current_price * (1 + stop_loss_percentage); // Calculate stop loss by percentage
        initial_stop_loss_price = stop_loss_price;
        double take_profit_price = current_price * (1 + minimum_percentage); // Calculate take profit by percentage

        PrintFormat("Attempting to enter trade at %s: volume: %f, stop_loss: %f, take_profit: %f, equity: %f, margin: %f, free margin: %f",
                    TimeToString(date_time), volume, stop_loss_price, take_profit_price, account_equity, account_margin, account_free_margin);

        if (CheckAndAdjustMargin(volume, current_price)) {
            if (trade.Buy(volume, "GBPUSD", current_price, 0.0, 0.0, "Buy Market Order")) {
                entry_price = trade.ResultPrice(); // Capture the executed price
                positions = volume;
                order_ticket = trade.ResultOrder();
                PrintFormat("Entered position at time %s, executed price: %f, volume: %f, balance: %f, margin: %f, equity: %f, free margin: %f",
                            TimeToString(date_time), entry_price, volume, account_balance, account_margin, account_equity, account_free_margin);

                // Initialize the profit array on the first trade
                ArrayInitialize(profit_array, 0.0);
                UpdateProfitArray(profit); // Add the first profit value
                PrintProfitArray(); // Print the initialized profit array
            } else {
                positions = 0;
                Print("Failed to place Buy Market order");
            }
        } else {
            Print("Not enough margin to open a buy position");
        }
    }

    if (order_ticket > 0 && PositionSelectByTicket(order_ticket)) {
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

            account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            account_margin = AccountInfoDouble(ACCOUNT_MARGIN);
            account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

            PrintFormat("OnTick: current price: %f, entry price: %f, profit: %f, balance: %f, margin: %f, volume: %f, equity: %f, free margin: %f",
                        current_price, entry_price, profit, account_balance, margin, positions, account_equity, account_margin, account_free_margin);
                        
            // Calculate profit/loss as a percentage of entry price
            double profit_percentage = (profit / entry_price) * 100.0;

            // Check for stop loss condition
            if (current_price <= entry_price * (1 + stop_loss_percentage)) {
                if (ClosePositionByTicket(order_ticket)) {
                    
                    if (!OrderCalcProfit(ORDER_TYPE_BUY, "GBPUSD", positions, entry_price, close_price, profit)) {
                        PrintFormat("Error calculating profit on close: %d", GetLastError());
                        return;
                    }

                    PrintFormat("Stop loss triggered at time %s, close price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                                TimeToString(TimeCurrent()), close_price, profit, account_balance, positions, account_equity, account_margin, account_free_margin);

                    // Update balance after closing the position
                    account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
                    PrintFormat("Balance after stop loss closure: %f", account_balance);

                    double daily_profit = account_balance - start_of_day_balance;
                    daily_trading_balance = initial_balance + daily_profit; // Update correctly
                    PrintFormat("Daily trading balance after stop loss closure: %f", daily_trading_balance);

                    // Reset positions and entry price
                    positions = 0;
                    entry_price = 0;
                } else {
                    Print("Failed to close position at stop loss");
                }
            } else if (profit_percentage >= profit_cap_percentage || profit_percentage >= minimum_percentage) {
                if (ClosePositionByTicket(order_ticket)) {
                    double close_price = SymbolInfoDouble("GBPUSD", SYMBOL_BID); // Capture the actual close price
                    if (!OrderCalcProfit(ORDER_TYPE_BUY, "GBPUSD", positions, entry_price, close_price, profit)) {
                        PrintFormat("Error calculating profit on close: %d", GetLastError());
                        return;
                    }

                    PrintFormat("Take profit or minimum profit percentage reached at time %s, close price: %f, profit: %f, balance: %f, volume: %f, equity: %f, margin: %f, free margin: %f",
                                TimeToString(TimeCurrent()), close_price, profit, account_balance, positions, account_equity, account_margin, account_free_margin);

                    // Update balance after closing the position
                    account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
                    PrintFormat("Balance after take profit closure: %f", account_balance);

                    double daily_profit = account_balance - start_of_day_balance;
                    daily_trading_balance = initial_balance + daily_profit; // Update correctly
                    PrintFormat("Daily trading balance after take profit closure: %f", daily_trading_balance);

                    // Reset positions and entry price
                    positions = 0;
                    entry_price = 0;
                } else {
                    Print("Failed to close position at take profit");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Custom function to close position by ticket                      |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket) {
    if (!PositionSelectByTicket(ticket)) {
        PrintFormat("Position with ticket %d not found", ticket);
        return false;
    }

    // Get the position properties
    string symbol = PositionGetString(POSITION_SYMBOL);
    double volume = PositionGetDouble(POSITION_VOLUME);
    int type = PositionGetInteger(POSITION_TYPE);
    double close_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

    // Create a request structure to close the position
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = volume;
    request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY; // Close the opposite type
    request.position = ticket;
    request.price = close_price;
    request.deviation = 10; // Adjust as needed to handle slippage
    request.magic = 0;
    request.comment = "Position closed by ticket";
    request.type_filling = ORDER_FILLING_IOC; // Default to IOC, can try FOK if needed

    // Attempt to close the position
    if (OrderSend(request, result)) {
        if (result.retcode == TRADE_RETCODE_DONE) {
            double executed_price = result.price;
            PrintFormat("Position with ticket %d closed successfully at price %f", ticket, executed_price);
            return true;
        } else {
            PrintFormat("Failed to close position with ticket %d: %d", ticket, result.retcode);
            return false;
        }
    } else {
        PrintFormat("OrderSend failed for ticket %d: %d", ticket, GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Function to update the profit array                              |
//+------------------------------------------------------------------+
void UpdateProfitArray(double profit) {
    // Shift all elements to the left
    for (int i = 0; i < 14; i++) {
        profit_array[i] = profit_array[i + 1];
    }
    // Insert the new profit at the last index
    profit_array[14] = profit;
}

//+------------------------------------------------------------------+
//| Function to print the profit array                               |
//+------------------------------------------------------------------+
void PrintProfitArray() {
    string output = "Profit Array: ";
    for (int i = 0; i < 15; i++) {
        output += DoubleToString(profit_array[i], 2) + " ";
    }
    Print(output);
}

//+------------------------------------------------------------------+
//| Function to calculate the percentage drop                        |
//+------------------------------------------------------------------+
double CalculatePercentageDrop(double previous_profit, double current_profit) {
    if (previous_profit == 0) {
        return 0.0;
    }
    return ((previous_profit - current_profit) / MathAbs(previous_profit)) * 100.0;
}

//+------------------------------------------------------------------+
//| Function to check if there is enough free margin to open a new position
//+------------------------------------------------------------------+
bool CheckAndAdjustMargin(double &volume, double price) {
    double min_volume = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MIN);
    double volume_step = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);
    double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    double required_margin = (volume * price) / leverage;
    double account_free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);

    while (account_free_margin < required_margin && volume > min_volume) {
        volume = volume - volume_step;
        required_margin = (volume * price) / leverage;
    }

    return (volume >= min_volume);
}

//+------------------------------------------------------------------+
//| Function to close all open positions to free up margin           |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0) {
            ClosePositionByTicket(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
double mean(double &array[], int rows, int cols, int column) {
    if (rows == 0 || cols == 0) {
        Print("Array size is zero in mean function");
        return 0.0;
    }

    double sum = 0.0;
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
    double sum = 0.0;
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
        predicted_signals[i] = (features[i*10+3] == 1) ? 1.0 : 0.0;
    }

    return true;
}
