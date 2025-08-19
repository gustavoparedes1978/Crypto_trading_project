import os
import asyncio
import json
from web3 import Web3, HTTPProvider
import aio_pika
from dotenv import load_dotenv
import logging

# Configure logging for the script to provide visibility into its operations.
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from a .env file.
load_dotenv()
logger.info("Environment variables loaded.")

# --- Web3 and Smart Contract Setup ---
# Retrieve required environment variables for connecting to the blockchain and smart contract.
ETH_TESTNET_URL = os.getenv("ETH_TESTNET_URL")
SETTLEMENT_CONTRACT_ADDRESS = os.getenv("SETTLEMENT_CONTRACT_ADDRESS")
SETTLEMENT_CONTRACT_ABI_STR = os.getenv("SETTLEMENT_CONTRACT_ABI")
RABBITMQ_URI = os.getenv("RABBITMQ_URI")
# Define the name of the queue to consume messages from.
QUEUE_NAME = "trade_settlement_queue"

# Validate that all necessary environment variables are present.
if not all([ETH_TESTNET_URL, SETTLEMENT_CONTRACT_ADDRESS, SETTLEMENT_CONTRACT_ABI_STR, RABBITMQ_URI]):
    logger.error("Missing one or more required environment variables for consumer. Exiting.")
    exit(1)

# Connect to the Ethereum testnet using the provided URL.
logger.info(f"Connecting to Ethereum testnet URL: {ETH_TESTNET_URL}")
w3 = Web3(HTTPProvider(ETH_TESTNET_URL))
if w3.is_connected():
    logger.info("Successfully connected to Ethereum testnet.")
else:
    logger.error("Failed to connect to Ethereum testnet. Check ETH_TESTNET_URL.")
    exit(1)

# Attempt to parse the contract's ABI from a string to a JSON object.
try:
    SETTLEMENT_CONTRACT_ABI = json.loads(SETTLEMENT_CONTRACT_ABI_STR)
    logger.info("SETTLEMENT_CONTRACT_ABI successfully parsed.")
except json.JSONDecodeError:
    logger.error("Error parsing SETTLEMENT_CONTRACT_ABI. Ensure it's valid JSON. Exiting.", exc_info=True)
    exit(1)

# Create a contract instance using the address and ABI. This allows the script
# to call functions on the smart contract.
logger.info(f"Loading settlement contract at address: {SETTLEMENT_CONTRACT_ADDRESS}")
settlement_contract = w3.eth.contract(address=SETTLEMENT_CONTRACT_ADDRESS, abi=SETTLEMENT_CONTRACT_ABI)

# --- RabbitMQ Message Consumer Logic ---
async def on_message(message: aio_pika.IncomingMessage):
    """
    Callback function to process incoming messages from the RabbitMQ queue.
    This function is triggered automatically when a new message is received.
    """
    logger.debug(f"Received raw message: {message.body.decode()}")
    # Use a context manager to automatically acknowledge the message upon successful processing.
    async with message.process():
        try:
            # Decode the message body (byte string) into a JSON object (dictionary).
            trade_data = json.loads(message.body.decode())
            logger.info(f"Received trade for settlement: {trade_data}")

            # Extract key data points from the trade message.
            trade_id = trade_data.get("trade_id")
            buyer_address = trade_data.get("buyer_user_id")
            seller_address = trade_data.get("seller_user_id")
            
            # Convert float values for price and amount into integer wei values.
            # Wei is the smallest unit of Ether (1 ETH = 10^18 wei),
            # which is required for accurate on-chain calculations.
            price = int(trade_data.get("price") * (10**18)) 
            amount = int(trade_data.get("amount") * (10**18)) 

            logger.debug(f"Parsed trade data - ID: {trade_id}, Buyer: {buyer_address}, Seller: {seller_address}, Price (wei): {price}, Amount (wei): {amount}")

            # --- Mocking on-chain settlement for demonstration ---
            # In a real system, you would call a function on the `settlement_contract`
            # here, passing the trade details as parameters. This would involve
            # building and signing a transaction.
            # Example: settlement_contract.functions.settleTrade(trade_id, buyer_address, seller_address, price, amount).transact(...)
            
            # Generate a mock transaction hash to simulate a successful on-chain transaction.
            tx_hash = f"0x{os.urandom(32).hex()}" 
            logger.info(f"Simulated on-chain transaction with hash: {tx_hash} for trade {trade_id}")

            # Example: Update a database.
            # In a production environment, this is where you would update your off-chain
            # database to record the successful settlement and the transaction hash.
            logger.info(f"Trade {trade_id} marked as settled (simulated) with TX: {tx_hash}")

        except json.JSONDecodeError:
            # Handle cases where the message body is not valid JSON.
            logger.error(f"Failed to decode JSON from message body: {message.body.decode()}", exc_info=True)
            # Acknowledge the message but do not requeue it, preventing an endless loop.
            await message.nack(requeue=False)
        except KeyError as e:
            # Handle cases where a required key is missing from the JSON data.
            logger.error(f"Missing expected key in trade data: {e}. Message: {message.body.decode()}", exc_info=True)
            await message.nack(requeue=False)
        except Exception as e:
            # Catch any other unexpected errors during processing.
            logger.error(f"Error processing message or during on-chain settlement for message: {message.body.decode()}: {e}", exc_info=True)
            # Requeue the message for a later retry, as the error might be temporary (e.g., network issue).
            await message.nack(requeue=True) 

# --- Consumer Main Function ---
async def start_consumer():
    """
    Connects to RabbitMQ and sets up the consumer.
    """
    logger.info(f"Attempting to connect to RabbitMQ at: {RABBITMQ_URI}")
    try:
        # Establish a robust connection to RabbitMQ, which handles retries.
        connection = await aio_pika.connect_robust(RABBITMQ_URI)
        logger.info("Successfully connected to RabbitMQ.")
    except Exception as e:
        logger.error(f"Failed to connect to RabbitMQ: {e}. Please check RABBITMQ_URI and availability.", exc_info=True)
        exit(1)

    try:
        # Open a communication channel.
        channel = await connection.channel()
        logger.info("RabbitMQ channel opened.")
        
        # Set Quality of Service (QoS) to prefetch one message at a time. This ensures
        # the worker doesn't get overwhelmed and only processes messages one by one.
        await channel.set_qos(prefetch_count=1)
        logger.info(f"QoS set: prefetch_count=1.")
        
        # Declare the queue. If it doesn't exist, it will be created.
        # `durable=True` ensures the queue survives a RabbitMQ restart.
        queue = await channel.declare_queue(QUEUE_NAME, durable=True)
        logger.info(f"Queue '{QUEUE_NAME}' declared. Starting consumption.")
        
        # Start consuming messages from the queue, using `on_message` as the callback.
        await queue.consume(on_message)
        
        logger.info("Settlement worker started. Waiting for messages...")
        # Keep the consumer running indefinitely.
        await asyncio.Future()
    except Exception as e:
        logger.critical(f"Critical error during consumer startup: {e}", exc_info=True)
    finally:
        # Ensure the connection is closed cleanly when the consumer stops.
        if connection:
            await connection.close()
            logger.info("RabbitMQ connection closed.")

# --- Script Entry Point ---
if __name__ == "__main__":
    logger.info("Starting settlement worker main execution.")
    try:
        # Run the asynchronous consumer.
        asyncio.run(start_consumer())
    except KeyboardInterrupt:
        logger.info("Settlement worker stopped by user (KeyboardInterrupt).")
    except Exception as e:
        logger.critical(f"Unhandled exception in main execution: {e}", exc_info=True)