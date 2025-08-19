This manual will guide you through the process of running the Python script that generates a new Ethereum private key and public address.

-----

### **Prerequisites**

To run this script, you'll need **Python 3.6** or a newer version installed on your computer. You also need to install the necessary libraries, **Web3.py** and **eth-account**.

### **Step 1: Install the Required Libraries**

Open your terminal or command prompt and run the following command to install the required Python libraries. This command uses `pip`, Python's package installer, to download and set up the libraries.

```bash
pip install web3 eth-account
```

### **Step 2: Save the Script**

Copy the following code and save it in a file named `generate_key.py`.

```python
from web3 import Web3
from eth_account import Account

# This is a temporary measure to bypass a warning for this specific use case.
# It enables features that are not yet audited, which is fine for generating
# a new, random key pair for non-production use.
Account.enable_unaudited_hdwallet_features()

# Generate a new random private key.
# The `._private_key.hex()` part converts the private key object into a
# readable hexadecimal string.
private_key = Account.create()._private_key.hex()

# Derive the public address from the generated private key.
# This is the address you share with others to receive funds.
public_address = Account.from_key(private_key).address

# Print the results to the console.
print("New Testnet Private Key (Keep this secret!):")
print(private_key)
print("\nNew Testnet Public Address:")
print(public_address)
```

### **Step 3: Run the Script**

After saving the file, navigate to the directory where you saved it using your terminal or command prompt. Then, execute the script with the following command:

```bash
python generate_key.py
```

### **Step 4: View the Output**

Once the script runs, it will print two lines of text to your console:

1.  **New Testnet Private Key:** A long string of numbers and letters. **This is your secret key.** Anyone who has this key can access and control your funds on the blockchain. You should never share it with anyone or store it in an insecure location.
2.  **New Testnet Public Address:** A shorter string that starts with `0x`. This is your public address, similar to a bank account number. It is safe to share with others so they can send you cryptocurrency.

-----

### **Important Security Note**

This script generates a **testnet** key. While you can technically use it on the main Ethereum network, this method is primarily for testing and learning purposes. For any real funds, you should always use a reputable wallet service (like MetaMask, Ledger, or Trust Wallet) that follows industry-standard security practices for key generation and management.