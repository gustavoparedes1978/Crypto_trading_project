import React, { useState } from 'react';

interface TradeFormProps {
  walletAddress: string | null;
}

const TradeForm: React.FC<TradeFormProps> = ({ walletAddress }) => {
  const [side, setSide] = useState<'buy' | 'sell'>('buy');
  const [amount, setAmount] = useState<number>(0);
  const [price, setPrice] = useState<number>(0);
  const [orderType, setOrderType] = useState<'limit' | 'market'>('limit');

  /**
   * @async
   * @function handleSubmit
   * @description Handles the submission of a trade order.
   * Validates input, constructs order data, and sends it to the backend API.
   * @param e - The form submission event.
   */
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); // Prevent default form submission behavior

    // Input validation
    if (!walletAddress) {
      // Replaced alert() with a user-friendly message for consistency
      console.error("Please connect your wallet first.");
      // Consider using a custom modal or state-based message instead of alert
      alert("Please connect your wallet first.");
      return;
    }
    
    if (amount <= 0) {
      // Replaced alert() with a user-friendly message for consistency
      console.error("Amount must be greater than zero.");
      // Consider using a custom modal or state-based message instead of alert
      alert("Amount must be greater than zero.");
      return;
    }

    if (orderType === 'limit' && price <= 0) {
      // Replaced alert() with a user-friendly message for consistency
      console.error("Limit orders must have a price greater than zero.");
      // Consider using a custom modal or state-based message instead of alert
      alert("Limit orders must have a price greater than zero.");
      return;
    }

    // Construct the order data payload
    const orderData = {
      user_id: walletAddress,
      pair: 'BTC-USD', // Hardcoded for simplicity, could be dynamic
      side,
      price: orderType === 'limit' ? price : null, // Price is null for market orders
      amount,
      order_type: orderType
    };

    try {
      // Send the order data to your backend API
      const response = await fetch('http://localhost:8000/api/v1/order', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(orderData),
      });

      if (response.ok) {
        // Order submitted successfully
        const result = await response.json();
        console.log('Order submitted successfully:', result);
        // Reset form fields after successful submission
        setAmount(0);
        setPrice(0);
        setOrderType('limit'); // Reset to default
        alert("Order submitted successfully!"); // User feedback
      } else {
        // Handle API errors
        const error = await response.json();
        console.error('Failed to submit order:', error);
        // Corrected syntax: enclosed the string in quotes
        alert(`Failed to submit order: ${error.detail || JSON.stringify(error)}`);
      }
    } catch (error) {
      // Handle network or other unexpected errors
      console.error('Error submitting order:', error);
      // Ensure error is properly converted to a string for display
      alert(`An unexpected error occurred: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl border border-gray-700">
      <h2 className="text-2xl font-semibold mb-4 text-center text-gray-200">Place Order</h2>
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Buy/Sell Side Selection */}
        <div className="flex justify-around bg-gray-700 p-1 rounded-lg">
          <button
            type="button"
            onClick={() => setSide('buy')}
            className={`flex-1 py-2 rounded-md transition-colors duration-200 ${
              side === 'buy' ? 'bg-green-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
          >
            Buy
          </button>
          <button
            type="button"
            onClick={() => setSide('sell')}
            className={`flex-1 py-2 rounded-md transition-colors duration-200 ${
              side === 'sell' ? 'bg-red-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
          >
            Sell
          </button>
        </div>

        {/* Order Type Selection */}
        <div className="flex justify-around bg-gray-700 p-1 rounded-lg">
          <button
            type="button"
            onClick={() => setOrderType('limit')}
            className={`flex-1 py-2 rounded-md transition-colors duration-200 ${
              orderType === 'limit' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
          >
            Limit Order
          </button>
          <button
            type="button"
            onClick={() => setOrderType('market')}
            className={`flex-1 py-2 rounded-md transition-colors duration-200 ${
              orderType === 'market' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
          >
            Market Order
          </button>
        </div>

        {/* Amount Input */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-1">Amount (BTC)</label>
          <input
            type="number"
            value={amount === 0 ? '' : amount}
            onChange={(e) => setAmount(Number(e.target.value))}
            className="w-full p-3 rounded-lg bg-gray-700 border border-gray-600 text-gray-100 focus:ring-blue-500 focus:border-blue-500 placeholder-gray-400"
            step="any"
            required
            placeholder="e.g., 0.001"
          />
        </div>
        
        {/* Price Input (only for Limit Orders) */}
        {orderType === 'limit' && (
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-1">Price (USD)</label>
            <input
              type="number"
              value={price === 0 ? '' : price}
              onChange={(e) => setPrice(Number(e.target.value))}
              className="w-full p-3 rounded-lg bg-gray-700 border border-gray-600 text-gray-100 focus:ring-blue-500 focus:border-blue-500 placeholder-gray-400"
              step="any"
              required={orderType === 'limit'}
              placeholder="e.g., 60000.00"
            />
          </div>
        )}
        
        {/* Submit Button */}
        <button
          type="submit"
          disabled={!walletAddress || amount <= 0 || (orderType === 'limit' && price <= 0)}
          className={`w-full py-3 rounded-lg font-bold text-white transition duration-300 ease-in-out transform hover:scale-105 ${
            !walletAddress || amount <= 0 || (orderType === 'limit' && price <= 0)
              ? 'bg-gray-600 cursor-not-allowed'
              : 'bg-gradient-to-r from-blue-600 to-cyan-600 hover:from-blue-700 hover:to-cyan-700 shadow-lg'
          }`}
        >
          {side === 'buy' ? 'Place Buy Order' : 'Place Sell Order'}
        </button>
      </form>
    </div>
  );
};

export default TradeForm;
