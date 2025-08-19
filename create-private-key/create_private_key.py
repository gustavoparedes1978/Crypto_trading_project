from web3 import Web3
from eth_account import Account

# Disable user-friendly warnings
# This function is used to enable features that are not yet audited
# and are intended for specific use cases like generating new accounts
# from a mnemonic phrase.
Account.enable_unaudited_hdwallet_features()

# This generates a new private key and address
# `Account.create()` generates a new, random Ethereum account object.
# `._private_key.hex()` extracts the private key from the account object
# and converts it into a hexadecimal string. This is the secret key
# used to sign transactions.
private_key = Account.create()._private_key.hex()

# `Account.from_key(private_key)` recreates the account object using
# the private key.
# `.address` extracts the public address associated with that private key.
# This address is what you share with others to receive funds.
public_address = Account.from_key(private_key).address

# Print the generated private key and public address
# The private key should be kept secret as it controls the account.
print("New Testnet Private Key (Keep this secret!):")
print(private_key)

# The public address is safe to share.
print("\nNew Testnet Public Address:")
print(public_address)

