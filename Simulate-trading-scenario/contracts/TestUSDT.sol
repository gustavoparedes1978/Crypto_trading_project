// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol"; // Import Hardhat's console for logging during development and testing

// This contract is a mock or test version of a USDT token, named "tUSDT".
// It inherits from OpenZeppelin's standard ERC20 and Ownable contracts.
// This is typically used for local development and testing environments.
contract TestUSDT is ERC20, Ownable {

    // The constructor is executed only once when the contract is deployed.
    // It initializes the ERC20 token with a name ("Test Tether") and a symbol ("tUSDT").
    // It also sets the `Ownable` contract's owner to the address that deploys it (`msg.sender`).
    constructor(uint256 initialSupply) ERC20("Test Tether", "tUSDT") Ownable(msg.sender) {
        // Log a debugging message showing who deployed the contract.
        console.log("TestUSDT deployed by:", msg.sender);
        // Log the initial supply that will be minted.
        console.log("Initial supply set to:", initialSupply);
        // Mints the `initialSupply` of tokens and assigns them to the contract deployer's address.
        // The `_mint` function is an internal function provided by the ERC20 contract.
        _mint(msg.sender, initialSupply);
    }

    // A public function that allows the owner of the contract to mint new tokens.
    // `onlyOwner` is a modifier from the `Ownable` contract, ensuring that only the
    // contract's owner can call this function.
    // It takes the recipient's address and the amount to mint as parameters.
    function mint(address to, uint256 amount) public onlyOwner {
        // Log a debugging message showing the amount and recipient of the new tokens.
        console.log("Minting", amount, "tUSDT to:", to);
        // Mints the specified `amount` of tokens and assigns them to the `to` address.
        _mint(to, amount);
    }
}