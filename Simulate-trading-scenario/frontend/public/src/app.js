// This section would typically contain the Application Binary Interface (ABI) of the smart contracts.
// The ABI acts as an interface for a JavaScript application to interact with a smart contract on the blockchain.
const usdtAbi = []; // Paste the ABI for TestUSDT.sol here
const exchangeAbi = []; // Paste the ABI for SimpleExchange.sol here

/*
Deploying contracts with the account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Deploying TestUSDT...
TestUSDT deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Deploying SimpleExchange...
SimpleExchange deployed to: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

*/

// These variables store the deployed addresses of the smart contracts on the blockchain.
// They are used to create instances of the contracts in the code.
const usdtAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Paste the deployed TestUSDT address here
const exchangeAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; // Paste the deployed SimpleExchange address here

// This event listener ensures that the JavaScript code runs only after the entire HTML document has been loaded and parsed.
document.addEventListener('DOMContentLoaded', () => {
    console.log("DOM content loaded. Attaching event listeners.");
    // Attaches a click event listener to the 'connect-wallet' button, which calls the `connectWallet` function.
    document.getElementById('connect-wallet').addEventListener('click', connectWallet);
    // Attaches a click event listener to the 'execute-trade' button, which calls the `executeTrade` function.
    document.getElementById('execute-trade').addEventListener('click', executeTrade);
});

// Global variables to hold the Ethers.js provider, signer, and contract instances.
// These are declared outside the functions so they can be accessed throughout the script.
let provider, signer, usdtContract, exchangeContract;

// An asynchronous function to handle wallet connection using MetaMask or a similar browser-based wallet.
async function connectWallet() {
    console.log("Connect wallet button clicked.");
    // Checks if the `ethereum` object (injected by MetaMask) exists in the browser's `window` object.
    if (typeof window.ethereum !== 'undefined') {
        console.log("window.ethereum");
        try {
            
            console.log("MetaMask provider found. Requesting accounts...");
            // Requests user's permission to access their Ethereum accounts.
            await window.ethereum.request({ method: 'eth_requestAccounts' });
            // Creates a new Ethers.js `BrowserProvider` instance using the detected `window.ethereum` object.
            provider = new ethers.BrowserProvider(window.ethereum);
            console.log(provider);
            // Gets a `signer` object, which represents the user's connected account and is used to sign transactions.
            signer = await provider.getSigner();
            console.log(signer);
            
            // Gets the public address of the connected wallet.
            const address = await signer.getAddress();
            console.log("Wallet connected:", address);
            // Updates the HTML element with the connected wallet address.
            document.getElementById('wallet-address').innerText = address;

            // Creates an instance of the `TestUSDT` contract.
            // It uses the contract address, ABI, and the `signer` to be able to send transactions.
            usdtContract = new ethers.Contract(usdtAddress, usdtAbi, signer);
            // Creates an instance of the `SimpleExchange` contract.
            exchangeContract = new ethers.Contract(exchangeAddress, exchangeAbi, signer);
            console.log("Contract instances created.");

            // Calls the `updateBalances` function to display the user's ETH and USDT balances.
            updateBalances(address);
            // Enables the 'execute-trade' button once the wallet is connected.
            document.getElementById('execute-trade').disabled = false;
            console.log("Execute Trade button enabled.");
        } catch (error) {
            // Catches any errors during the connection process, such as the user denying access.
            console.error("User denied account access or another error occurred:", error);
        }
    } else {
        // Displays an error message if MetaMask is not installed.
        console.error("MetaMask not found. Please install MetaMask to use this dApp.");
    }
}

// An asynchronous function to fetch and display the user's ETH and USDT balances.
async function updateBalances(address) {
    console.log("Updating balances for address:", address);
    // Fetches the ETH balance of the given address using the Ethers.js provider.
    const ethBalance = await provider.getBalance(address);
    // Formats the balance from Wei (a small unit of ETH) to Ether and updates the HTML.
    document.getElementById('eth-balance').innerText = ethers.formatEther(ethBalance) + " ETH";
    console.log("ETH balance updated.");

    try {
        // Fetches the tUSDT balance by calling the `balanceOf` function on the `usdtContract`.
        const usdtBalance = await usdtContract.balanceOf(address);
        // Formats the balance and updates the HTML.
        document.getElementById('usdt-balance').innerText = ethers.formatEther(usdtBalance) + " tUSDT";
        console.log("tUSDT balance updated.");
    } catch (error) {
        // Catches and logs an error if the USDT balance retrieval fails.
        console.error("Failed to get tUSDT balance. Ensure the contract address is correct.", error);
    }
}

// An asynchronous function to handle the entire trade process.
async function executeTrade() {
    console.log("Execute trade button clicked.");
    // Defines the seller's address and the amounts for the trade.
    const sellerAddress = "0x..."; // Replace with Customer B's wallet address
    // `ethers.parseUnits` and `ethers.parseEther` convert human-readable numbers into large integer formats
    // (Wei for ETH, and a similar unit for USDT with 18 decimals) required by smart contracts.
    const usdtAmount = ethers.parseUnits("50", 18);
    const ethAmount = ethers.parseEther("0.025");
    console.log("Trade parameters set: USDT amount", ethers.formatEther(usdtAmount), "ETH amount", ethers.formatEther(ethAmount));

    try {
        console.log("Starting approval transaction...");
        // The buyer must first approve the `SimpleExchange` contract to spend their USDT.
        // This transaction calls the `approve` function on the USDT contract.
        const approvalTx = await usdtContract.approve(exchangeAddress, usdtAmount);
        // Waits for the transaction to be mined and confirmed on the blockchain.
        await approvalTx.wait();
        console.log("Approval transaction successful:", approvalTx.hash);

        console.log("Starting trade transaction...");
        // This is the core transaction that executes the trade on the `SimpleExchange` contract.
        // It calls the `buyETH` function, passing the seller's address, USDT amount, and the ETH amount as a `value`.
        const tradeTx = await exchangeContract.buyETH(sellerAddress, usdtAmount, { value: ethAmount });
        // Waits for the trade transaction to be mined.
        await tradeTx.wait();
        console.log("Trade transaction successful:", tradeTx.hash);

        // After a successful trade, update the balances to reflect the change.
        updateBalances(await signer.getAddress());
        console.log("Balances updated after trade.");
    } catch (error) {
        // Catches and logs any errors that occur during the transaction process.
        console.error("Trade failed:", error);
    }
}