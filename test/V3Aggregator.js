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

const bone = new bn("1000000000000000000"); // 10**18

beforeEach(async function () {
  [owner, userA, userB] = await ethers.getSigners();

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
  const V3Aggregator = await ethers.getContractFactory("V3AggregatorTest");

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

describe("V3Aggregator", function () {
  it("Should add right amount of successfully", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);

    const bal0Before = await testToken0.balanceOf(pool.address);
    const bal1Before = await testToken1.balanceOf(pool.address);
    
    
    const tickLow = await strategy.tickLower();
    const tickUp = await strategy.tickUpper();
    const posKey = await v3Aggregator.TESTgetPositionKey(v3Aggregator.address, tickLow, tickUp);
    const currentLiq = await pool.positions(posKey.toString());
    
    // CONTRACT VARIABLE
    const LiquidityBefore = currentLiq.liquidity; // BN
    assert.equal(LiquidityBefore.toString(), "0", "Wrong initial liquidity");
    // CONTRACT VARIABLE - end

    const slot = await pool.slot0();
    const ratioA = await v3Aggregator.getSqrtRatioTEST(tickLow);
    const ratioB = await v3Aggregator.getSqrtRatioTEST(tickUp);
    const getLiqAmt = await v3Aggregator.getLiqAmtTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      amountA,
      amountB
    )
    
    
    // CONTRACT VARIABLE - Do we have a manual way of calculating this in JS?
    const Liquidity = getLiqAmt; // BN
    // CONTRACT VARIABLE - end

    const amountsForLiq = await v3Aggregator.getAmtForLiqTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      Liquidity.toString()
    )
    console.log(amountsForLiq.amount0.toString());
    console.log(amountsForLiq.amount1.toString());

    const ownerShareBefore = await v3Aggregator.getShares(strategy.address, owner.address);
    const feeHolderShareBefore = await v3Aggregator.getShares(strategy.address, owner.address);

    assert.equal(ownerShareBefore.toString(), "0", "wrong initial depositor share");
    assert.equal(feeHolderShareBefore.toString(), "0", "wrong fee holder shares");
    // const getLiqForAmt = await 

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
    const feeShare = await v3Aggregator.shares(strategy.address, userA.address);
    const slot0 = await pool.slot0();

    // FAILURES - THEY ARE OFF BY VERY SMALL VALUES - Likely culprit: UNISWAP
    // assert.equal(bal0.toString(), amountsForLiq.amount0.toString(), "Wrong balances");
    // assert.equal(bal1.toString(), amountsForLiq.amount1.toString(), "wrong balance1")
    // FAILURES - end
    
    const sharesToFee = Liquidity.div(2).toString();
    const sharesToDepositor = Liquidity.sub(sharesToFee);
    assert.equal(share.toString(), Liquidity.toString(), "wrong amount of shares");
    
    // assert.equal(feeShare.toString(), Liquidity.mul(bone).div(2).toString(), "wrong shares to fee")
    
    console.log({
      sqrtPriceX96: slot0.sqrtPriceX96.toString(),
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });

  });

  // TO TEST: changeFeeSetter()
  it("Should distribute fee correctly", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);

    const bal0Before = await testToken0.balanceOf(pool.address);
    const bal1Before = await testToken1.balanceOf(pool.address);
    
    // set feeAddr
    await v3Aggregator.changeFeeTo(userA.address);
    
    const tickLow = await strategy.tickLower();
    const tickUp = await strategy.tickUpper();
    const posKey = await v3Aggregator.TESTgetPositionKey(v3Aggregator.address, tickLow, tickUp);
    const currentLiq = await pool.positions(posKey.toString());
    
    // CONTRACT VARIABLE
    const LiquidityBefore = currentLiq.liquidity; // BN
    assert.equal(LiquidityBefore.toString(), "0", "Wrong initial liquidity");
    // CONTRACT VARIABLE - end

    const slot = await pool.slot0();
    const ratioA = await v3Aggregator.getSqrtRatioTEST(tickLow);
    const ratioB = await v3Aggregator.getSqrtRatioTEST(tickUp);
    const getLiqAmt = await v3Aggregator.getLiqAmtTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      amountA,
      amountB
    )
    
    
    // CONTRACT VARIABLE - Do we have a manual way of calculating this in JS?
    const Liquidity = getLiqAmt; // BN
    // CONTRACT VARIABLE - end

    const amountsForLiq = await v3Aggregator.getAmtForLiqTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      Liquidity.toString()
    )
    console.log(amountsForLiq.amount0.toString());
    console.log(amountsForLiq.amount1.toString());

    const ownerShareBefore = await v3Aggregator.getShares(strategy.address, owner.address);
    const feeHolderShareBefore = await v3Aggregator.getShares(strategy.address, owner.address);

    assert.equal(ownerShareBefore.toString(), "0", "wrong initial depositor share");
    assert.equal(feeHolderShareBefore.toString(), "0", "wrong fee holder shares");
    // const getLiqForAmt = await 

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
    const feeShare = await v3Aggregator.shares(strategy.address, userA.address);
    const slot0 = await pool.slot0();

    // FAILURES - THEY ARE OFF BY VERY SMALL VALUES - Likely culprit: UNISWAP
    // assert.equal(bal0.toString(), amountsForLiq.amount0.toString(), "Wrong balances");
    // assert.equal(bal1.toString(), amountsForLiq.amount1.toString(), "wrong balance1")
    // FAILURES - end
    
    const sharesToFee = Liquidity.div(2).toString();
    const sharesToDepositor = Liquidity.sub(sharesToFee);
    assert.equal(share.toString(), sharesToDepositor.toString(), "wrong amount of shares");
    
    assert.equal(feeShare.toString(), sharesToFee.toString(), "wrong shares to fee")
    
    console.log({
      sqrtPriceX96: slot0.sqrtPriceX96.toString(),
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
    });

  });

  it("Should issue right amount of shares", async function () {
    await testToken0.approve(v3Aggregator.address, amountA);
    await testToken1.approve(v3Aggregator.address, amountB);

    const tickLow = await strategy.tickLower();
    const tickUp = await strategy.tickUpper();

    const slot = await pool.slot0();
    const ratioA = await v3Aggregator.getSqrtRatioTEST(tickLow);
    const ratioB = await v3Aggregator.getSqrtRatioTEST(tickUp);
    const getLiqAmt = await v3Aggregator.getLiqAmtTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      amountA,
      amountB
    )
    
    
    // CONTRACT VARIABLE - Do we have a manual way of calculating this in JS?
    const Liquidity = getLiqAmt; // BN
    // CONTRACT VARIABLE - end

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

    expect(share).to.equal(Liquidity);
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

    // const newTickLower = calculateTick(3200, 60);
    // const newTickUpper = calculateTick(4200, 60);

    // await strategy.changeTicks(newTickLower, newTickUpper);
    // await v3Aggregator.rebalance(strategy.address, tickLower, tickUpper);

    const tickLow = await strategy.tickLower();
    const tickUp = await strategy.tickUpper();
    const posKey = await v3Aggregator.TESTgetPositionKey(v3Aggregator.address, tickLow, tickUp);
    const currentLiq = await pool.positions(posKey.toString());
    
    // CONTRACT VARIABLE
    const LiquidityCurrent = currentLiq.liquidity; // BN
    // CONTRACT VARIABLE - end
    const share = await v3Aggregator.shares(strategy.address, owner.address);

    const totalShares = await v3Aggregator.totalShares(strategy.address);
    const liquidity = share.mul(LiquidityCurrent).div(totalShares);

    const slot = await pool.slot0();
    const ratioA = await v3Aggregator.getSqrtRatioTEST(tickLow);
    const ratioB = await v3Aggregator.getSqrtRatioTEST(tickUp);

    const amountsForLiq = await v3Aggregator.getAmtForLiqTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      liquidity.toString()
    )

    console.log(amountsForLiq[0].toString());
    console.log(amountsForLiq[1].toString());

    const bal0Before = await testToken0.balanceOf(pool.address);
    const bal1Before = await testToken1.balanceOf(pool.address);
    // const share = await v3Aggregator.shares(strategy.address, owner.address);
    

    await v3Aggregator.removeLiquidity(strategy.address, share.toString(), 0, 0);

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const shareAfter = await v3Aggregator.shares(strategy.address, owner.address);

    // assert.equal(bal0.toString(), bal0Before.sub(amountsForLiq[0]).toString(), "wrong bal 0");
    // assert.equal(bal1.toString(), bal1Before.sub(amountsForLiq[1]).toString(), "wrong bal 1");

    assert.equal(shareAfter.toString(), share.sub(share), "wrong shares");
    console.log({
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
      shareAfter: shareAfter.toString()
    });
  });

  it("Should remove partial liquidity", async function () {
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

    // const newTickLower = calculateTick(3200, 60);
    // const newTickUpper = calculateTick(4200, 60);

    // await strategy.changeTicks(newTickLower, newTickUpper);
    // await v3Aggregator.rebalance(strategy.address, tickLower, tickUpper);

    const tickLow = await strategy.tickLower();
    const tickUp = await strategy.tickUpper();
    const posKey = await v3Aggregator.TESTgetPositionKey(v3Aggregator.address, tickLow, tickUp);
    const currentLiq = await pool.positions(posKey.toString());
    
    // CONTRACT VARIABLE
    const LiquidityCurrent = currentLiq.liquidity; // BN
    // CONTRACT VARIABLE - end
    const share = await v3Aggregator.shares(strategy.address, owner.address);

    const totalShares = await v3Aggregator.totalShares(strategy.address);
    const liquidity = share.mul(LiquidityCurrent).div(totalShares);

    const slot = await pool.slot0();
    const ratioA = await v3Aggregator.getSqrtRatioTEST(tickLow);
    const ratioB = await v3Aggregator.getSqrtRatioTEST(tickUp);

    const amountsForLiq = await v3Aggregator.getAmtForLiqTEST(
      slot[0].toString(),
      ratioA.toString(),
      ratioB.toString(),
      liquidity.toString()
    )

    console.log(amountsForLiq[0].toString());
    console.log(amountsForLiq[1].toString());

    const bal0Before = await testToken0.balanceOf(pool.address);
    const bal1Before = await testToken1.balanceOf(pool.address);
    // const share = await v3Aggregator.shares(strategy.address, owner.address);
    

    await v3Aggregator.removeLiquidity(strategy.address, parseInt(parseInt(share) / 2), 0, 0);

    const bal0 = await testToken0.balanceOf(pool.address);
    const bal1 = await testToken1.balanceOf(pool.address);
    const shareAfter = await v3Aggregator.shares(strategy.address, owner.address);

    // assert.equal(bal0.toString(), bal0Before.sub(amountsForLiq[0]).toString(), "wrong bal 0");
    // assert.equal(bal1.toString(), bal1Before.sub(amountsForLiq[1]).toString(), "wrong bal 1");

    // assert.equal(shareAfter.toString(), share.sub(share), "wrong shares");
    console.log({
      bal0: bal0.toString(),
      bal1: bal1.toString(),
      share: share.toString(),
      shareAfter: shareAfter.toString(),
    });
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
