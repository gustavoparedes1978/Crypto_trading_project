// This line imports the Hardhat Runtime Environment (HRE), which gives access to all the
// Hardhat functionalities and plugins, like Ethers.js.
const hre = require("hardhat");

// The `main` function is the entry point for the deployment script. It is an async function
// because contract deployment and interaction are asynchronous operations.
async function main() {
    // Retrieves the first account listed in the Hardhat configuration's `accounts` section.
    // This is typically the default deployer account.
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Sets the initial supply for the TestUSDT token. `parseEther` converts a
    // human-readable number ("1000000") into the smallest unit of the token (wei),
    // accounting for the token's 18 decimal places.
    const initialSupply = hre.ethers.parseEther("1000000");

    // Gets the contract factory for the "TestUSDT" contract. The factory is an object
    // used to deploy new instances of the contract.
    const TestUSDT = await hre.ethers.getContractFactory("TestUSDT");
    console.log("Deploying TestUSDT...");
    // Deploys a new instance of the TestUSDT contract, passing the `initialSupply`
    // to its constructor.
    const testUSDT = await TestUSDT.deploy(initialSupply);
    // Waits for the deployment transaction to be mined and confirmed.
    await testUSDT.waitForDeployment();
    // Retrieves the address of the newly deployed contract.
    const usdtAddress = await testUSDT.getAddress();
    console.log("TestUSDT deployed to:", usdtAddress);

    // Gets the contract factory for the "SimpleExchange" contract.
    const SimpleExchange = await hre.ethers.getContractFactory("SimpleExchange");
    console.log("Deploying SimpleExchange...");
    // Deploys a new instance of the SimpleExchange contract, passing the address of the
    // already deployed TestUSDT contract to its constructor.
    const exchange = await SimpleExchange.deploy(usdtAddress);
    // Waits for the deployment transaction to be mined.
    await exchange.waitForDeployment();
    // Retrieves the address of the newly deployed exchange contract.
    const exchangeAddress = await exchange.getAddress();
    console.log("SimpleExchange deployed to:", exchangeAddress);
}

// This is the standard way to run the `main` function in a Hardhat script.
// It calls the `main` function and includes a `catch` block to handle any errors
// that occur during the execution, logging the error and exiting the process with a failure code.
main().catch((error) => {
    console.error("An error occurred during deployment:", error);
    process.exitCode = 1;
});