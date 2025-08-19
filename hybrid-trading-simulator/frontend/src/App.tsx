import React, { useState, useEffect, useCallback } from 'react';
import { ethers, JsonRpcProvider } from 'ethers';
import OrderBook from './components/OrderBook';
import TradeForm from './components/TradeForm';

interface OrderBookData {
  bids: { price: number; amount: number }[];
  asks: { price: number; amount: number }[];
}

// Extend the Window interface to include ethereum for MetaMask detection
declare global {
  interface Window {
    ethereum?: any;
  }
}

const App: React.FC = () => {
  // State to store the connected wallet address
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  // State to store the order book data received from the WebSocket
  const [orderBook, setOrderBook] = useState<OrderBookData | null>(null);

  /**
   * @async
   * @function connectWallet
   * @description Attempts to connect to the user's MetaMask wallet.
   * If successful, it sets the wallet address and logs the connection.
   * If MetaMask is not detected or connection fails, it alerts the user.
   */
  const connectWallet = async () => {
    if (window.ethereum) {
      try {
        // Request accounts from MetaMask
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        const provider = new ethers.BrowserProvider(window.ethereum);
        console.log(provider);
		const signer = await provider.getSigner();
		console.log(signer);
        const address = await signer.getAddress();
        console.log(address);
		setWalletAddress(address);
        console.log("Connected to wallet:", address);
      } catch (error) {
        console.error("Failed to connect wallet:", error);
        // Use a more user-friendly modal or message box instead of alert()
        alert("Failed to connect MetaMask. Please ensure it's installed and unlocked.");
      }
    } else {
      // Use a more user-friendly modal or message box instead of alert()
      alert("MetaMask is not detected. Please install it to connect your wallet.");
    }
  };

  /**
   * @function handleAccountsChanged
   * @description Callback function for 'accountsChanged' event from MetaMask.
   * Updates the wallet address when the user changes accounts in MetaMask.
   * @param accounts - An array of account addresses.
   */
  const handleAccountsChanged = useCallback((accounts: string[]) => {
    if (accounts.length === 0) {
      // User disconnected their accounts from the DApp or locked MetaMask
      console.log('Please connect to MetaMask.');
      setWalletAddress(null);
    } else if (accounts[0] !== walletAddress) {
      // User switched accounts
      setWalletAddress(accounts[0]);
      console.log('Switched to account:', accounts[0]);
    }
  }, [walletAddress]); // Recreate if walletAddress changes

  /**
   * @function handleChainChanged
   * @description Callback function for 'chainChanged' event from MetaMask.
   * Reloads the page or handles network changes when the user switches networks.
   * @param chainId - The new chain ID.
   */
  const handleChainChanged = useCallback((chainId: string) => {
    // We recommend reloading the page when the network changes,
    // since most dApps only work on a single network.
    console.log('Chain changed to:', chainId);
    window.location.reload();
  }, []);

  // useEffect hook for setting up WebSocket connection and MetaMask event listeners
  useEffect(() => {
    // --- MetaMask Event Listeners Setup ---
    if (window.ethereum) {
      // Check for existing MetaMask connection on load
      const checkConnection = async () => {
        try {
          const provider = new ethers.BrowserProvider(window.ethereum);
          const accounts = await provider.listAccounts();
          if (accounts.length > 0) {
            setWalletAddress(accounts[0].address);
          }
        } catch (error) {
          console.error("Error checking MetaMask connection:", error);
        }
      };
      checkConnection();

      // Subscribe to accountsChanged event
      window.ethereum.on('accountsChanged', handleAccountsChanged);
      // Subscribe to chainChanged event
      window.ethereum.on('chainChanged', handleChainChanged);
    }

    // --- WebSocket Connection Setup ---
    // Replace with your actual WebSocket endpoint
    const ws = new WebSocket('ws://localhost:8000/ws/market_data');

    ws.onopen = () => {
      console.log('WebSocket connection established.');
    };

    ws.onmessage = (event) => {
      // Parse the incoming market data (assuming JSON string)
      const data: OrderBookData = JSON.parse(event.data);
      setOrderBook(data);
    };

    ws.onclose = (event) => {
      console.log('WebSocket connection closed:', event.code, event.reason);
      // Implement reconnection logic if needed
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    // Cleanup function for useEffect
    return () => {
      ws.close(); // Close WebSocket connection when component unmounts

      // Clean up MetaMask event listeners
      if (window.ethereum) {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
      }
    };
  }, [handleAccountsChanged, handleChainChanged]); // Dependencies for useEffect

  return (
    <div className="bg-gray-900 text-white min-h-screen p-8 font-inter">
      <header className="flex justify-between items-center mb-8 pb-4 border-b border-gray-700">
        <h1 className="text-3xl font-extrabold text-blue-400">Hybrid Trading Simulator</h1>
        <button
          onClick={connectWallet}
          className="bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-700 hover:to-indigo-700 text-white font-bold py-2 px-4 rounded-xl shadow-lg transition duration-300 ease-in-out transform hover:scale-105"
        >
          {walletAddress ? `Connected: ${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}` : 'Connect Wallet'}
        </button>
      </header>
      
      {/* Main content area, structured with a grid for responsiveness */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        {/* OrderBook component displays live market depth */}
        <OrderBook orderBook={orderBook} />
        {/* TradeForm component allows users to place buy/sell orders */}
        <TradeForm walletAddress={walletAddress} />
      </div>

      {/* Footer with copyright and version info */}
      <footer className="mt-12 text-center text-gray-500 text-sm">
        <p>&copy; {new Date().getFullYear()} Hybrid Trading Simulator. All rights reserved.</p>
        <p>Real-time data and blockchain integration for a dynamic trading experience.</p>
      </footer>
    </div>
  );
};

export default App;
