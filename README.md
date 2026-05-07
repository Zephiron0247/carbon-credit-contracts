# Pranaq — Smart Contracts

Solidity smart contracts powering blockchain-based carbon credit issuance.

---

# Features

- ERC-20 carbon credit token
- Verification-linked minting
- Duplicate mint prevention
- Sepolia deployment

---

# Stack

- Solidity
- Hardhat
- OpenZeppelin
- Sepolia Testnet

---

# Contract

| Contract | Purpose |
|---|---|
| CarbonCredit.sol | Carbon credit token + issuance logic |

---

# Deploy

```bash
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network sepolia
