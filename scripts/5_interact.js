const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");


const config = require('./config');

let aggregator;
let pool;
let strategy;

async function main() {
  console.log("⭐  Deployment Started");

  aggregator = await ethers.getContractAt("Aggregator", config.aggregator);

  const dai = await ethers.getContractAt("ERC20", config.dai);
  const eth = await ethers.getContractAt("ERC20", config.eth);

  pool = await ethers.getContractAt("UniswapV3Pool", config.pool);

  strategy = await ethers.getContractAt(
    "DefiEdgeStrategy",
    "0xc628F1535efF40a9f2365854e1065601A15fe32E"
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

  //   await strategy.initialize([[0, 0, tickLower, tickUpper]]);
  //   console.log("✅ strategy initialised");

  await addLiquidity(strategy.address);

  // console.log contract config
  console.log("🎉 Contracts Deployed");
  console.log({
    strategy: strategy.address,
  });
}

async function hold(_strategy) {
//   const sqrtRatioX96 = (await pool.slot0()).sqrtPriceX96;
//   const sqrtPriceLimitX96 = sqrtRatioX96 - (sqrtRatioX96 * 10) / 100;

  const tx = await strategy.hold();

  console.log(tx);
}

async function rebalance(_strategy) {
  const sqrtRatioX96 = (await pool.slot0()).sqrtPriceX96;
  const sqrtPriceLimitX96 = sqrtRatioX96 - (sqrtRatioX96 * 10) / 100;

  const tx = await strategy.rebalance(
    toGwei(14.402835656046523),
    toGwei(sqrtPriceLimitX96 / 1e18),
    "1000000",
    true,
    [[toGwei(22.10276257899523), toGwei(0.001627392823741774), 75960, 82920]],
    {
      gasLimit: 10000000,
    }
  );

  console.log(tx);
}

async function addLiquidity(_strategy) {
  const tx = await aggregator.addLiquidity(
    _strategy,
    "350000000000000000000000",
    "100000000000000000000000000",
    "0",
    "0",
    "0",
    {
      gasLimit: 1000000,
    }
  );
  console.log(tx);
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

function toGwei(_number) {
  return (_number * 1e18).toLocaleString("fullwide", { useGrouping: false }); // returns "4000000000000000000000000000"
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
