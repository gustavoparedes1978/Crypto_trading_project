# CryptoExchangeSimulation

This project simulates a peer-to-peer cryptocurrency exchange on the Sepolia testnet.

## Project Structure

- **contracts/**: Contains the Solidity smart contracts (TestUSDT.sol and SimpleExchange.sol).
- **scripts/**: Deployment and utility scripts.
- **test/**: JavaScript tests for the smart contracts.
- **frontend/**: The user interface for interacting with the dApp.
- **hardhat.config.js**: Hardhat project configuration.

## Setup & Deployment

1.  **Install Dependencies**: Run pm install in the project root.
2.  **Configure Environment**: Create a .env file based on .env.example and fill in your details.
3.  **Deploy Contracts**: Run px hardhat run scripts/deploy.js --network sepolia
4.  **Run Frontend**: Use a local web server to serve the frontend/public directory.
