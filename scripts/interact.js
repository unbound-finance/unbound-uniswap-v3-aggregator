const { BigNumber, utils } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

// contracts
let strategy;
let aggregator;
let pool;
let token0;
let token1;

async function main() {
  const owner = "0x22CB224F9FA487dCE907135B57C779F1f32251D4";
  const _strategy = "0x264A140E9B19c1174aaA77C923b2Cb0Ac90B736a";
  const _aggregator = "0xF321056d79b919eE1aA6084495C5A37a29aad06B";
  const _pool = "0x5A12f0272d2D5f44778e2fcB14Dc0439D4B7b688";
  const _token0 = "0xBf20a11bD3d13D643954a907d03512AC6E8893Ac";
  const _token1 = "0x760A5D9072FFf27F488a6785F23a6ad2abB3525a";

  strategy = await ethers.getContractAt("TestStrategy", _strategy);
  aggregator = await ethers.getContractAt("V3Aggregator", _aggregator);
  pool = await ethers.getContractAt("UniswapV3Pool", _pool);

  token0 = await ethers.getContractAt("ERC20", _token0);
  token1 = await ethers.getContractAt("ERC20", _token1);

  const slot0 = await pool.slot0();

  console.log("currentTick", slot0.tick);

  const amountA = "3500000000000000000000";
  const amountB = "1000000000000000000";

  const tickLower = await strategy.tickLower();
  const tickUpper = await strategy.tickUpper();

  const newTickLower = calculateTick(0.0003333333333333333, 60);
  const newTickUpper = calculateTick(0.00025, 60);

  const getStrategy = await aggregator.strategies(_strategy);
  const unused = await aggregator.unused(_strategy);
  const token0Real = await pool.token0();
  const shares = await aggregator.shares(_strategy, owner);
  console.log(token0Real);

  console.log("token0", await pool.token0())

  console.log({ shares, unused: unused, getStrategy: getStrategy });
  
  await addLiquidity(_strategy);
  // await removeLiquidity(_strategy);
  // const shares = await aggregator.shares(_strategy, owner);
  // const unused = await aggregator.unused(_strategy);
  // const totalShares = await aggregator.totalShares(_strategy)

  // console.log({
  //   amount0: getStrategy.amount0.toString(),
  //   amount1: getStrategy.amount1.toString(),
  //   totalShares: totalShares.toString()
  // })

  // await token0.approve(_aggregator, "10000000000000000000000000000000")
  // await token1.approve(_aggregator, "10000000000000000000000000000000")

  // const added = await addLiquidity(_strategy)
  // const removed = await removeLiquidity(_strategy)

  // console.log({
  //   added: added.hash,
  //   removed: removed.hash
  // })
  // await removeLiquidity(_strategy);

  // console.log({ getStrategy, shares, unused, totalShares });

  // await aggregator.rebalance(_strategy);

  // await addLiquidity(_strategy);

  //  await strategy.changeTicks(
  //     newTickUpper,
  //     newTickLower,
  //     0,
  //     0,
  //     0
  //   );

  // await addLiquidity(_strategy);

  // console.log(changeStrategy);

  console.log(slot0);

  //   tickUpper = calculateTick(3000, 60);
  //   tickLower = calculateTick(4000, 60);;

  console.log({
    tickLower,
    tickUpper,
  });

  // const tx = await aggregator.addLiquidity(
  //   strategy,
  //   "3500000000000000000000",
  //   "1000000000000000000",
  //   "0",
  //   "0"
  // )

  // console.log(tx);

  // await strategy.changeTickLower(tickLower);
  // await strategy.changeTickUpper(tickUpper);

  //   const tx = await aggregator.rebalance(strategy, {
  //       gasLimit: 1000000
  //   });

  //   const tx = await aggregator.addLiquidity(strategy, amountA, amountB, 0, 0, {
  //     gasLimit: 1000000,
  //   });

  //   console.log(tx);

  // console.log contract addresses
  console.log("🎉  Interaction Complete");
}

async function addLiquidity(_strategy) {
  const tx = await aggregator.addLiquidity(
    _strategy,
    "3500000000000000000000",
    "1000000000000000000",
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
    "0",
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
