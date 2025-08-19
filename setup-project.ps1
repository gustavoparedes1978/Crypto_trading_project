# Define the root project directory name
$projectRoot = "hybrid-trading-simulator"

# --- 1. Create Main Project Directory Structure ---
Write-Host "Creating project directory structure..."
New-Item -Path . -Name $projectRoot -ItemType Directory -Force
Set-Location -Path $projectRoot

New-Item -Path "backend" -ItemType Directory -Force
New-Item -Path "backend/app" -ItemType Directory -Force
New-Item -Path "frontend" -ItemType Directory -Force
New-Item -Path "frontend/src" -ItemType Directory -Force
New-Item -Path "frontend/src/components" -ItemType Directory -Force
New-Item -Path "blockchain" -ItemType Directory -Force
New-Item -Path "blockchain/contracts" -ItemType Directory -Force
New-Item -Path "blockchain/scripts" -ItemType Directory -Force

Write-Host "Project structure created."

# --- 2. Backend Setup (FastAPI, Python) ---
Write-Host "Setting up backend..."
Set-Location -Path "backend"

Write-Host "Creating Python virtual environment..."
# Check if python3.11 is available, otherwise use python
try {
    python3.11 -m venv venv -ErrorAction Stop
} catch {
    Write-Warning "python3.11 not found, trying 'python' instead. Ensure Python 3.x is installed and in PATH."
    python -m venv venv
}

Write-Host "Activating virtual environment and installing dependencies..."
# Activation script path for PowerShell
$venvActivatePath = ".\venv\Scripts\Activate.ps1"
if (Test-Path $venvActivatePath) {
    & $venvActivatePath
} else {
    Write-Warning "Virtual environment activation script not found at $venvActivatePath. Please activate manually if issues arise."
}

# backend/requirements.txt
@"
fastapi
uvicorn
gunicorn
python-binance
motor
aio-pika
web3
pydantic
python-dotenv
"# | Set-Content -Path "requirements.txt"

pip install -r requirements.txt
Write-Host "Backend dependencies installed."

# backend/Dockerfile
@"
# Stage 1: Build dependencies
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Final image
FROM python:3.11-slim
WORKDIR /app

# Copy dependencies from builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy the application code
COPY ./app /app/app

# Expose the port for the API
EXPOSE 8000

# Command to run the API service with Gunicorn
CMD ["gunicorn", "app.api:app", "--workers", "4", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000"]
"@ | Set-Content -Path "Dockerfile"

# backend/app/dependencies.py
@"
import os
import motor.motor_asyncio
import aio_pika

# Load environment variables
from dotenv import load_dotenv
load_dotenv()

# MongoDB Connection
MONGO_URI = os.getenv("MONGODB_URI")
if not MONGO_URI:
    raise ValueError("MONGODB_URI environment variable not set.")
client = motor.motor_asyncio.AsyncIOMotorClient(MONGO_URI)
db = client.trading_simulator

# RabbitMQ Connection
RABBITMQ_URI = os.getenv("RABBITMQ_URI")
if not RABBITMQ_URI:
    raise ValueError("RABBITMQ_URI environment variable not set.")
queue_name = "trade_settlement_queue"

async def get_rabbitmq_channel():
    connection = await aio_pika.connect_robust(RABBITMQ_URI)
    channel = await connection.channel()
    await channel.declare_queue(queue_name, durable=True)
    return channel
"@ | Set-Content -Path "app/dependencies.py"

# backend/app/matching_engine.py
@"
import uuid
import heapq
import json
from datetime import datetime
from typing import Optional, Dict, List
from pydantic import BaseModel
from .dependencies import db, get_rabbitmq_channel, queue_name
import asyncio # Import asyncio for Future

class Order(BaseModel):
    user_id: str
    order_id: str = str(uuid.uuid4())
    pair: str
    side: str  # 'buy' or 'sell'
    price: Optional[float]
    amount: float
    timestamp: datetime = datetime.now()
    order_type: str  # 'limit' or 'market'

class MatchedTrade(BaseModel):
    trade_id: str
    buyer_order_id: str
    seller_order_id: str
    price: float
    amount: float
    timestamp: datetime = datetime.now()

class OrderBook:
    def __init__(self, pair: str):
        self.pair = pair
        self.asks = []  # min-heap: (price, timestamp, order)
        self.bids = []  # max-heap: (-price, timestamp, order)
        # Store orders by their ID for quick lookup and modification
        self.active_orders: Dict[str, Order] = {}

    async def add_order(self, order: Order):
        self.active_orders[order.order_id] = order
        if order.side == 'buy':
            heapq.heappush(self.bids, (-order.price, order.timestamp, order.order_id)) # Store order_id
        else:
            heapq.heappush(self.asks, (order.price, order.timestamp, order.order_id)) # Store order_id
        await self._match_orders()

    async def _match_orders(self):
        while self.bids and self.asks:
            best_bid_tuple = self.bids[0]
            best_ask_tuple = self.asks[0]

            buy_order_id = best_bid_tuple[2]
            sell_order_id = best_ask_tuple[2]

            buy_order = self.active_orders.get(buy_order_id)
            sell_order = self.active_orders.get(sell_order_id)

            # Check if orders still exist and have positive amount
            if not buy_order or buy_order.amount <= 0:
                heapq.heappop(self.bids)
                continue
            if not sell_order or sell_order.amount <= 0:
                heapq.heappop(self.asks)
                continue

            bid_price = -best_bid_tuple[0]
            ask_price = best_ask_tuple[0]

            if bid_price >= ask_price:
                fill_amount = min(buy_order.amount, sell_order.amount)
                
                # Execute at the price of the oldest order for price-time priority
                execution_price = ask_price if best_ask_tuple[1] < best_bid_tuple[1] else bid_price

                trade_id = str(uuid.uuid4())
                trade_message = {
                    "trade_id": trade_id,
                    "buyer_order_id": buy_order.order_id,
                    "seller_order_id": sell_order.order_id,
                    "price": execution_price,
                    "amount": fill_amount,
                    "buyer_user_id": buy_order.user_id, # Include user IDs for settlement
                    "seller_user_id": sell_order.user_id,
                    "pair": self.pair,
                    "timestamp": datetime.now().isoformat()
                }
                
                try:
                    channel = await get_rabbitmq_channel()
                    await channel.default_exchange.publish(
                        aio_pika.Message(body=json.dumps(trade_message).encode(), delivery_mode=aio_pika.DeliveryMode.PERSISTENT),
                        routing_key=queue_name,
                    )
                except Exception as e:
                    print(f"Failed to publish to RabbitMQ: {e}")
                
                buy_order.amount -= fill_amount
                sell_order.amount -= fill_amount

                if buy_order.amount <= 0:
                    heapq.heappop(self.bids)
                    del self.active_orders[buy_order_id]
                if sell_order.amount <= 0:
                    heapq.heappop(self.asks)
                    del self.active_orders[sell_order_id]

                # Store trade in MongoDB
                await db.trades.insert_one(trade_message)
            else:
                break
    
    async def get_order_book_data(self):
        # Reconstruct bids and asks lists from active orders to ensure up-to-date amounts
        current_bids = sorted([self.active_orders[order_id] for _, _, order_id in self.bids if order_id in self.active_orders and self.active_orders[order_id].amount > 0], key=lambda x: x.price, reverse=True)
        current_asks = sorted([self.active_orders[order_id] for _, _, order_id in self.asks if order_id in self.active_orders and self.active_orders[order_id].amount > 0], key=lambda x: x.price)
        
        bids_data = [{"price": o.price, "amount": o.amount} for o in current_bids]
        asks_data = [{"price": o.price, "amount": o.amount} for o in current_asks]
        return {"bids": bids_data, "asks": asks_data}

order_books: Dict[str, OrderBook] = {"BTC-USD": OrderBook("BTC-USD")}

"@ | Set-Content -Path "app/matching_engine.py"

# backend/app/api.py
@"
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List
from .dependencies import db, get_rabbitmq_channel
from .matching_engine import Order, order_books
# from binance import AsyncWebsocketStreamManager # Uncomment if you want live Binance data

app = FastAPI()

# CORS configuration for frontend
origins = [
    "http://localhost:3000",  # React app development server
    "http://127.0.0.1:3000",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

active_connections: Dict[str, WebSocket] = {}

# Pydantic model for order book response
class OrderBookData(BaseModel):
    bids: List[Dict[str, float]]
    asks: List[Dict[str, float]]

# API Endpoints
@app.post("/api/v1/order")
async def place_order(order: Order):
    # TODO: Add more robust user authentication and balance checks here
    order_book = order_books.get(order.pair)
    if not order_book:
        return {"error": "Invalid trading pair"}, 400
    
    # Simple validation for market orders
    if order.order_type == 'market' and order.price is not None:
        return {"error": "Market orders should not specify a price"}, 400
    if order.order_type == 'limit' and order.price is None:
        return {"error": "Limit orders must specify a price"}, 400

    await order_book.add_order(order)
    return {"message": "Order submitted successfully", "order_id": order.order_id}

@app.get("/api/v1/orderbook/{pair}", response_model=OrderBookData)
async def get_order_book_endpoint(pair: str):
    order_book = order_books.get(pair)
    if not order_book:
        return {"bids": [], "asks": []}
    
    return await order_book.get_order_book_data()

# Real-time WebSocket endpoint for market data updates
@app.websocket("/ws/marketdata")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    client_key = f"{websocket.client.host}:{websocket.client.port}"
    active_connections[client_key] = websocket
    print(f"Client {client_key} connected to WebSocket.")
    try:
        while True:
            # Continuously send order book updates to this specific client
            order_book_data = await get_order_book_endpoint(pair="BTC-USD") # Always fetch for BTC-USD for now
            try:
                await websocket.send_json({"type": "orderbook_update", "data": order_book_data.dict()})
            except RuntimeError as e:
                # Handle cases where connection might be closing or already closed
                print(f"Error sending to WebSocket {client_key}: {e}")
                break
            await asyncio.sleep(1) # Send updates every second
    except WebSocketDisconnect:
        del active_connections[client_key]
        print(f"Client {client_key} disconnected from WebSocket.")
    except Exception as e:
        print(f"Unexpected error in WebSocket {client_key}: {e}")
        del active_connections[client_key]

# Optional: Binance live data stream integration (requires valid API keys)
# async def binance_live_stream():
#     # You would use your actual API Key and Secret from .env here
#     # bm = AsyncWebsocketStreamManager(api_key=os.getenv("BINANCE_API_KEY"), api_secret=os.getenv("BINANCE_SECRET"))
#     # async with bm as bsm:
#     #     # Example: Stream ticker data for BTCUSDT
#     #     def handle_ticker_message(msg):
#     #         if msg and 'c' in msg and 's' in msg:
#     #             print(f"Live Binance Ticker: {msg['s']} Last Price: {msg['c']}")
#     #             # You could update an in-memory price, or push this to another queue
#     #     await bsm.start_symbol_ticker_socket(symbol='BTCUSDT', callback=handle_ticker_message)
#     #     await asyncio.Future() # Keep the task alive indefinitely
#     print("Binance stream placeholder running...")
#     while True:
#         await asyncio.sleep(5) # Simulate activity

# @app.on_event("startup")
# async def startup_event():
#     # Uncomment to enable Binance stream
#     # asyncio.create_task(binance_live_stream())
#     pass
"@ | Set-Content -Path "app/api.py"

# backend/app/consumer.py
@"
import os
import asyncio
import json
from web3 import Web3, HTTPProvider
import aio_pika
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Web3 and Contract Setup
ETH_TESTNET_URL = os.getenv("ETH_TESTNET_URL")
SETTLEMENT_CONTRACT_ADDRESS = os.getenv("SETTLEMENT_CONTRACT_ADDRESS")
SETTLEMENT_CONTRACT_ABI_STR = os.getenv("SETTLEMENT_CONTRACT_ABI")
RABBITMQ_URI = os.getenv("RABBITMQ_URI")
QUEUE_NAME = "trade_settlement_queue"

if not all([ETH_TESTNET_URL, SETTLEMENT_CONTRACT_ADDRESS, SETTLEMENT_CONTRACT_ABI_STR, RABBITMQ_URI]):
    print("Missing one or more required environment variables for consumer. Exiting.")
    exit(1)

w3 = Web3(HTTPProvider(ETH_TESTNET_URL))
try:
    SETTLEMENT_CONTRACT_ABI = json.loads(SETTLEMENT_CONTRACT_ABI_STR)
except json.JSONDecodeError:
    print("Error parsing SETTLEMENT_CONTRACT_ABI. Ensure it's valid JSON.")
    exit(1)

settlement_contract = w3.eth.contract(address=SETTLEMENT_CONTRACT_ADDRESS, abi=SETTLEMENT_CONTRACT_ABI)

# Import MongoDB dependencies from backend.app.dependencies if needed
# from .dependencies import db # if the consumer needs direct DB access beyond what's received in trade_data

async def on_message(message: aio_pika.IncomingMessage):
    async with message.process():
        try:
            trade_data = json.loads(message.body.decode())
            print(f"Received trade for settlement: {trade_data}")

            trade_id = trade_data.get("trade_id")
            buyer_address = trade_data.get("buyer_user_id")
            seller_address = trade_data.get("seller_user_id")
            price = int(trade_data.get("price") * (10**18)) # Adjust for token decimals, assuming 18 for simplicity
            amount = int(trade_data.get("amount") * (10**18)) # Adjust for token decimals

            # IMPORTANT: In a true non-custodial system, the signed transaction
            # would be received from the frontend or a separate signing service.
            # This is a placeholder for demonstration purposes.
            # You would likely have an admin account for the settlement contract itself
            # or expect pre-approved transfers.

            # For a real system, the frontend would pass the signed transaction
            # and this worker would only broadcast it.
            # signed_transaction = trade_data.get("signed_transaction")
            # tx_hash = w3.eth.send_raw_transaction(signed_transaction)

            # --- Mocking on-chain settlement for demonstration ---
            # This assumes the settlement worker has the private key for the contract owner
            # or a designated signer account, which is a departure from pure non-custodial
            # but common for automated settlement layers. For full non-custodial, the user
            # must sign the settlement transaction themselves and this worker would just broadcast it.

            # Mock successful transaction
            tx_hash = f"0x{os.urandom(32).hex()}" # Generate a mock transaction hash
            print(f"Simulated on-chain transaction with hash: {tx_hash} for trade {trade_id}")

            # Example: Update status in MongoDB (assuming `db` is accessible or passed)
            # This part would require the `db` object from `dependencies.py`
            # For this standalone consumer, we'll just print.
            # In a real app, you'd use a shared database or another message for updates.
            # from backend.app.dependencies import db # Uncomment and use if direct DB access is desired
            # await db.trades.update_one(
            #     {"trade_id": trade_id},
            #     {"$set": {"transaction_hash": tx_hash, "status": "settled_on_chain"}}
            # )
            print(f"Trade {trade_id} marked as settled (simulated) with TX: {tx_hash}")

        except Exception as e:
            print(f"Error processing message or during on-chain settlement: {e}")
            # Optionally re-queue the message for retry after a delay
            # await message.nack() # This will put the message back to the queue
            
async def start_consumer():
    connection = await aio_pika.connect_robust(RABBITMQ_URI)
    channel = await connection.channel()
    
    await channel.set_qos(prefetch_count=1) # Only process one message at a time per worker
    
    queue = await channel.declare_queue(QUEUE_NAME, durable=True)
    await queue.consume(on_message)
    
    print("Settlement worker started. Waiting for messages...")
    await asyncio.Future() # Keep the consumer running indefinitely

if __name__ == "__main__":
    asyncio.run(start_consumer())
"@ | Set-Content -Path "app/consumer.py"

Write-Host "Backend files created."
Set-Location -Path ".." # Back to project root

# --- 3. Frontend Setup (React, TypeScript) ---
Write-Host "Setting up frontend..."
Set-Location -Path "frontend"

# Check if npx and npm are available
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Error "npx is not found. Please ensure Node.js and npm are installed and in your PATH."
    exit 1
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "npm is not found. Please ensure Node.js and npm are installed and in your PATH."
    exit 1
}

# Create React app
npx create-react-app . --template typescript --use-npm --force # --force to overwrite if dir not empty

npm install redux toolkit react-redux tailwindcss ethers

# Configure Tailwind CSS
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# frontend/tailwind.config.js
@"
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {},
  },
  plugins: [],
}
"@ | Set-Content -Path "tailwind.config.js"

# frontend/src/main.tsx (assuming React 18+)
@"
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css'; // Your main CSS file for Tailwind output

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
"@ | Set-Content -Path "src/main.tsx"

# frontend/src/App.tsx
@"
import React, { useState, useEffect } from 'react';
import { ethers, JsonRpcProvider } from 'ethers';
import OrderBook from './components/OrderBook';
import TradeForm from './components/TradeForm';

interface OrderBookData {
  bids: { price: number; amount: number }[];
  asks: { price: number; amount: number }[];
}

declare global {
  interface Window {
    ethereum?: any;
  }
}

const App: React.FC = () => {
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [orderBook, setOrderBook] = useState<OrderBookData | null>(null);

  const connectWallet = async () => {
    if (window.ethereum) {
      try {
        const provider = new ethers.BrowserProvider(window.ethereum);
        const signer = await provider.getSigner();
        const address = await signer.getAddress();
        setWalletAddress(address);
        console.log("Connected to wallet:", address);
      } catch (error) {
        console.error("Failed to connect wallet:", error);
        alert("Failed to connect MetaMask. Please ensure it's installed and unlocked.");
      }
    } else {
      alert("MetaMask is not detected. Please install it to connect your wallet.");
    }
  };

  useEffect(() => {
    // Check for existing MetaMask connection on load
    if (window.ethereum) {
      const provider = new ethers.BrowserProvider(window.ethereum);
      provider.listAccounts().then(accounts => {
        if (accounts.length > 0) {
          setWalletAddress(accounts[0].address);
          console.log("Already connected to wallet:", accounts[0].address);
        }
      });

      // Listen for account changes
      window.ethereum.on('accountsChanged', (accounts: string[]) => {
        if (accounts.length > 0) {
          setWalletAddress(accounts[0]);
          console.log("Wallet account changed to:", accounts[0]);
        } else {
          setWalletAddress(null);
          console.log("Wallet disconnected.");
        }
      });

      // Listen for network changes
      window.ethereum.on('chainChanged', (chainId: string) => {
        console.log("Network changed to:", chainId);
        // You might want to reload or re-initialize providers here
      });
    }

    const ws = new WebSocket('ws://localhost:8000/ws/marketdata');

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'orderbook_update') {
        setOrderBook(data.data);
      }
    };

    ws.onclose = () => console.log('WebSocket connection closed.');
    ws.onerror = (error) => console.error('WebSocket error:', error);

    return () => {
      ws.close();
      // Clean up event listeners
      if (window.ethereum) {
        window.ethereum.removeListener('accountsChanged', () => {});
        window.ethereum.removeListener('chainChanged', () => {});
      }
    };
  }, []);

  return (
    <div className="bg-gray-900 text-white min-h-screen p-8 font-inter">
      <header className="flex justify-between items-center mb-8 pb-4 border-b border-gray-700">
        <h1 className="text-3xl font-extrabold text-blue-400">Hybrid Trading Simulator</h1>
        <button
          onClick={connectWallet}
          className="bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-700 hover:to-indigo-700 text-white font-bold py-2 px-4 rounded-xl shadow-lg transition duration-300 ease-in-out transform hover:scale-105"
        >
          {walletAddress ? `Connected: ${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}` : 'Connect Wallet'}
        </button>
      </header>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <OrderBook orderBook={orderBook} />
        <TradeForm walletAddress={walletAddress} />
      </div>

      <footer className="mt-12 text-center text-gray-500 text-sm">
        <p>&copy; 2025 Hybrid Trading Simulator. All rights reserved.</p>
        <p>Disclaimer: This is a simulation for educational purposes only and does not involve real funds.</p>
      </footer>
    </div>
  );
};

export default App;
"@ | Set-Content -Path "src/App.tsx"

# frontend/src/components/OrderBook.tsx
@"
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
"@ | Set-Content -Path "src/components/OrderBook.tsx"

# frontend/src/components/TradeForm.tsx
@"
import React, { useState } from 'react';

interface TradeFormProps {
  walletAddress: string | null;
}

const TradeForm: React.FC<TradeFormProps> = ({ walletAddress }) => {
  const [side, setSide] = useState<'buy' | 'sell'>('buy');
  const [amount, setAmount] = useState<number>(0);
  const [price, setPrice] = useState<number>(0);
  const [orderType, setOrderType] = useState<'limit' | 'market'>('limit');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!walletAddress) {
      alert("Please connect your wallet first.");
      return;
    }
    
    if (amount <= 0) {
      alert("Amount must be greater than zero.");
      return;
    }

    if (orderType === 'limit' && price <= 0) {
      alert("Limit orders must have a price greater than zero.");
      return;
    }

    const orderData = {
      user_id: walletAddress,
      pair: 'BTC-USD',
      side,
      price: orderType === 'limit' ? price : null,
      amount,
      order_type: orderType
    };

    try {
      const response = await fetch('http://localhost:8000/api/v1/order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(orderData),
      });

      if (response.ok) {
        alert("Order submitted successfully! Check the order book for updates.");
        setAmount(0);
        setPrice(0);
      } else {
        const error = await response.json();
        alert(`Failed to submit order: ${error.detail || error.message || JSON.stringify(error)}`);
      }
    } catch (error) {
      console.error("Submission error:", error);
      alert("An error occurred. Please ensure the backend is running and accessible.");
    }
  };

  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl border border-gray-700">
      <h2 className="text-2xl font-semibold mb-4 text-center text-gray-200">Place Order</h2>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-1">Order Type</label>
          <div className="flex space-x-4 mb-3">
            <button
              type="button"
              onClick={() => setOrderType('limit')}
              className={`flex-1 py-2 px-4 rounded-lg transition-colors duration-200 ${orderType === 'limit' ? 'bg-blue-600 text-white shadow-md' : 'bg-gray-600 text-gray-300 hover:bg-gray-500'}`}
            >
              Limit
            </button>
            <button
              type="button"
              onClick={() => { setOrderType('market'); setPrice(0); }}
              className={`flex-1 py-2 px-4 rounded-lg transition-colors duration-200 ${orderType === 'market' ? 'bg-blue-600 text-white shadow-md' : 'bg-gray-600 text-gray-300 hover:bg-gray-500'}`}
            >
              Market
            </button>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-1">Side</label>
          <div className="flex space-x-4">
            <button
              type="button"
              onClick={() => setSide('buy')}
              className={`flex-1 py-2 px-4 rounded-lg transition-colors duration-200 ${side === 'buy' ? 'bg-green-600 text-white shadow-md' : 'bg-gray-600 text-gray-300 hover:bg-gray-500'}`}
            >
              Buy
            </button>
            <button
              type="button"
              onClick={() => setSide('sell')}
              className={`flex-1 py-2 px-4 rounded-lg transition-colors duration-200 ${side === 'sell' ? 'bg-red-600 text-white shadow-md' : 'bg-gray-600 text-gray-300 hover:bg-gray-500'}`}
            >
              Sell
            </button>
          </div>
        </div>
        
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
        
        <button
          type="submit"
          disabled={!walletAddress || amount <= 0 || (orderType === 'limit' && price <= 0)}
          className={`w-full py-3 rounded-lg font-bold text-white shadow-lg transition duration-300 ease-in-out transform hover:scale-105 
            ${side === 'buy' ? 'bg-gradient-to-r from-green-500 to-green-700 hover:from-green-600 hover:to-green-800' : 'bg-gradient-to-r from-red-500 to-red-700 hover:from-red-600 hover:to-red-800'}
            disabled:opacity-50 disabled:cursor-not-allowed`}
        >
          Submit {side === 'buy' ? 'Buy' : 'Sell'} Order
        </button>
      </form>
    </div>
  );
};

export default TradeForm;
"@ | Set-Content -Path "src/components/TradeForm.tsx"

Write-Host "Frontend files created."
Set-Location -Path ".." # Back to project root

# --- 4. Blockchain Setup (Solidity, Hardhat) ---
Write-Host "Setting up blockchain project..."
Set-Location -Path "blockchain"

# Initialize Hardhat
npm init -y
npm install hardhat @nomicfoundation/hardhat-toolbox

# Overwrite default hardhat.config.js and create contracts/Settlement.sol and scripts/deploy.js
# hardhat.config.js
@"
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    sepolia: {
      url: process.env.ETH_TESTNET_URL || "",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
"@ | Set-Content -Path "hardhat.config.js"

# blockchain/contracts/Settlement.sol
@"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// A mock ERC20 token for simulation
contract MockERC20 is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address initialOwner) ERC20(name, symbol) Ownable(initialOwner) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract Settlement is Ownable {
    mapping(string => bool) private settledTrades;
    MockERC20 public tokenA; // e.g., USDT
    MockERC20 public tokenB; // e.g., WBTC

    event TradeSettled(string tradeId, address indexed buyer, address indexed seller, uint256 price, uint256 amount);

    constructor(address initialOwner, MockERC20 _tokenA, MockERC20 _tokenB) Ownable(initialOwner) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // Function to settle a trade on-chain
    // This function assumes `buyer` has approved `tokenA` for `this` contract,
    // and `seller` has approved `tokenB` for `this` contract.
    function settleTrade(string memory tradeId, address buyer, address seller, uint256 price, uint256 amount) public onlyOwner {
        require(!settledTrades[tradeId], "Trade already settled");
        require(price > 0 && amount > 0, "Price and amount must be positive");

        uint256 valueUSD = price * amount; // Assuming price is in tokenA units (e.g., USD)

        // Transfer tokenA (e.g., USDT) from buyer to seller
        tokenA.transferFrom(buyer, seller, valueUSD);

        // Transfer tokenB (e.g., WBTC) from seller to buyer
        tokenB.transferFrom(seller, buyer, amount);

        settledTrades[tradeId] = true;
        emit TradeSettled(tradeId, buyer, seller, price, amount);
    }
}
"@ | Set-Content -Path "contracts/Settlement.sol"

# blockchain/scripts/deploy.js
@"
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy MockERC20 tokens
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");

  const usdt = await MockERC20.deploy("Tether USD", "USDT", deployer.address);
  await usdt.waitForDeployment();
  console.log("USDT deployed to:", usdt.target);

  const wbtc = await MockERC20.deploy("Wrapped BTC", "WBTC", deployer.address);
  await wbtc.waitForDeployment();
  console.log("WBTC deployed to:", wbtc.target);

  // Deploy Settlement contract
  const Settlement = await hre.ethers.getContractFactory("Settlement");
  const settlement = await Settlement.deploy(deployer.address, usdt.target, wbtc.target);
  await settlement.waitForDeployment();
  console.log("Settlement deployed to:", settlement.target);

  // Optional: Mint some tokens to the deployer or other test accounts
  await usdt.mint(deployer.address, hre.ethers.parseUnits("1000000", 18)); // 1,000,000 USDT
  await wbtc.mint(deployer.address, hre.ethers.parseUnits("10", 18));    // 10 WBTC
  console.log("Minted initial tokens to deployer.");

  // Save contract addresses and ABI for frontend/backend
  const contracts = {
    Settlement: settlement.target,
    USDT: usdt.target,
    WBTC: wbtc.target,
    SettlementABI: settlement.interface.format(hre.ethers.utils.FormatTypes.json),
  };
  console.log(JSON.stringify(contracts, null, 2));

  // Store these in your .env or a config file
  console.log("\nCopy these values to your .env file:");
  console.log(`SETTLEMENT_CONTRACT_ADDRESS=${settlement.target}`);
  console.log(`SETTLEMENT_CONTRACT_ABI='${settlement.interface.format(hre.ethers.utils.FormatTypes.json).replace(/'/g, "\\'")}'`);
  console.log(`MOCK_USDT_ADDRESS=${usdt.target}`);
  console.log(`MOCK_WBTC_ADDRESS=${wbtc.target}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
"@ | Set-Content -Path "scripts/deploy.js"

Write-Host "Blockchain files created."
Set-Location -Path ".." # Back to project root

# --- 5. Docker Compose and Environment Variables ---
Write-Host "Creating Docker Compose file and .env..."

# .env file content (placeholders)
@"
# Backend and Blockchain Environment Variables
MONGODB_URI=mongodb://mongo1:27017,mongo2:27018,mongo3:27019/?replicaSet=dbrs
RABBITMQ_URI=amqp://guest:guest@rabbitmq:5672/

# Ethereum Testnet (e.g., Sepolia Infura/Alchemy URL)
ETH_TESTNET_URL=YOUR_INFURA_SEPOLIA_URL_HERE
# Private key of an account with ETH on the testnet for deploying and potentially signing (for automated worker)
PRIVATE_KEY=YOUR_ETHEREUM_PRIVATE_KEY_HERE
# Etherscan API Key (optional, for contract verification)
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY_HERE

# Binance API Keys (optional, for live data streaming in backend)
BINANCE_API_KEY=YOUR_BINANCE_API_KEY_HERE
BINANCE_SECRET=YOUR_BINANCE_SECRET_HERE

# After deploying the Settlement contract, update these values
SETTLEMENT_CONTRACT_ADDRESS=
SETTLEMENT_CONTRACT_ABI=
MOCK_USDT_ADDRESS=
MOCK_WBTC_ADDRESS=
"@ | Set-Content -Path ".env"

# docker-compose.yml
@"
version: '3.8'

services:
  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: trading-api
    ports:
      - "8000:8000"
    volumes:
      - ./backend/app:/app/app # Mount for development, for production copy in Dockerfile
    env_file:
      - ./.env
    environment:
      # These override .env if present, or provide defaults
      MONGODB_URI: ${MONGODB_URI}
      RABBITMQ_URI: ${RABBITMQ_URI}
      BINANCE_API_KEY: ${BINANCE_API_KEY}
      BINANCE_SECRET: ${BINANCE_SECRET}
    depends_on:
      rabbitmq:
        condition: service_healthy
      mongo1:
        condition: service_healthy

  settlement-worker:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: settlement-worker
    command: python -m app.consumer # Runs the dedicated consumer script
    volumes:
      - ./backend/app:/app/app
    env_file:
      - ./.env
    environment:
      # These override .env if present, or provide defaults
      MONGODB_URI: ${MONGODB_URI}
      RABBITMQ_URI: ${RABBITMQ_URI}
      ETH_TESTNET_URL: ${ETH_TESTNET_URL}
      SETTLEMENT_CONTRACT_ADDRESS: ${SETTLEMENT_CONTRACT_ADDRESS}
      SETTLEMENT_CONTRACT_ABI: ${SETTLEMENT_CONTRACT_ABI}
    depends_on:
      rabbitmq:
        condition: service_healthy
      mongo1:
        condition: service_healthy

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: rabbitmq
    ports:
      - "5672:5672" # AMQP protocol port
      - "15672:15672" # Management UI port
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_port_connectivity"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  mongo1:
    image: mongo:7
    container_name: mongo1
    ports:
      - "27017:27017"
    volumes:
      - mongo1-data:/data/db
    command: ["--replSet", "dbrs", "--bind_ip_all"]
    healthcheck:
      test: test $$(echo "rs.initiate({_id: 'dbrs', members: [{_id: 0, host: 'mongo1:27017'}, {_id: 1, host: 'mongo2:27018'}, {_id: 2, host: 'mongo3:27019'}]}).ok" | mongosh --quiet) -eq 1
      interval: 10s
      timeout: 10s
      retries: 5
    restart: always

  mongo2:
    image: mongo:7
    container_name: mongo2
    ports:
      - "27018:27018"
    volumes:
      - mongo2-data:/data/db
    command: ["--replSet", "dbrs", "--bind_ip_all"]
    depends_on:
      - mongo1
    restart: always

  mongo3:
    image: mongo:7
    container_name: mongo3
    ports:
      - "27019:27019"
    volumes:
      - mongo3-data:/data/db
    command: ["--replSet", "dbrs", "--bind_ip_all"]
    depends_on:
      - mongo1
    restart: always

volumes:
  mongo1-data:
  mongo2-data:
  mongo3-data:
"@ | Set-Content -Path "docker-compose.yml"

Write-Host "Docker Compose and .env files created."

Write-Host "Project setup complete! Here are the next steps:"
Write-Host "------------------------------------------------"
Write-Host "1.  Update the '.env' file in the '$projectRoot' directory with your actual API keys and testnet URLs. This is crucial for both blockchain deployment and optional Binance data streaming."
Write-Host "    - ETH_TESTNET_URL (e.g., from Infura or Alchemy)"
Write-Host "    - PRIVATE_KEY (of an account with test ETH)"
Write-Host "    - SETTLEMENT_CONTRACT_ADDRESS and SETTLEMENT_CONTRACT_ABI (will be filled after step 2)"
Write-Host "    - MOCK_USDT_ADDRESS and MOCK_WBTC_ADDRESS (will be filled after step 2)"
Write-Host "    - BINANCE_API_KEY, BINANCE_SECRET (optional)"
Write-Host ""
Write-Host "2.  Deploy the Smart Contracts:"
Write-Host "    - Navigate to the 'blockchain' directory: cd blockchain"
Write-Host "    - Run the Hardhat deployment script (after filling .env): npx hardhat run scripts/deploy.js --network sepolia"
Write-Host "    - Copy the `SETTLEMENT_CONTRACT_ADDRESS`, `SETTLEMENT_CONTRACT_ABI`, `MOCK_USDT_ADDRESS`, and `MOCK_WBTC_ADDRESS` outputs from the deployment script to your '.env' file in the root project directory."
Write-Host ""
Write-Host "3.  Start the Services with Docker Compose:"
Write-Host "    - Navigate back to the root project directory: cd .."
Write-Host "    - Run: docker compose up --build -d"
Write-Host "    - This will build and start the backend API, settlement worker, MongoDB replica set, and RabbitMQ."
Write-Host ""
Write-Host "4.  Start the Frontend Development Server:"
Write-Host "    - Open a new PowerShell terminal and navigate to the 'frontend' directory: cd frontend"
Write-Host "    - Run: npm start"
Write-Host "    - The React app will open in your browser (usually http://localhost:3000)."
Write-Host ""
Write-Host "5.  Interact with the Application:"
Write-Host "    - In your browser, connect your MetaMask wallet to the appropriate testnet (e.g., Sepolia)."
Write-Host "    - Place buy/sell orders. Matched trades will be sent to RabbitMQ and processed by the settlement worker."
Write-Host ""
Write-Host "To stop all services, navigate to the root '$projectRoot' directory and run: docker compose down"