// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol"; // Import Hardhat's console for logging during development and testing

// A simple smart contract acting as a decentralized exchange for trading ETH and USDT
contract SimpleExchange {
    // Defines an event to be emitted after a successful trade. Events are a way to log
    // information on the blockchain that can be easily accessed off-chain (e.g., by
    // a dApp's front-end).
    // `indexed` makes the parameters searchable.
    event Trade(address indexed buyer, address indexed seller, uint256 ethAmount, uint256 usdtAmount);

    // Declares a state variable to hold the address of the USDT ERC20 token contract.
    // `public` creates an automatic getter function for this variable.
    IERC20 public usdtToken;

    // The constructor is a special function that is executed only once when the
    // contract is deployed.
    // It takes the address of the USDT token as a parameter.
    constructor(address _usdtTokenAddress) {
        // Logs a message to the Hardhat console, useful for debugging deployment.
        console.log("SimpleExchange deployed with USDT address:", _usdtTokenAddress);
        // Initializes the `usdtToken` variable with the address of the USDT contract,
        // allowing this contract to interact with the USDT token.
        usdtToken = IERC20(_usdtTokenAddress);
    }

    // A function allowing a user to buy ETH from a seller using USDT.
    // `public` means anyone can call this function.
    // `payable` means this function can receive ETH.
    function buyETH(address seller, uint256 usdtAmount) public payable {
        // Log trade details for debugging.
        console.log("Trade initiated by buyer:", msg.sender);
        console.log("Seller address:", seller);
        console.log("ETH amount received:", msg.value);
        console.log("USDT amount to transfer:", usdtAmount);

        // Ensures the amount of ETH sent with the transaction is greater than zero.
        // `require` is used for pre-conditions and will revert the transaction if the
        // condition is false, refunding any gas used.
        require(msg.value > 0, "ETH amount must be greater than zero");
        console.log("ETH amount check passed.");
        
        // Checks the buyer's allowance for this contract to spend their USDT.
        // `allowance` is a standard ERC20 function that returns the amount of tokens
        // that a spender is allowed to withdraw from a specific address.
        uint256 allowance = usdtToken.allowance(msg.sender, address(this));
        console.log("Buyer's USDT allowance to exchange:", allowance);

        // Checks if the allowance is sufficient to cover the trade amount.
        require(allowance >= usdtAmount, "Insufficient USDT allowance");
        console.log("Allowance check passed.");

        // Transfers the specified amount of USDT from the buyer to the seller.
        // `transferFrom` is called on the USDT token contract. This requires the
        // buyer to have previously approved this contract to spend their USDT.
        require(usdtToken.transferFrom(msg.sender, seller, usdtAmount), "USDT transfer failed");
        console.log("USDT transferred from buyer to seller.");

        // Transfers the ETH received in this transaction to the seller.
        // The `call` method is a low-level way to send ETH and is a recommended
        // way to transfer ETH to external addresses as it mitigates re-entrancy risks.
        // It returns a boolean indicating success and the return data.
        (bool success, ) = seller.call{value: msg.value}("");
        // Checks if the ETH transfer was successful.
        require(success, "ETH transfer to seller failed");
        console.log("ETH transferred from contract to seller.");

        // Emits the `Trade` event with details of the transaction.
        emit Trade(msg.sender, seller, msg.value, usdtAmount);
        console.log("Trade event emitted.");
    }
}