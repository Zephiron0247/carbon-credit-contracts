const hre = require("hardhat");

async function main() {
  console.log("Deploying CarbonCredit contract to Polygon Amoy...");

  // Get the deployer wallet from hardhat config (reads from .env)
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with wallet:", deployer.address);

  // Check balance before deploying
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Wallet balance:", hre.ethers.formatEther(balance), "MATIC");

  // Compile and deploy the contract
  const CarbonCredit = await hre.ethers.getContractFactory("CarbonCredit");
  const contract = await CarbonCredit.deploy();

  // Wait for deployment to be confirmed on-chain
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  console.log("CarbonCredit deployed to:", contractAddress);
  console.log("Save this address — you need it for the FastAPI backend");
  console.log("Polygonscan:", `https://amoy.polygonscan.com/address/${contractAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });