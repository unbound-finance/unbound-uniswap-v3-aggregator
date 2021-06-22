const { BigNumber, utils } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

// contracts
let strategy;
let aggregator;
let pool;
let dai;
let eth;
let tickLower;
let tickUpper;

async function main() {
  const owner = "0x22CB224F9FA487dCE907135B57C779F1f32251D4";
  const config = {
    dai: "0xB0E810B60813A61e8214E4d688cCB78e495Fc081",
    eth: "0x6E650Bf5216b8aFC84576061E22F5D7Ed3EA3bFE",
    pool: "0x23450701eA9F672cd8dF5796AAcD07a9c1d996bb",
    strategy: "0x6B28d8C72371d17C88709D3d517e5b2803F12C3f",
    v3Aggregator: "0x87B1EbCE964eAf8D65c51B3d96ff7bD27E5C4D0f",
  };

  const _strategy = config.strategy;
  const _aggregator = config.v3Aggregator;
  const _pool = config.pool;
  const _token0 = config.dai;
  const _token1 = config.eth;

  const TestStrategy = await ethers.getContractFactory("UnboundStrategy");

  aggregator = await ethers.getContractAt("V3Aggregator", _aggregator);
  pool = await ethers.getContractAt("UniswapV3Pool", _pool);

  dai = await ethers.getContractAt("ERC20", _token0);
  eth = await ethers.getContractAt("ERC20", _token1);

  const balanceOfDai = await dai.balanceOf(owner);
  const balanceOfEth = await dai.balanceOf(owner);

  await dai.approve(aggregator.address, balanceOfDai);
  await eth.approve(aggregator.address, balanceOfEth);

  if (dai.address < eth.address) {
    // add initial liquidity to start the pool
    tickUpper = calculateTick(0.0003333333333333333, 60);
    tickLower = calculateTick(0.00025, 60);
  } else {
    // add initial liquidity to start the pool
    tickLower = calculateTick(2500, 60);
    tickUpper = calculateTick(4500, 60);
  }

  // deploy strategy contract
  strategy = await TestStrategy.deploy(aggregator.address, pool.address, owner);

  await strategy.initialize([[0, 0, tickLower, tickUpper]]);

  await addLiquidity(strategy.address);

  console.log("🎉  Interaction Complete");
  console.log("New Strategy Address", strategy.address);
}

async function addLiquidity(_strategy) {
  const tx = await aggregator.addLiquidity(
    _strategy,
    "3500000000000000000000000",
    "1000000000000000000000000000000",
    "0",
    "0",
    "0",
    {
      gasLimit: 10000000,
    }
  );
  console.log(tx);
}

async function removeLiquidity(_strategy) {
  const tx = await aggregator.removeLiquidity(
    _strategy,
    "875000000000000000000",
    "0",
    "0"
  );
  console.log(tx);
}

function getPositionKey(address, lowerTick, upperTick) {
  return utils.keccak256(
    utils.solidityPack(
      ["address", "int24", "int24"],
      [address, lowerTick, upperTick]
    )
  );
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
