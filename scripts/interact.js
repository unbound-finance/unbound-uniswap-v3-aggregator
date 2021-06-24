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

  strategy = await ethers.getContractAt("UnboundStrategy", _strategy);
  aggregator = await ethers.getContractAt("V3Aggregator", _aggregator);
  pool = await ethers.getContractAt("UniswapV3Pool", _pool);

  token0 = await ethers.getContractAt("ERC20", _token0);
  token1 = await ethers.getContractAt("ERC20", _token1);

  const slot0 = await pool.slot0();

  console.log("currentTick", slot0.tick);

  const amountA = "3500000000000000000000";
  const amountB = "1000000000000000000";

  const newTickLower = calculateTick(0.0003333333333333333, 60);
  const newTickUpper = calculateTick(0.00025, 60);

  const ticks = await aggregator.getTicks(_strategy);
  const unused = await aggregator.unused(_strategy);
  const token0Real = await pool.token0();
  const shares = await aggregator.shares(_strategy, owner);
  const tvl = await aggregator.getAUM(_strategy);
  const token0Bal = await token0.balanceOf(owner);
  const token1Bal = await token1.balanceOf(owner);
  const burnedAmount0 = await aggregator.recentlyBurned0();
  const burnedAmount1 = await aggregator.recentlyBurned1();

  // console.log(ticks);

  // console.log("token0", await pool.token0());

  // await changeTicksAndRebalance(_strategy);

  console.log({
    burnedAmount0,
    burnedAmount1
  })

  console.log({
    shares,
    balance: {
      token0: token0Bal.toString(),
      token1: token1Bal.toString(),
    },
    unused: {
      amount0: unused.amount0.toString(),
      amount1: unused.amount1.toString(),
    },
    ticks: {
      amount0: ticks[0].amount0.toString(),
      amount1: ticks[0].amount1.toString(),
    },
    totalLiquidity: {
      amount0: (
        parseInt(unused.amount0) + parseInt(ticks[0].amount0)
      ).toString(),
      amount1: (
        parseInt(unused.amount1) + parseInt(ticks[0].amount1)
      ).toString(),
    },
    tvl: {
      amount0: tvl.amount0.toString(),
      amount1: tvl.amount1.toString(),
    },
    liquidityValue: (await pool.liquidity()).toString(),
    allTicks: ticks,
  });

  // await holdFund();
  // await changeTicksAndRebalance(_strategy);

  // console.log(tvl);

  // await changeTicksAndRebalance(_strategy);
  // await changeTicksAndRebalance(_strategy);

  // await changeTicksAndRebalance(_strategy);

  // await changeTicksAndRebalance(_strategy);
  // await changeTicksAndRebalance(_strategy);
  // await changeTicksAndRebalance(_strategy);
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

// async function swapAndRebalance(_strategy) {
//   const tx = await strategy.swapAndRebalance(
//     "0",
//     "100000",
//     "100000",
//     true,
//     [["278162800053839930000", "2370965592054314000000000", "78240", "82920"]]
//     // {
//     //   gasLimit: 10000000,
//     // }
//   );

//   console.log(tx);
// }

async function holdFund() {
  const tx = await strategy.holdFunds();
  console.log(tx);
}

async function changeTicksAndRebalance(_strategy) {
  // const tickLower = calculateTick(0.00025, 60);
  // const tickUpper = calculateTick(0.0003333333333333333, 60);

  // console.log({
  //   tickLower,
  //   tickUpper,
  // });

  // [15596.867398363842, 3.7415834221929125, -82920, -80040], [12276.52368152808, 0.591446184039982, -82140, -78240]
  const tx = await strategy.swapAndRebalance(
    toGwei(14.402835656046523),
    "1000000",
    "1000000",
    true,
    [[toGwei(22.10276257899523), toGwei(0.001627392823741774), -82920, -75960]],
    {
      gasLimit: 10000000,
    }
  );

  // const tx = await strategy.changeTicksAndRebalance(
  //   [
  //     [toGwei(6780.699), toGwei(0.69024), "-81720", "-81300"],
  //     [toGwei(0), toGwei(1.314),"-82920", "-81720"],
  //     [toGwei(2299.19), toGwei(0), "-78240", "-75960"],
  //   ],
  //   {
  //     gasLimit: 1000000,
  //   }
  // );

  // const tx = await strategy.swapAndRebalance(
  //   toGwei(1.6485258940457455),
  //   "100000",
  //   "100000",
  //   false,
  //   [
  //     [toGwei(11451.834060090392), toGwei(2.052605755715921), -82980, -79380],
  //   ]
  // );

  console.log(tx);
}

async function addLiquidity(_strategy) {
  const tx = await aggregator.addLiquidity(
    _strategy,
    "10000000000000000000000",
    "35000000000000000000000000",
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
