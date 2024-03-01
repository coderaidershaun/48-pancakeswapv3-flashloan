import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, network } from "hardhat";

// Run 'npx hardhat compile' for this to import
import { abi as abiFlashLoan } from "../artifacts/contracts/FlashLoan.sol/FlashLoan.json";

// Whale Setup
// https://bscscan.com/token/0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56#balances
const WHALE_ADDR_BUSD = "0x7e4390281401fC8da0DC5E8641307B8585D65732";

// ONLY USE IF ALREADY DEPLOYED - otherwise make blank
const FLASH_CONTRACT = "";

// Tokens
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

// Other
const exchRoute = [1, 0, 0];
const v3Fee = 500;
const path = [CAKE, WBNB];
const payContractAmount = "50";

// Token Selection
const BORROW_TOKEN_BUSD = BUSD;

describe("BinanceFlashloanPancakeswapV3", function () {
  async function create_whale() {
    // connect to local forked test network (i.e. do not use getDefaultProvider)
    const provider = ethers.provider;

    // Ensure BNB balance not zero (for making transactions)
    const whaleBalance = await provider.getBalance(WHALE_ADDR_BUSD);
    expect(whaleBalance).not.equal("0");

    // Impersonate WETH Account
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WHALE_ADDR_BUSD],
    });
    const whaleWallet = ethers.provider.getSigner(WHALE_ADDR_BUSD);
    expect(await whaleWallet.getBalance()).not.equal("0");

    // Ensure USDT balance
    const abi = [
      "function balanceOf(address _owner) view returns (uint256 balance)",
    ];
    const contractBusd = new ethers.Contract(BORROW_TOKEN_BUSD, abi, provider);
    const balanceBusd = await contractBusd.balanceOf(WHALE_ADDR_BUSD);
    if (balanceBusd == "0") {
      console.log("Looks like the whale wallet balance has moved to zero.");
      console.log(
        `Try replacing the WHALE Wallet address above named as WHALE_ADDR_BUSD in the test/flashloantest.ts file on line 10, with another one at https://bscscan.com/token/0xe9e7cea3dedca5984780bafc599bd69add087d56#balances`
      );
    }
    expect(balanceBusd).not.equal("0");

    // Return whale wallet
    return { whaleWallet };
  }

  describe("Deployment", function () {
    it("Should perform a FlashLoan using Uniswap V3", async function () {
      // Impersonate a BUSD whale
      let { whaleWallet } = await loadFixture(create_whale);

      // Deploy contract
      const FlashLoan = await ethers.getContractFactory("FlashLoan");
      let flashloan = await FlashLoan.deploy(WBNB, BUSD, 500); // 500 = Pool Fee
      await flashloan.deployed();
      console.log("FlashLoan Contract Deployed: \t", flashloan.address);

      // Decide whether to use Live or newly deployed contract
      let flashAddress =
        FLASH_CONTRACT.length > 0 ? FLASH_CONTRACT : flashloan.address;

      // Send some BUSD to the smart contract
      // This ensures the FlashLoan will always be paid back in full
      let usdtAmt = ethers.utils.parseUnits(payContractAmount, 18);
      const abi = [
        "function transfer(address _to, uint256 _value) public returns (bool success)",
        "function balanceOf(address _owner) view returns (uint256 balance)",
      ];
      const contractUsdt = new ethers.Contract(
        BORROW_TOKEN_BUSD,
        abi,
        whaleWallet
      );
      const txTferUsdt = await contractUsdt.transfer(flashAddress, usdtAmt);
      const receiptTxUsdt = await txTferUsdt.wait();
      expect(receiptTxUsdt.status).to.eql(1);

      // Print starting BUSD balance
      let contractBalUsdt = await contractUsdt.balanceOf(flashloan.address);
      console.log("Flash Contract BUSD: \t\t", contractBalUsdt);

      // Print starting BUSD balance
      let whaleBalUsdt = await contractUsdt.balanceOf(whaleWallet._address);
      console.log("Wallet BUSD: \t\t\t", whaleBalUsdt);

      // Initialize flash loan parameters
      const amountBorrow = ethers.utils.parseUnits("30", 18); // BUSD
      const tokenPath = path;
      const routing = exchRoute; // [0] = Uniswap V2, [1] = Uniswap V3
      const feeV3 = v3Fee; // 100, 500, 3000 or 10000 (selected lowest fee due to arb nature)

      // Connect Flashloan Contract
      const contractFlashLoan = new ethers.Contract(
        flashAddress,
        abiFlashLoan,
        whaleWallet
      );

      // Send Flashloan Transaction
      const txFlashLoan = await contractFlashLoan.flashloanRequest(
        tokenPath,
        0, // BorrowBUSD (see constructor)
        amountBorrow, // BorrowWBNB (see constructor)
        feeV3,
        routing
      );

      // Show Results
      const txFlashLoanReceipt = await txFlashLoan.wait();
      expect(txFlashLoanReceipt.status).to.eql(1);

      // Print closing BUSD balance
      whaleBalUsdt = await contractUsdt.balanceOf(whaleWallet._address);
      console.log("");
      console.log("Wallet BUSD: ", whaleBalUsdt);
    });
  });
});
