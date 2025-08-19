import pkg from 'hardhat';
const { ethers } = pkg;

/**
 * This script is a Hardhat deployment script for a hybrid trading system.
 * It's responsible for deploying the necessary smart contracts (MockERC20 tokens and the Settlement contract)
 * to a local blockchain or testnet. It also configures them and provides useful output for developers.
 */
async function main() {
  // Get the first account listed in the Hardhat network configuration.
  // This account is automatically funded and will be used as the deployer.
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // --- Contract Deployment ---

  // Get the ContractFactory for the MockERC20 contract, which is a representation
  // of the contract in the JavaScript environment.
  const MockERC20 = await ethers.getContractFactory("MockERC20");

  // Deploy the first mock token, a stand-in for USDT.
  const usdt = await MockERC20.deploy("Tether USD", "USDT", deployer.address);
  // Wait for the deployment transaction to be mined and confirmed.
  await usdt.waitForDeployment();
  console.log("USDT deployed to:", usdt.target);

  // Deploy the second mock token, a stand-in for WBTC.
  const wbtc = await MockERC20.deploy("Wrapped BTC", "WBTC", deployer.address);
  // Wait for the deployment transaction to be mined.
  await wbtc.waitForDeployment();
  console.log("WBTC deployed to:", wbtc.target);

  // Get the ContractFactory for the Settlement contract.
  const Settlement = await ethers.getContractFactory("Settlement");
  // Deploy the Settlement contract. Its constructor requires the owner's address
  // and the addresses of the two tokens it will manage.
  const settlement = await Settlement.deploy(deployer.address, usdt.target, wbtc.target);
  // Wait for the deployment transaction to be mined.
  await settlement.waitForDeployment();
  console.log("Settlement deployed to:", settlement.target);

  // --- Initial Setup and Configuration ---

  // Optional: Mint some initial tokens to the deployer account. This is essential for testing
  // the trade settlement functionality, as the deployer now has assets to trade with.
  // `ethers.parseUnits` converts a human-readable number (e.g., "1000000") to the smallest
  // token unit (wei for 18 decimals) for on-chain calculations.
  await usdt.mint(deployer.address, ethers.parseUnits("1000000", 18)); // 1,000,000 USDT
  await wbtc.mint(deployer.address, ethers.parseUnits("10", 18));      // 10 WBTC
  console.log("Minted initial tokens to deployer.");

  // --- Output for Development ---

  // Log the deployed contract addresses. This is a critical step as these addresses
  // need to be copied into environment variables (.env file) for other parts of the
  // application (like the backend consumer or frontend) to interact with the correct contracts.
  console.log("\nCopy these values to your .env file:");
  console.log(`SETTLEMENT_CONTRACT_ADDRESS=${settlement.target}`);
  console.log(`MOCK_USDT_ADDRESS=${usdt.target}`);
  console.log(`MOCK_WBTC_ADDRESS=${wbtc.target}`);
}

// Run the main function and catch any potential errors during deployment.
// If an error occurs, log it and exit the process with a failure code (1).
main().catch((error) => {
  console.error(error);
  process.exit(1);
});