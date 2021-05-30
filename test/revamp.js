const { expect } = require("chai");

const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

// TODOs
// Add liquidity from 3 user accounts and check share wise
// Gas costs for providing liquidity, rebalance and remove liquidity
// Rebalance with new range orders
// Rebalance with swap
// Rebalance with hold
// Burn liquidity: Full
// Remove liquidiy from user point of view, remove from limit, range and unused
// Pachapute's formula testing

let factory;
let v3Aggregator;
let token0;
let token1;
let pool;
let strategy;
let owner;
let userA;
let userB;
let userC;
let tickLower;
let tickUpper;
let secondaryTickLower;
let secondaryTickUpper;
let TestStrategy;

const amountB = "200000000000000000000000";
const amountA = "100000000000000000000";

beforeEach(async function () {
  [owner, userA, userB, userC] = await ethers.getSigners();

  const TickMath = await ethers.getContractFactory(
    "contracts/test/core/libraries/TickMath.sol:TickMath"
  );

  const tickMath = await TickMath.deploy();

  const Factory = await ethers.getContractFactory("UniswapV3Factory", {
    libraries: {
      TickMath: tickMath.address,
    },
  });

  factory = await Factory.deploy();

  // create a pool

  const TestToken = await ethers.getContractFactory("ERC20");
  TestStrategy = await ethers.getContractFactory("TestStrategy");
  const V3Aggregator = await ethers.getContractFactory("V3Aggregator");

  v3Aggregator = await V3Aggregator.deploy(owner.address);

  // deployments
  const testToken0 = await TestToken.deploy(
    "Test Token 0",
    "TST0",
    18,
    "100000000000000000000000000000",
    owner.address
  );

  const testToken1 = await TestToken.deploy(
    "Test Token 1",
    "TST1",
    18,
    "100000000000000000000000000000",
    owner.address
  );

  // trasfer tokens to userA
  testToken0.transfer(userA.address, "3333333333000000000000000000");
  testToken1.transfer(userA.address, "3333333333000000000000000000");

  // transfer tokens to userB
  testToken0.transfer(userB.address, "3333333333000000000000000000");
  testToken1.transfer(userB.address, "3333333333000000000000000000");

  // transfer tokens to userC
  testToken0.transfer(userC.address, "3333333333000000000000000000");
  testToken1.transfer(userC.address, "3333333333000000000000000000");

  await factory.createPool(testToken0.address, testToken1.address, "3000");

  // initialize the pool
  const poolAddress = await factory.getPool(
    testToken0.address,
    testToken1.address,
    "3000"
  );

  pool = await ethers.getContractAt("UniswapV3Pool", poolAddress);

  // add initial liquidity to start the pool
  tickLower = calculateTick(2800, 60);
  tickUpper = calculateTick(3500, 60);

  secondaryTickLower = calculateTick(3500, 60);
  secondaryTickUpper = calculateTick(4000, 60);

  // console.log(getPriceFromTick(tickLower));
  // console.log(getPriceFromTick(tickUpper));

  // deploy strategy contract
  strategy = await TestStrategy.deploy(
    tickLower,
    tickUpper,
    secondaryTickLower,
    secondaryTickUpper,
    pool.address,
    "0"
  );

  let reserve0, reserve1;
  let ethAddress, daiAddress;

  // set reserves at ETH price of 3000 DAI per ETh
  const initialEthReserve = "33333333333333330000";
  const initialDaiReserve = "100000000000000000000000";

  reserve0 = initialEthReserve;
  reserve1 = initialDaiReserve;

  const sqrtPriceX96 = encodePriceSqrt(reserve0, reserve1);
  await pool.initialize(sqrtPriceX96);

  const token0AddressFromPool = await pool.token0();

  if (token0AddressFromPool.toLowerCase() == testToken0.address.toLowerCase()) {
    token0 = testToken0;
    token1 = testToken1;
  } else {
    token1 = testToken0;
    token0 = testToken1;
  }

  // deploy strategy contract
  const demoStrategy = await TestStrategy.deploy(
    tickLower,
    tickUpper,
    secondaryTickLower,
    secondaryTickUpper,
    pool.address,
    "0"
  );

  const balanceOf0 = await token0.balanceOf(owner.address);
  const balanceOf1 = await token1.balanceOf(owner.address);

  await token0.approve(v3Aggregator.address, balanceOf0);
  await token1.approve(v3Aggregator.address, balanceOf1);

  // add some liquidity to the pool
  await v3Aggregator.addLiquidity(
    demoStrategy.address,
    initialEthReserve,
    initialDaiReserve,
    "0",
    "0"
  );
});

// 2nd
// Simulate bolingers band on loop

describe("V3Aggregator", function () {
  // starts of tests
  it("Should add liquidity from 3 different accounts", async function () {
    await token0
      .connect(userA)
      .approve(v3Aggregator.address, "3333333333000000000000000000");
    await token1
      .connect(userA)
      .approve(v3Aggregator.address, "3333333333000000000000000000");

    await token0
      .connect(userB)
      .approve(v3Aggregator.address, "3333333333000000000000000000");
    await token1
      .connect(userB)
      .approve(v3Aggregator.address, "3333333333000000000000000000");

    await token0
      .connect(userC)
      .approve(v3Aggregator.address, "3333333333000000000000000000");
    await token1
      .connect(userC)
      .approve(v3Aggregator.address, "3333333333000000000000000000");

    // add liquidity from 3 accounts and check if all of them are getting right amount of shares
    await v3Aggregator
      .connect(userA)
      .addLiquidity(
        strategy.address,
        "10000000000000000000000",
        "10000000000000000000000",
        "0",
        "0"
      );

    await v3Aggregator
      .connect(userB)
      .addLiquidity(
        strategy.address,
        "10000000000000000000000",
        "10000000000000000000000",
        "0",
        "0"
      );

    const tx = await v3Aggregator
      .connect(userC)
      .addLiquidity(
        strategy.address,
        "10000000000000000000000",
        "10000000000000000000000",
        "0",
        "0"
      );

    const sharesOfA = await v3Aggregator.shares(
      strategy.address,
      userA.address
    );
    const sharesOfB = await v3Aggregator.shares(
      strategy.address,
      userB.address
    );
    const sharesOfC = await v3Aggregator.shares(
      strategy.address,
      userC.address
    );

    expect(parseInt(sharesOfA)).to.equal(1000);
    expect(parseInt(sharesOfB)).to.equal(1000);
    expect(parseInt(sharesOfC)).to.equal(1000);
  });

  it("Should rebalance using new ranges", async function () {
    // add liquidity
    await v3Aggregator.addLiquidity(
      strategy.address,
      "10000000000000000000000",
      "10000000000000000000000",
      "0",
      "0"
    );

    // calculate new ticks
    const newTickLower = calculateTick(2100, 60);
    const newTickUpper = calculateTick(3100, 60);

    // calculate new secondary ticks
    const newSecondaryTickLower = 0;
    const newSecondaryTickUpper = 0;

    // add primary and secondary ticks
    await strategy.changeTicks(
      newTickLower,
      newTickUpper,
      newSecondaryTickLower,
      newSecondaryTickUpper,
      0
    );

    // rebalance the pool
    await v3Aggregator.rebalance(strategy.address);

    const unused = await v3Aggregator.unused(strategy.address);

    const balanceOfContractInToken0 = await token0.balanceOf(
      v3Aggregator.address
    );
    const balanceOfContractInToken1 = await token1.balanceOf(
      v3Aggregator.address
    );

    expect(parseInt(unused.amount0)).to.equal(
      parseInt(balanceOfContractInToken0)
    );
    expect(parseInt(unused.amount1)).to.equal(
      parseInt(balanceOfContractInToken1)
    );
  });

  it("Should rebalance using range and limit orders", async function () {
    // Add liquidity, rebalance and calculate
    await v3Aggregator.addLiquidity(
      strategy.address,
      "10000000000000000000000",
      "10000000000000000000000",
      "0",
      "0"
    );

    // calculate new ticks
    const newTickLower = calculateTick(2900, 60);
    const newTickUpper = calculateTick(3100, 60);

    // calculate new secondary ticks
    const newSecondaryTickLower = calculateTick(3100, 60);
    const newSecondaryTickUpper = calculateTick(4000, 60);

    // add primary and secondary ticks
    strategy.changeTicks(
      newTickLower,
      newTickUpper,
      newSecondaryTickLower,
      newSecondaryTickUpper,
      0
    );

    // rebalance the pool
    await v3Aggregator.rebalance(strategy.address);

    const balanceOfContractInToken0 = await token0.balanceOf(
      v3Aggregator.address
    );
    const balanceOfContractInToken1 = await token1.balanceOf(
      v3Aggregator.address
    );

    expect(parseInt(balanceOfContractInToken0)).to.equal(0);
    expect(parseInt(balanceOfContractInToken1)).to.equal(406);
  });

  it("Should remove and hold liquidity", async function () {
    // balance of user before adding liquidity
    const balanceOfUserBeforeInToken0 = await token0.balanceOf(owner.address);
    const balanceOfUserBeforeInToken1 = await token1.balanceOf(owner.address);

    const secondStrategy = await TestStrategy.deploy(
      tickLower,
      tickUpper,
      secondaryTickLower,
      secondaryTickUpper,
      pool.address,
      "0"
    );

    // add liquidity
    await v3Aggregator.addLiquidity(
      secondStrategy.address,
      "10000000000000000000000",
      "10000000000000000000000",
      "0",
      "0"
    );

    // balance of user after adding liquidity
    const balanceOfUserAfterInToken0 = await token0.balanceOf(owner.address);
    const balanceOfUserAfterInToken1 = await token1.balanceOf(owner.address);

    const differenceToken0 =
      balanceOfUserBeforeInToken0 - balanceOfUserAfterInToken0;
    const differenceToken1 =
      balanceOfUserBeforeInToken1 - balanceOfUserAfterInToken1;

    // add primary and secondary ticks
    await secondStrategy.holdFunds();

    // rebalance the pool
    await v3Aggregator.rebalance(secondStrategy.address);

    const balanceOfAggregatorAfterInToken0 = await token0.balanceOf(
      v3Aggregator.address
    );
    const balanceOfAggregatorAfterInToken1 = await token1.balanceOf(
      v3Aggregator.address
    );
    // check if unused balances are equal to balances
    const unused = await v3Aggregator.unused(strategy.address);

    // console.log({
    //   balanceOfUserAfterInToken0: balanceOfUserAfterInToken0.toString(),
    //   balanceOfUserAfterInToken1: balanceOfUserAfterInToken0.toString(),
    //   balanceOfAggregatorAfterInToken0:
    //     balanceOfAggregatorAfterInToken0.toString(),
    //   balanceOfAggregatorAfterInToken1:
    //     balanceOfAggregatorAfterInToken1.toString(),
    //   differenceToken0: differenceToken0.toString(),
    //   differenceToken1: differenceToken1.toString(),
    //   unusedToken0: unused.amount0.toString(),
    //   unusedToken1: unused.amount1.toString(),
    // });

    expect(parseInt(balanceOfAggregatorAfterInToken0)).to.be.closeTo(
      parseInt(balanceOfAggregatorAfterInToken0),
      parseInt(differenceToken0)
    );
    expect(parseInt(balanceOfAggregatorAfterInToken1)).to.be.closeTo(
      parseInt(balanceOfAggregatorAfterInToken1),
      parseInt(differenceToken1)
    );
  });

  it("Should swap and rebalance", async function () {
    // add liquidity
    // Add liquidity, rebalance and calculate
    await v3Aggregator.addLiquidity(
      strategy.address,
      "10000000000000000000000",
      "10000000000000000000000",
      "0",
      "0"
    );

    // calculate new ticks
    const newTickLower = calculateTick(2800, 60);
    const newTickUpper = calculateTick(3200, 60);

    // add primary and secondary ticks
    await strategy.changeTicks(newTickLower, newTickUpper, 0, 0, 0);

    await v3Aggregator.rebalance(strategy.address);

    // await strategy.swapFunds(
    //   newTickLower,
    //   newTickUpper,
    //   "1000000000000000000",
    //   "10",
    //   true
    // );

    // await v3Aggregator.rebalance(strategy.address);

    const unused = await v3Aggregator.unused(strategy.address);

    // console.log({
    //   unusedAmount0: unused.amount0.toString(),
    //   unusedAmount1: unused.amount1.toString(),
    // });

    const balanceOfAggregatorAfterInToken0 = await token0.balanceOf(
      v3Aggregator.address
    );
    const balanceOfAggregatorAfterInToken1 = await token1.balanceOf(
      v3Aggregator.address
    );

    const swapAmt = calculateSwapAmount(
      newTickLower,
      newTickUpper,
      parseInt(balanceOfAggregatorAfterInToken0) / 1e18,
      0,
      0.3
    );
    // console.log("swapAmount", swapAmt);

    // console.log({
    //   balanceOfAggregatorBeforeInToken0:
    //     balanceOfAggregatorBeforeInToken0.toString(),
    //   balanceOfAggregatorBeforeInToken1:
    //     balanceOfAggregatorBeforeInToken1.toString(),
    //   balanceOfAggregatorAfterInToken0:
    //     balanceOfAggregatorAfterInToken0.toString(),
    //   balanceOfAggregatorAfterInToken1:
    //     balanceOfAggregatorAfterInToken1.toString(),
    // });
  });

  it("Should remove liquidity successfully", async function () {
    await token0
      .connect(userA)
      .approve(v3Aggregator.address, "3333333333000000000000000000");
    await token1
      .connect(userA)
      .approve(v3Aggregator.address, "3333333333000000000000000000");

    // balance of user after adding liquidity
    const balanceOfUserBeforeInToken0 = await token0
      .connect(userA)
      .balanceOf(userA.address);
    const balanceOfUserBeforeInToken1 = await token1
      .connect(userA)
      .balanceOf(userA.address);

    await v3Aggregator
      .connect(userA)
      .addLiquidity(
        strategy.address,
        "10000000000000000000000",
        "10000000000000000000000",
        "0",
        "0"
      );

    // calculate new ticks
    const newTickLower = calculateTick(2800, 60);
    const newTickUpper = calculateTick(3200, 60);

    // add primary and secondary ticks
    await strategy.changeTicks(newTickLower, newTickUpper, 0, 0, 0);

    // rebalance the pool
    await v3Aggregator.rebalance(strategy.address);

    // get shares
    const shares = await v3Aggregator.shares(strategy.address, userA.address);

    // remove liquidity
    await v3Aggregator
      .connect(userA)
      .removeLiquidity(strategy.address, shares, 0, 0);

          // balance of user after adding liquidity
    const balanceOfUserAfterInToken0 = await token0.balanceOf(userA.address);
    const balanceOfUserAfterInToken1 = await token1.balanceOf(userA.address);

    // console.log({
    //   shares: shares.toString(),
    //   balanceOfUserBeforeInToken0: balanceOfUserBeforeInToken0.toString(),
    //   balanceOfUserBeforeInToken1: balanceOfUserBeforeInToken1.toString(),
    //   balanceOfUserAfterInToken0: balanceOfUserAfterInToken0.toString(),
    //   balanceOfUserAfterInToken1: balanceOfUserAfterInToken1.toString()
    // });

    expect(parseInt(balanceOfUserBeforeInToken0)).to.equal(parseInt(balanceOfUserAfterInToken0));
    expect(parseInt(balanceOfUserBeforeInToken1)).to.equal(parseInt(balanceOfUserAfterInToken1));

  });
});

function calculateSwapAmount(_tickLower, _tickUpper, _amount0, _amount1, _fee) {
  const currentPrice = 3000;
  const range0 = 1.0001 ** _tickLower;
  const range1 = 1.0001 ** _tickUpper;
  const fee = _fee;
  const sqrtP = Math.sqrt(currentPrice);
  const ratio =
    (sqrtP * (sqrtP - range0)) / (1 - Math.sqrt(currentPrice / range1));

  // console.log({
  //   currentPrice,
  //   range0,
  //   range1,
  //   fee,
  //   sqrtP,
  //   ratio,
  //   _amount0,
  //   _amount1,
  // });

  let sellAmt;

  if (_amount1 < ratio) {
    // sell ETH
    sellAmt = (ratio * _amount0 - _amount1) / ratio + currentPrice * (1 - fee);
  } else {
    sellAmt =
      (_amount1 - ratio * _amount0) / 1 + (ratio / currentPrice) * (1 - fee);
  }

  // console.log("sellAmount", sellAmt);
}

function encodePriceSqrt(reserve0, reserve1) {
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

function expandTo18Decimals(number) {
  return BigNumber.from(number).mul(BigNumber.from(10).pow(18));
}

function getPriceFromTick(tick) {
  return 1.0001 ** tick;
}
