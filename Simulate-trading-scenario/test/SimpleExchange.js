// This line imports the Chai assertion library, a popular choice for writing tests in JavaScript.
// It provides the `expect` function for making clear and readable assertions.
const { expect } = require("chai");
// This line imports the Hardhat Runtime Environment's Ethers.js module. Hardhat enhances Ethers.js
// by providing a direct way to interact with the local development blockchain and smart contracts.
const { ethers } = require("hardhat");

// The `describe` function is a block that groups related tests together.
// The string "SimpleExchange" is a label for this test suite.
describe("SimpleExchange", function () {
    // Declares variables to hold contract instances and accounts. These are made
    // accessible to all tests within this `describe` block.
    let testUSDT, exchange, owner, customerA, customerB;
    // Defines a constant for the initial supply of the test USDT token, converted to
    // its smallest unit (18 decimal places).
    const initialSupply = ethers.parseUnits("1000000", 18);

    // `beforeEach` is a Mocha hook that runs before each test (`it` block) in the suite.
    // This is useful for setting up a clean state for every test, such as deploying contracts.
    beforeEach(async function () {
        // Retrieves a list of available accounts from the Hardhat network. The first
        // three are assigned to `owner`, `customerA`, and `customerB`.
        [owner, customerA, customerB] = await ethers.getSigners();
        console.log("Test Accounts Initialized:");
        console.log("  Owner:", owner.address);
        console.log("  Customer A:", customerA.address);
        console.log("  Customer B:", customerB.address);

        // Gets a contract factory for the `TestUSDT` contract. The factory is an object
        // that can be used to deploy the contract.
        const TestUSDTFactory = await ethers.getContractFactory("TestUSDT", owner);
        // Deploys a new instance of the `TestUSDT` contract, passing the `initialSupply`
        // to its constructor.
        testUSDT = await TestUSDTFactory.deploy(initialSupply);
        // Waits for the contract deployment transaction to be confirmed on the network.
        await testUSDT.waitForDeployment();
        console.log("TestUSDT deployed at:", await testUSDT.getAddress());

        // Gets the contract factory for the `SimpleExchange` contract.
        const SimpleExchangeFactory = await ethers.getContractFactory("SimpleExchange", owner);
        // Deploys a new instance of the `SimpleExchange` contract, passing the address
        // of the deployed `testUSDT` contract to its constructor.
        exchange = await SimpleExchangeFactory.deploy(await testUSDT.getAddress());
        // Waits for the deployment transaction to be confirmed.
        await exchange.waitForDeployment();
        console.log("SimpleExchange deployed at:", await exchange.getAddress());

        console.log("Funding Customer A with 1000 tUSDT...");
        // Transfers 1000 tUSDT tokens from the `owner` (who received the initial supply)
        // to `customerA`. `connect(owner)` ensures the transaction is signed by the owner.
        await testUSDT.connect(owner).transfer(customerA.address, ethers.parseUnits("1000", 18));
        
        console.log("Funding Customer B with 5 ETH...");
        // Sends a transaction to transfer 5 ETH from the `owner` to `customerB`.
        // This is necessary because `customerB` will be the seller of ETH in the trade.
        await owner.sendTransaction({
            to: customerB.address,
            value: ethers.parseEther("5")
        });
    });

    // An `it` block defines a single test case. The string "Should allow a buyer to trade USDT for ETH"
    // is a descriptive name for the test.
    it("Should allow a buyer to trade USDT for ETH", async function () {
        console.log("\n--- Starting 'buyETH' test ---");
        // Defines the amounts of USDT and ETH to be used in the trade, converting them
        // to their respective smallest units.
        const usdtAmountToSpend = ethers.parseUnits("50", 18);
        const ethAmountToBuy = ethers.parseEther("0.025");

        // Fetches the initial USDT balances of both `customerA` and `customerB` for comparison later.
        const customerAInitialUSDTBalance = await testUSDT.balanceOf(customerA.address);
        const customerBInitialUSDTBalance = await testUSDT.balanceOf(customerB.address);
        console.log("Initial balances fetched.");
        console.log("  Customer A USDT:", ethers.formatEther(customerAInitialUSDTBalance));
        console.log("  Customer B USDT:", ethers.formatEther(customerBInitialUSDTBalance));

        console.log("Customer A approving exchange for", ethers.formatEther(usdtAmountToSpend), "tUSDT...");
        // `customerA` calls the `approve` function on the `testUSDT` contract, giving the
        // `exchange` contract permission to spend a certain amount of their tokens.
        await testUSDT.connect(customerA).approve(await exchange.getAddress(), usdtAmountToSpend);
        
        console.log("Customer A executing trade...");
        // `customerA` calls the `buyETH` function on the `exchange` contract.
        // The `value` field specifies the amount of ETH to be sent with the transaction.
        const tradeTx = await exchange.connect(customerA).buyETH(customerB.address, usdtAmountToSpend, {
            value: ethAmountToBuy
        });
        // Waits for the trade transaction to be mined and confirmed.
        await tradeTx.wait();
        console.log("Trade transaction confirmed.");

        // Fetches the final USDT balances after the trade to verify the transaction was successful.
        const customerAFinalUSDTBalance = await testUSDT.balanceOf(customerA.address);
        const customerBFinalUSDTBalance = await testUSDT.balanceOf(customerB.address);
        console.log("Final balances fetched.");
        console.log("  Customer A USDT:", ethers.formatEther(customerAFinalUSDTBalance));
        console.log("  Customer B USDT:", ethers.formatEther(customerBFinalUSDTBalance));

        // The assertion checks. `expect` is used to make sure the final balances are as expected.
        // It verifies that `customerA`'s balance decreased by the spent amount
        // and `customerB`'s balance increased by the same amount.
        expect(customerAFinalUSDTBalance).to.equal(customerAInitialUSDTBalance - usdtAmountToSpend);
        expect(customerBFinalUSDTBalance).to.equal(customerBInitialUSDTBalance + usdtAmountToSpend);

        console.log("Balances assertions passed.");
        console.log("--- Test finished ---");
    });
});