import { ethers } from "hardhat";

/// For mainnet: npx hardhat run scripts/deploySim.ts --network mainnet
/// Ensure that deployFlash.ts file is executed first.
/// DEPLOYED CONTRACT ADDRESS:
async function main() {
  const FLASHLOAN_CONTRACT = ""; // ENTER DEPLOYED CONTRACT ADDRESS FOR FLASHLOAN CONTRACT HERE
  const [deployer] = await ethers.getSigners();
  console.log(
    "Signer Account balance:",
    (await deployer.getBalance()).toString()
  );
  const Simulation = await ethers.getContractFactory("SimulateFlash");
  const simulation = await Simulation.deploy(FLASHLOAN_CONTRACT);
  console.log("Contract address:", simulation.address);
  await simulation.deployed();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
