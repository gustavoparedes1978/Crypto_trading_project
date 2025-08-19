// The Hardhat configuration file for the project.
// It sets up the compiler version, specifies network details for deployment,
// and manages API keys for external services like Etherscan.

// Import Hardhat plugins and libraries.
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

// Load environment variables from the project's root directory.
// This is a crucial line that fixes the common issue of Hardhat not finding the .env file
// by explicitly pointing to its location one directory up.
dotenv.config({ path: '../.env' }); 

// Log the loaded environment variable to confirm it's working.
console.log(process.env.ETH_TESTNET_URL);

// The main configuration object that Hardhat uses.
const config = {
  // Specify the Solidity compiler version to use.
  solidity: "0.8.20",
  // Define the blockchain networks the project can interact with.
  networks: {
    // Configuration for the Sepolia testnet.
    sepolia: {
      // Get the network URL from an environment variable.
      // The `|| ""` provides a fallback to an empty string if the variable is not set.
      url: process.env.ETH_TESTNET_URL || "",
      // Get the private key(s) from an environment variable to sign transactions.
      // It checks if the key exists and formats it into an array as required by Hardhat.
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  // Etherscan configuration for contract verification.
  etherscan: {
    // Use the API key from the environment variables.
    // This allows for automatic source code verification on Etherscan after deployment.
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

// Export the configuration object so Hardhat can use it.
export default config;