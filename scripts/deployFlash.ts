import { ethers } from "hardhat";

/// For mainnet: npx hardhat run scripts/deployFlash.ts --network mainnet
/// DEPLOYED CONTRACT ADDRESS:
async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerBalance = (await deployer.getBalance()).toString();
  console.log("Signer Account balance:", deployerBalance);

  const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
  const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
  const FlashLoan = await ethers.getContractFactory("FlashLoan");
  const flashloan = await FlashLoan.deploy(WBNB, BUSD, 500); // 500 = Pool Fee
  await flashloan.deployed();
  console.log("FlashLoan Contract Deployed: \t", flashloan.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
