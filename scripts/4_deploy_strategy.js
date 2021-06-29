const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");

const config = require('./config');

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

async function main() {
  console.log("⭐  Deployment Started");

  const dai = await ethers.getContractAt("ERC20", config.dai);
  const eth = await ethers.getContractAt("ERC20", config.eth);

  const factory = await ethers.getContractAt(
    "StrategyFactory",
    config.strategyFactory
  );

  const pool = await ethers.getContractAt("UniswapV3Pool", config.pool);

  await factory.createStrategy(pool.address, config.owner);

  const index = await factory.total()

  const strategyAddress = await factory.strategyByIndex(parseInt(index));
  const strategy = await ethers.getContractAt(
    "DefiEdgeStrategy",
    strategyAddress
  );

  let tickUpper, tickLower;
  if (dai.address < eth.address) {
    // add initial liquidity to start the pool
    tickUpper = calculateTick(0.0003333333333333333, 60);
    tickLower = calculateTick(0.00025, 60);
  } else {
    // add initial liquidity to start the pool
    tickLower = calculateTick(3000, 60);
    tickUpper = calculateTick(4000, 60);
  }

  await strategy.initialize([[0, 0, tickLower, tickUpper]]);
  console.log("✅ strategy initialised");

  // console.log contract config
  console.log("🎉 Contracts Deployed");
  console.log({
    strategy: strategy.address,
  });

}

function encodePriceSqrt(reserve0, reserve1) {
  console.log("encoding");
  return BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  );
}

function calculateTick(price, tickSpacing) {
  const logTick = 46054 * Math.log10(Math.sqrt(price));
  return parseInt(logTick) + tickSpacing - (parseInt(logTick) % tickSpacing);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
