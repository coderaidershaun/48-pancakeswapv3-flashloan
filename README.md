## YOUTUBE EXACT CODE

If you are following the exact code from the YouTube series, you can get the code with exactly what is shown in that series here:

https://github.com/coderaidershaun/youtube-series-flashloan-bsc.git

## Step 1

Make sure node, ts-node and yarn are installed globally on your machine and download the githum package in whatever folder you like.

## Step 2 - Add .env

```shell
touch .env
```

Edit the .env file

```plaintext ./env
MAINNET_PROVIDER_URL=https://bsc-dataseed.binance.org
TESTNET_PROVIDER_URL=https://data-seed-prebsc-1-s1.binance.org:8545
PRIVATE_KEY=ENTER_YOUR_PRIVATE_KEY_PREFIXED_WITH_0x
```

## Step 3 - Install Exact Packages and Compile

```shell
yarn --exact
npx hardhat compile
```

## Step 4 - Test

```shell
npx hardhat test
```

You should now see a bunch of swaps and a green tick showing success.

## Step 5 - Deploy

In order to deploy to mainnet (WARNING: WILL COST GAS):

```shell
npx hardhat run scripts/deployFlash.ts --network mainnet
```

Or if you are deploying the simulation contract (this is useful for calling the previously deployed contract) to see gas used:

```shell
npx hardhat run scripts/deploySim.ts --network mainnet
```
