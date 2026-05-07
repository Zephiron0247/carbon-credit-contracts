require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

if (!process.env.PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY not found in .env file");
}

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },

  networks: {
    hardhat: {},
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
      chainId: 11155111
    }
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};