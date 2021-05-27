
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");
const hre = require("hardhat");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

async function main() {
  const owner = "0x22CB224F9FA487dCE907135B57C779F1f32251D4";
  const strategy = "0x62D66Bc52691DD014fa13f42d0E0D99d5b8486c1";
  const aggregator = "0xBe357b43A7305F6E98D1C4A3ACAf05d14ceFd2ef";

  const TestStrategy = await ethers.getContractAt("TestStrategy", strategy);
  const v3Aggregator = await ethers.getContractAt("V3Aggregator", aggregator);
  const pool = await ethers.getContractAt(
    "UniswapV3Pool",
    "0xc9e64C21A1E0CE5bB4136B7dCB7ADD52612e3fDD"
  );

  const slot0 = await pool.slot0();

  console.log("currentTick", slot0.tick);

  const amountA = "3500000000000000000000";
  const amountB = "1000000000000000000";

    tickUpper = "-79980";
    tickLower = "-83220";

//   tickUpper = calculateTick(3000, 60);
//   tickLower = calculateTick(4000, 60);;

  console.log({
    tickLower,
    tickUpper,
  });

  await TestStrategy.changeTickLower(tickLower);
  await TestStrategy.changeTickUpper(tickUpper);

//   const tx = await v3Aggregator.rebalance(strategy, {
//       gasLimit: 1000000
//   });

  //   const tx = await v3Aggregator.addLiquidity(strategy, amountA, amountB, 0, 0, {
  //     gasLimit: 1000000,
  //   });

//   console.log(tx);

  // console.log contract addresses
  console.log("🎉  Interaction Complete");
}

async function changeTicks() {}

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
