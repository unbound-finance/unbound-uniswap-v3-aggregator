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
    dai: '0x10DAF88Aef79FD82369A5f5c158FfC093a58021a',
    eth: '0xF77c21C32b03550EdcB3e1c92760544888094c5C',
    pool: '0xF2fA4A3915Bd00de50F1d250CD6CA578C4204cd6',
    strategy: '0xC9536BcC7AE571bDBCBcF6AB6eEF13D4153656C5',
    v3Aggregator: '0xBD15C17260C0D1b4a4e7b73F67A5871Be62A3AbC'
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
    "350000000000000000000000000",
    "100000000000000000000000000000000",
    "0",
    "0",
    "0"
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
