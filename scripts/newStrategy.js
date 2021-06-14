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
  const _strategy = "0xB010FA36E4994735f2b8E8c6705f31DD0C7EF0B1";
  const _aggregator = "0xF321056d79b919eE1aA6084495C5A37a29aad06B";
  const _pool = "0x5A12f0272d2D5f44778e2fcB14Dc0439D4B7b688";
  const _token0 = "0xd5B8557F2fb5A589b65F628698Ee346897750264";
  const _token1 = "0x90897fc7AB659b23881f7E97e54D181229C008E6";

  const TestStrategy = await ethers.getContractFactory("TestStrategy");

  aggregator = await ethers.getContractAt("V3Aggregator", _aggregator);
  pool = await ethers.getContractAt("UniswapV3Pool", _pool);

  dai = await ethers.getContractAt("ERC20", _token0);
  eth = await ethers.getContractAt("ERC20", _token1);

  if (dai.address < eth.address) {

    // add initial liquidity to start the pool
    tickUpper = calculateTick(0.0003333333333333333, 60);
    tickLower = calculateTick(0.00025, 60);
  } else {
    // add initial liquidity to start the pool
    tickLower = calculateTick(3000, 60);
    tickUpper = calculateTick(4000, 60);
  }

  strategy = await TestStrategy.deploy(
    // deploy strategy contract
    tickLower,
    tickUpper,
    0,
    0,
    _pool,
    "0",
    owner,
    aggregator.address
  );

  await addLiquidity(strategy.address);

  console.log("🎉  Interaction Complete");
  console.log("New Strategy Address", strategy.address)
}

async function addLiquidity(_strategy) {
  const tx = await aggregator.addLiquidity(
    _strategy,
    "3500000000000000000000",
    "10000000000000000000000000000000",
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

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
