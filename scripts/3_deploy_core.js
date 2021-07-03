const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");

const config = require("./config");

async function main() {

  const addresses = {
    owner: "0x22CB224F9FA487dCE907135B57C779F1f32251D4"
  }

  const Aggregator = await ethers.getContractFactory("Aggregator");
  const StrategyFactory = await ethers.getContractFactory("StrategyFactory");

  // deploy aggregator contract
  const aggregator = await Aggregator.deploy(addresses.owner);
  console.log("✅ aggregator deployed");
  const factory = await StrategyFactory.deploy(aggregator.address);
  await aggregator.addFactory(factory.address);

  // console.log contract addresses
  console.log("🎉 Contracts Deployed");
  console.log({
    aggregator: aggregator.address,
    strategyFactory: factory.address,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
