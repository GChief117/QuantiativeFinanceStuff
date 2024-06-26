#include <Trade\Trade.mqh>

CTrade trade;

// Global variables
double initial_balance;
double target_balance = 400;
double leverage = 200;
double risk_percentage = 0.01; // 1% risk per trade
double peak_equity = 0;
double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
double margin = AccountInfoDouble(ACCOUNT_MARGIN);
double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
double equity_at_buylimit;


// Resource for the ONNX model
#resource "forexmodel-2.onnx" as uchar ExtModel[];

// Initialization function
int OnInit()
{
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("Initial Balance: ", initial_balance);
    return INIT_SUCCEEDED;
}

// Main function called on every tick
void OnTick()
{

        double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double present_equity = AccountInfoDouble(ACCOUNT_EQUITY);

    if (current_balance >= target_balance)
    {
        Print("Target balance achieved. Stopping trading.");
        return;
    }

    double lot_size = CalculateLotSize(current_balance);
    double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double stop_loss = CalculateStopLoss(price);
    double take_profit = CalculateTakeProfit(price);

    if (ConditionsToBuy())
    {
        if (trade.BuyLimit(lot_size, price, "GBPUSD", stop_loss, take_profit, ORDER_TIME_GTC, 0, "BuyLimit Order"))
        {
            Print("Buy limit order placed successfully.");
            equity_at_buylimit = current_equity; // Capture equity at the time of BuyLimit
        }
        else
        {
            Print("Failed to place buy limit order. Error: ", GetLastError());
        }
    }
    
    // Compare current equity with the equity at the time of BuyLimit
    if (present_equity > equity_at_buylimit)
    {
        CloseAllTrades();
        equity_at_buylimit = 0; // Update equity after closing trades
    }
    

}

// Function to close all trades
void CloseAllTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (trade.PositionClose(ticket))
        {
            Print("Position closed successfully. Ticket: ", ticket);
        }
        else
        {
            Print("Failed to close position. Ticket: ", ticket, " Error: ", GetLastError());
        }
    }
}

// Function to calculate lot size
double CalculateLotSize(double balance)
{
    double risk_amount = balance * risk_percentage;
    double lot_size = (risk_amount / (100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)));
    lot_size = lot_size / 100000; // Convert to standard lots (e.g., 1,000 units = 0.01 lot)
    lot_size = NormalizeDouble(lot_size, 2);
    return lot_size;
}

// Function to calculate stop loss
double CalculateStopLoss(double price)
{
    double stop_loss = price - (50 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // 50 pips SL
    return NormalizeDouble(stop_loss, SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Function to calculate take profit
double CalculateTakeProfit(double price)
{
    double take_profit = price + (100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // 100 pips TP
    return NormalizeDouble(take_profit, SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Function to determine if conditions to buy are met
bool ConditionsToBuy()
{
    // Load and initialize the ONNX model
    long session_handle = OnnxCreateFromBuffer(ExtModel, ONNX_DEBUG_LOGS);
    if (session_handle == INVALID_HANDLE)
    {
        Print("Cannot create model. Error ", GetLastError());
        return false;
    }

    const long input_shape[] = {1, 500, 10}; // Confirmed input shape
    if (!OnnxSetInputShape(session_handle, 0, input_shape))
    {
        Print("OnnxSetInputShape error ", GetLastError());
        OnnxRelease(session_handle);
        return false;
    }

    const long output_shape[] = {1, 2}; // Confirmed output shape
    if (!OnnxSetOutputShape(session_handle, 0, output_shape))
    {
        Print("OnnxSetOutputShape error ", GetLastError());
        OnnxRelease(session_handle);
        return false;
    }

    // Fetch live data from the last 500 M30 periods
    MqlRates rates_array[500];
    if (CopyRates("GBPUSD", PERIOD_M30, 0, 500, rates_array) <= 0)
    {
        Print("Error copying rates: ", GetLastError());
        OnnxRelease(session_handle);
        return false;
    }

    // Feature engineering
    double Change_Open_Close[500];
    double Change_High_Low[500];
    double Profit_Between_Time_Series[500];
    double input_matrix[500][10];

    for (int i = 0; i < 500; i++)
    {
        Change_Open_Close[i] = ((rates_array[i].close - rates_array[i].open) / rates_array[i].open) * 100;
        Change_High_Low[i] = ((rates_array[i].high - rates_array[i].low) / rates_array[i].high) * 100;
        if (i > 0)
        {
            Profit_Between_Time_Series[i] = Change_Open_Close[i] - Change_Open_Close[i - 1];
        }
        else
        {
            Profit_Between_Time_Series[i] = 0;
        }

        input_matrix[i][0] = rates_array[i].open;
        input_matrix[i][1] = rates_array[i].high;
        input_matrix[i][2] = rates_array[i].low;
        input_matrix[i][3] = rates_array[i].close;
        input_matrix[i][4] = Change_Open_Close[i];
        input_matrix[i][5] = Change_High_Low[i];
        input_matrix[i][6] = Profit_Between_Time_Series[i];
        input_matrix[i][7] = 0; // Placeholder for additional features if needed
        input_matrix[i][8] = 0; // Placeholder for additional features if needed
        input_matrix[i][9] = 0; // Placeholder for additional features if needed
    }

    // Normalize features and prepare input tensor
    double input_data[500][10];
    double m[10], s[10];

    // Calculate mean and std for normalization
    for (int j = 0; j < 10; j++)
    {
        double sum = 0, sum_sq = 0;
        for (int i = 0; i < 500; i++)
        {
            sum += input_matrix[i][j];
            sum_sq += input_matrix[i][j] * input_matrix[i][j];
        }
        m[j] = sum / 500;
        s[j] = sqrt(sum_sq / 500 - m[j] * m[j]);
    }

    for (int i = 0; i < 500; i++)
    {
        for (int j = 0; j < 10; j++)
        {
            input_data[i][j] = (input_matrix[i][j] - m[j]) / s[j];
        }
    }

    // Convert input_data to the required format for ONNX model
    double input_data_reshaped[1][500][10];
    for (int i = 0; i < 500; i++)
    {
        for (int j = 0; j < 10; j++)
        {
            input_data_reshaped[0][i][j] = input_data[i][j];
        }
    }

    // Run the ONNX model
    double output_data[1][2]; // Adjusted to match the output shape
    if (!OnnxRun(session_handle, ONNX_DEBUG_LOGS, input_data_reshaped, output_data))
    {
        Print("OnnxRun error ", GetLastError());
        OnnxRelease(session_handle);
        return false;
    }

    // Extract the output logits
    double logit0 = output_data[0][0];
    double logit1 = output_data[0][1];

    // Compute the softmax probabilities
    double max_logit = MathMax(logit0, logit1);
    double exp_logit0 = MathExp(logit0 - max_logit);
    double exp_logit1 = MathExp(logit1 - max_logit);
    double sum_exp_logits = exp_logit0 + exp_logit1;
    double prob0 = exp_logit0 / sum_exp_logits;
    double prob1 = exp_logit1 / sum_exp_logits;

    // Print the softmax probabilities for debugging
    PrintFormat("Softmax probabilities: [%.6f, %.6f]", prob0, prob1);

    // Decide to buy based on the model's output
    bool buy_signal = (prob1 > prob0);

    // Release the model session
    OnnxRelease(session_handle);

    return buy_signal;
}
