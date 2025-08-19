# The code is a FastAPI application that serves as a simple cryptocurrency exchange backend.
# It includes API endpoints for placing orders and fetching order book data,
# as well as a WebSocket endpoint for real-time market data updates.

import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List
import logging
from .dependencies import db, get_rabbitmq_channel
from .matching_engine import Order, order_books
# from binance import AsyncWebsocketStreamManager # Uncomment if you want live Binance data

# Configure basic logging for a clear record of application events and errors.
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Initialize the FastAPI application.
app = FastAPI()

# Configure CORS (Cross-Origin Resource Sharing) to allow the frontend
# application (e.g., a React app running on localhost:3000) to
# communicate with this backend API. This is crucial for web development.
origins = [
    "http://localhost:3000",  # React app development server
    "http://127.0.0.1:3000",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods (GET, POST, etc.)
    allow_headers=["*"],  # Allow all headers
)

# Dictionary to store active WebSocket connections. The key is a unique
# identifier for the client (e.g., "host:port") and the value is the WebSocket object.
active_connections: Dict[str, WebSocket] = {}

# Pydantic model to define the structure of the order book data
# that will be returned by the API. This ensures data consistency.
class OrderBookData(BaseModel):
    # A list of bids, where each bid is a dictionary with price and amount.
    bids: List[Dict[str, float]]
    # A list of asks, structured similarly to bids.
    asks: List[Dict[str, float]]

# API Endpoints
# ---

# Endpoint to place a new order. It accepts an 'Order' object,
# which is a Pydantic model for data validation.
@app.post("/api/v1/order")
async def place_order(order: Order):
    logger.info(f"Received new order: {order.dict()}")
    # TODO: Add more robust user authentication and balance checks here
    # A real-world application would need to verify the user's identity and
    # ensure they have sufficient funds before processing the order.

    # Retrieve the correct order book for the specified trading pair (e.g., "BTC-USD").
    order_book = order_books.get(order.pair)
    if not order_book:
        logger.warning(f"Invalid trading pair '{order.pair}' requested for order.")
        # If the pair doesn't exist, return a 400 Bad Request error.
        raise HTTPException(status_code=400, detail="Invalid trading pair")
    
    # Simple validation logic to ensure market and limit orders are correctly formatted.
    # Market orders don't need a price, as they are executed at the best available price.
    if order.order_type == 'market' and order.price is not None:
        logger.warning("Market order received with a price. Price will be ignored.")
        # A more common approach is to simply ignore the price, as the system
        # will handle the market order logic, regardless of a provided price.

    # Limit orders must have a price to define the limit at which they should be executed.
    if order.order_type == 'limit' and order.price is None:
        logger.error("Limit order received without a price.")
        raise HTTPException(status_code=400, detail="Limit orders must specify a price")

    try:
        # Add the validated order to the matching engine's order book.
        await order_book.add_order(order)
        logger.info(f"Order {order.order_id} for pair {order.pair} submitted successfully.")
        # Return a success message and the order's unique ID.
        return {"message": "Order submitted successfully", "order_id": order.order_id}
    except Exception as e:
        # Catch any unexpected errors during order processing and log them.
        logger.error(f"Failed to add order {order.order_id} to the order book: {e}", exc_info=True)
        # Return a 500 Internal Server Error to the client.
        raise HTTPException(status_code=500, detail="Internal server error while processing order.")

# Endpoint to get the current state of a specific trading pair's order book.
@app.get("/api/v1/orderbook/{pair}", response_model=OrderBookData)
async def get_order_book_endpoint(pair: str):
    logger.info(f"Fetching order book for pair: {pair}")
    order_book = order_books.get(pair)
    if not order_book:
        logger.warning(f"Order book for pair '{pair}' not found. Returning empty data.")
        # If no order book exists for the pair, return an empty set of bids and asks.
        return {"bids": [], "asks": []}
    
    # Call the method on the order book object to get the current data.
    data = await order_book.get_order_book_data()
    logger.info(f"Successfully fetched order book data for {pair}.")
    return data

# Real-time WebSocket endpoint for market data updates.
# This allows clients to receive live data without repeatedly polling the API.
@app.websocket("/ws/marketdata")
async def websocket_endpoint(websocket: WebSocket):
    # Create a unique key for the client based on their IP and port.
    client_key = f"{websocket.client.host}:{websocket.client.port}"
    logger.info(f"Attempting to accept WebSocket connection for client: {client_key}")
    try:
        # Accept the incoming WebSocket connection.
        await websocket.accept()
        # Store the connection in the dictionary of active connections.
        active_connections[client_key] = websocket
        logger.info(f"Client {client_key} connected to WebSocket.")
    except Exception as e:
        logger.error(f"Failed to accept WebSocket connection for {client_key}: {e}", exc_info=True)
        return

    try:
        # The main loop for the WebSocket connection.
        while True:
            # Note: The current implementation only fetches data for "BTC-USD".
            # A more advanced system might allow the client to specify which pair
            # they want to subscribe to.
            pair_to_fetch = "BTC-USD"
            logger.debug(f"Fetching and sending order book update for {pair_to_fetch} to client {client_key}.")
            
            # Fetch the latest order book data via the existing API function.
            order_book_data = await get_order_book_endpoint(pair=pair_to_fetch)
            
            try:
                # Send the data to the connected client as a JSON message.
                await websocket.send_json({"type": "orderbook_update", "data": order_book_data.dict()})
                logger.debug(f"Successfully sent update to client {client_key}.")
            except RuntimeError as e:
                # Handle cases where the connection is no longer active.
                logger.warning(f"Error sending to WebSocket {client_key}: {e}. Connection may be closed.")
                break
            
            # Pause for one second before sending the next update.
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        # This exception is raised when the client gracefully closes the connection.
        # Remove the disconnected client from the active connections dictionary.
        del active_connections[client_key]
        logger.info(f"Client {client_key} disconnected from WebSocket.")
    except Exception as e:
        # Catch any other unexpected errors and log them.
        logger.error(f"Unexpected error in WebSocket {client_key}: {e}", exc_info=True)
        if client_key in active_connections:
            # Ensure the connection is removed from the active connections list.
            del active_connections[client_key]

# Optional: Binance live data stream integration.
# This section is commented out but provides a blueprint for integrating with
# a live external data source like Binance to provide real-time pricing.
# It uses the `AsyncWebsocketStreamManager` to listen for ticker updates.
# The data received from Binance could then be used to inform trades or
# provide more dynamic pricing.
# async def binance_live_stream():
#     logger.info("Starting Binance stream placeholder.")
#     ... (code for managing the stream) ...
#     while True:
#         logger.debug("Binance stream placeholder running...")
#         await asyncio.sleep(5)

# This event handler would be used to start background tasks, such as the
# Binance data stream, when the application starts up.
# @app.on_event("startup")
# async def startup_event():
#     logger.info("Application startup event triggered.")
#     # Uncomment to enable Binance stream
#     # asyncio.create_task(binance_live_stream())
#     pass