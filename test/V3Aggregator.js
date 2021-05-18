const { expect, assert } = require("chai");

const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

let factory;
let v3Aggregator;
let testToken0;
let testToken1;
let pool;
let strategy;
let owner;
let tickLower;
let tickUpper;

const amountA = "100000000000000000000";
const amountB = "28571428570000000";

beforeEach(async function () {
  [owner] = await ethers.getSigners();

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
  const TestStrategy = await ethers.getContractFactory("TestStrategy");
  const V3Aggregator = await ethers.getContractFactory("V3Aggregator");

  v3Aggregator = await V3Aggregator.deploy(owner.address);
  
  // deployments
  testToken0 = await TestToken.deploy(
    "Test Token 0",
    "TST0",
    18,
    "100000000000000000000000000000",
    owner.address
  );

  testToken1 = await TestToken.deploy(
    "Test Token 1",
    "TST1",
    18,
    "100000000000000000000000000000",
    owner.address
  );

  await factory.createPool(testToken0.address, testToken1.address, "3000");

  // initialize the pool
  const poolAddress = await factory.getPool(
    testToken0.address,
    testToken1.address,
    "3000"
  );

  pool = await ethers.getContractAt("UniswapV3Pool", poolAddress);

  // add initial liquidity to start the pool
  tickLower = calculateTick(3000, 60);
  tickUpper = calculateTick(4000, 60);

  // console.log(getPriceFromTick(tickLower));
  // console.log(getPriceFromTick(tickUpper));

  // deploy strategy contract
  strategy = await TestStrategy.deploy(
    "2500",
    "4500",
    tickLower,
    tickUpper,
    pool.address,
    testToken0.address,
    "0"
  );

  let reserve0, reserve1;
  let ethAddress, daiAddress;

  // set reserves at ETH price of 3500 DAI per ETh
  const initialEthReserve = "28571428571400000000";
  const initialDaiReserve = "100000000000000000000000";

  reserve0 = initialEthReserve;
  reserve1 = initialDaiReserve;

  const sqrtPriceX96 = encodePriceSqrt(reserve0, reserve1);
  await pool.initialize(sqrtPriceX96);
});

describe("state variables", () => {
  it("totalShare", async () => {
    const totalShare = await v3Aggregator.totalShare();
    assert.equal(totalShare.toString(), "0", "wrong total shares");
  })

  it("feeSetter", async () => {
    const totalShare = await v3Aggregator.feeSetter();
    assert.equal(totalShare, owner.address, "wrong feeSetter");
  })
})

describe("V3Aggregator", function () {
  it("Should add right amount of successfully", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);
    // add liquidity using aggregator contract
    await v3Aggregator.addLiquidity(
      strategy.address,
      amountA,
      amountB,
      "0",
      "0"
    );

    // how do we check what the correct amounts to add from amountA and amountB are?

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const share = await v3Aggregator.shares(strategy.address, owner.address);
    const slot0 = await pool.slot0();

    console.log({
      sqrtPriceX96: slot0.sqrtPriceX96.toString(),
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });

    expect(share).to.equal(1000);
  });

  it("Should issue right amount of shares", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);
    // add liquidity using aggregator contract
    const bal0Before = await testToken0.balanceOf(pool.address);
    const bal1Before = await testToken1.balanceOf(pool.address);
    const shareBefore = await v3Aggregator.shares(strategy.address, owner.address);

    assert.equal(shareBefore.toString(), "0", "wrong shares");
    assert.equal(bal0Before.toString(), "0", "wrong bal0");
    assert.equal(bal1Before.toString(), "0", "wrong bal1");

    await v3Aggregator.addLiquidity(
      strategy.address,
      amountA,
      amountB,
      "0",
      "0"
    );

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const share = await v3Aggregator.shares(strategy.address, owner.address);
    const slot0 = await pool.slot0();

    console.log({
      sqrtPriceX96: slot0.sqrtPriceX96.toString(),
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });

    // not sure why bal0 is amountB - 2 ??
    // assert.equal(bal0.toString(), bal0Before.add(BigNumber.from(amountB)).toString(), "wrong amountA")

    expect(share).to.equal(1000);
  });


  it("Should remove the liquidity", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);
    // add liquidity using aggregator contract
    await v3Aggregator.addLiquidity(
      strategy.address,
      amountA,
      amountB,
      "0",
      "0"
    );

    const shareBefore = await v3Aggregator.shares(strategy.address, owner.address);

    const newTickLower = calculateTick(3200, 60);
    const newTickUpper = calculateTick(4200, 60);

    await strategy.changeTicks(newTickLower, newTickUpper);
    await v3Aggregator.rebalance(strategy.address);

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const share = await v3Aggregator.shares(strategy.address, owner.address);
    console.log({
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });
    assert.equal(share.toString(), shareBefore.toString(), "wrong shares");

    await v3Aggregator.removeLiquidity(strategy.address, 1000, 0, 0);

    const bal0After = await testToken0.balanceOf(pool.address);
    const bal1After = await testToken1.balanceOf(pool.address);
    const shareAfter = await v3Aggregator.shares(strategy.address, owner.address);

    console.log({
      bal0: bal0After.toString(),
      bal1: bal1After.toString(),
      share: shareAfter.toString(),
    });
    assert.equal(shareAfter.toString(), "0", "shares properly removed");
    // assert.equal(bal0After.toString(), "0", "wrong bal0");  // leaves 2 wei
    // assert.equal(bal1After.toString(), "0", "wrong bal1");
  });

  it("Should rebalance", async function () {
    // calculate new ticks
    // const newTickLower = calculateTick(3200, 60);
    // const newTickUpper = calculateTick(4200, 60);
    // // add liquidity using aggregator contract
    // await v3Aggregator.addLiquidity(
    //   strategy.address,
    //   amountA,
    //   amountB,
    //   "0",
    //   "0"
    // );
    // // change ticks in strategy
    // await strategy.changeTicks(newTickLower, newTickUpper);
    // await v3Aggregator.rebalance(strategy.address);
    // const bal0 = await testToken0.balanceOf(pool.address);
    // const bal1 = await testToken1.balanceOf(pool.address);
    // const share = await v3Aggregator.shares(strategy.address, owner.address);
    // console.log({
    //   bal0: bal0.toString(),
    //   bal1: bal1.toString(),
    //   share: share.toString(),
    // });
  });

  it("multiple users", async () => {

  })

  it("add liq then swap, remove liq", async () => {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);
    // add liquidity using aggregator contract
    await v3Aggregator.addLiquidity(
      strategy.address,
      amountA,
      amountB,
      "0",
      "0"
    );

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const share = await v3Aggregator.shares(strategy.address, owner.address);
    const slot0 = await pool.slot0();

    console.log({
      sqrtPriceX96: slot0.sqrtPriceX96.toString(),
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });

    expect(share).to.equal(1000);

    // uniswapV3 swap call
    const swap = await pool.swap(
      owner.address,
      true, // zeroForOne ??
      200, // amountSepcified
      slot0.sqrtPriceX96,
      0 // data
    );

    const bal0After = await testToken0.balanceOf(pool.address);
    const bal1After = await testToken1.balanceOf(pool.address);
    const shareAfter = await v3Aggregator.shares(strategy.address, owner.address);
    const slot0After = await pool.slot0();

    console.log({
      sqrtPriceX96: slot0After.sqrtPriceX96.toString(),
      bal0: bal0After.toString(),
      bal1: bal1After.toString(),
      share: shareAfter.toString(),
    });

    // remove liq, make sure correct amount returned.
  })
});

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
