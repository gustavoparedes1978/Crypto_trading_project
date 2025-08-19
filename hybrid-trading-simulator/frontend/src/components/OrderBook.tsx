import React from 'react';

interface OrderBookProps {
  orderBook: { bids: { price: number; amount: number }[]; asks: { price: number; amount: number }[] } | null;
}

const OrderBook: React.FC<OrderBookProps> = ({ orderBook }) => {
  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl border border-gray-700">
      <h2 className="text-2xl font-semibold mb-4 text-center text-gray-200">Order Book (BTC-USD)</h2>
      
      <div className="mb-6">
        <h3 className="text-xl font-medium text-red-400 mb-2">Asks (Sell Orders)</h3>
        <div className="flex justify-between font-mono text-xs text-gray-400 border-b border-gray-600 pb-1 mb-1">
          <span>Price (USD)</span>
          <span>Amount (BTC)</span>
        </div>
        <div className="space-y-1 max-h-48 overflow-y-auto custom-scrollbar">
          {orderBook?.asks.length === 0 && <p className="text-gray-500 text-center py-4">No sell orders.</p>}
          {orderBook?.asks.slice(0, 10).map((order, index) => (
            <div key={index} className="flex justify-between text-red-300 text-sm bg-gray-700 p-2 rounded-md hover:bg-gray-600 transition-colors duration-200">
              <span>{order.price.toFixed(2)}</span>
              <span>{order.amount.toFixed(4)}</span>
            </div>
          ))}
        </div>
      </div>

      <hr className="my-6 border-gray-600" />

      <div>
        <h3 className="text-xl font-medium text-green-400 mb-2">Bids (Buy Orders)</h3>
        <div className="flex justify-between font-mono text-xs text-gray-400 border-b border-gray-600 pb-1 mb-1">
          <span>Price (USD)</span>
          <span>Amount (BTC)</span>
        </div>
        <div className="space-y-1 max-h-48 overflow-y-auto custom-scrollbar">
          {orderBook?.bids.length === 0 && <p className="text-gray-500 text-center py-4">No buy orders.</p>}
          {orderBook?.bids.slice(0, 10).map((order, index) => (
            <div key={index} className="flex justify-between text-green-300 text-sm bg-gray-700 p-2 rounded-md hover:bg-gray-600 transition-colors duration-200">
              <span>{order.price.toFixed(2)}</span>
              <span>{order.amount.toFixed(4)}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default OrderBook;
