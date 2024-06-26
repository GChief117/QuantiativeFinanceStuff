#resource "forexmodel-2.onnx" as uchar ExtModel[]// model as a resource
 
#define TESTS 10000  // number of test datasets
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
int OnStart()
  {
//--- create the model
   long session_handle=OnnxCreateFromBuffer(ExtModel,ONNX_DEBUG_LOGS);
   if(session_handle==INVALID_HANDLE)
     {
      Print("Cannot create model. Error ",GetLastError());
      return(-1);
     }
 
//--- since the input tensor size is not defined for the model, specify it explicitly
//--- first index is batch size, second index is series size, third index is number of series (OHLC)
   const long input_shape[]={1,10,10};
   if(!OnnxSetInputShape(session_handle,0,input_shape))
     {
      Print("OnnxSetInputShape error ",GetLastError());
      return(-2);
     }
 
//--- since the output tensor size is not defined for the model, specify it explicitly
//--- first index is batch size, must match the batch size in the input tensor
//--- second index is number of predicted prices (only Close is predicted here)
   const long output_shape[]={1,1};
   if(!OnnxSetOutputShape(session_handle,0,output_shape))
     {
      Print("OnnxSetOutputShape error ",GetLastError());
      return(-3);
     }
//--- run tests
   vector closes(TESTS);      // vector to store validation prices
   vector predicts(TESTS);    // vector to store obtained predictions
   vector prev_closes(TESTS); // vector to store preceding prices
 
   matrix rates;              // matrix to get the OHLC series
   matrix splitted[2];        // two submatrices to divide the series into test and validation
   ulong  parts[]={10,1};     // sizes of divided submatrices
 
//--- start from the previous bar
   for(int i=1; i<=TESTS; i++)
     {
      //--- get 11 bars
      rates.CopyRates("GBPUSD",PERIOD_H1,COPY_RATES_OHLC,i,11);
      //--- divide the matrix into test and validation
      rates.Vsplit(parts,splitted);
      //--- take the Close price from the validation matrix
      closes[i-1]=splitted[1][3][0];
      //--- last Close in the tested series
      prev_closes[i-1]=splitted[0][3][9];
 
      //--- submit the test matrix of 10 bars to testing
      predicts[i-1]=PricePredictionTest(session_handle,splitted[0]);
      //--- runtime error
      if(predicts[i-1]<=0)
        {
         OnnxRelease(session_handle);
         return(-4);
        }
     }
//--- complete operation
   OnnxRelease(session_handle);
//--- evaluate if price movement was predicted correctly
   int    right_directions=0;
   vector delta_predicts=prev_closes-predicts;
   vector delta_actuals=prev_closes-closes;
 
   for(int i=0; i<TESTS; i++)
      if((delta_predicts[i]>0 && delta_actuals[i]>0) || (delta_predicts[i]<0 && delta_actuals[i]<0))
         right_directions++;
   PrintFormat("right direction predictions = %.2f%%",(right_directions*100.0)/double(TESTS));
//--- 
   return(0);
  }
//+------------------------------------------------------------------+
//|  Prepare the data and run the model                              |
//+------------------------------------------------------------------+
double PricePredictionTest(const long session_handle,matrix& rates)
  {
   static matrixf input_data(10,4); // matrix for the transformed input
   static vectorf output_data(1);   // vector to receive the result
   static matrix mm(10,4);          // matrix of horizontal vectors Mean
   static matrix ms(10,4);          // matrix of horizontal vectors Std
 
//--- a set of OHLC vertical vectors must be input into the model
   matrix x_norm=rates.Transpose();
//--- normalize prices
   vector m=x_norm.Mean(0);
   vector s=x_norm.Std(0);
   for(int i=0; i<10; i++)
     {
      mm.Row(m,i);
      ms.Row(s,i);
     }
   x_norm-=mm;
   x_norm/=ms;
 
//--- run the model
   input_data.Assign(x_norm);
   if(!OnnxRun(session_handle,ONNX_DEBUG_LOGS,input_data,output_data))
     {
      Print("OnnxRun error ",GetLastError());
      return(0);
     }
//--- unnormalize the price from the output value
   double y_pred=output_data[0]*s[3]+m[3];
 
   return(y_pred);
  }