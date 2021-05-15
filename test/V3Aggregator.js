const { expect } = require("chai");

const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const bn = require("bignumber.js");

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

describe("V3Aggregator", function () {
  it("Should add liquidity successfully", async function () {
    const TickMath = await ethers.getContractFactory("contracts/test/core/libraries/TickMath.sol:TickMath")
    const tickMath = await TickMath.deploy()
    const Factory = await ethers.getContractFactory("UniswapV3Factory",   {
      libraries: {
        TickMath: tickMath.address
      }
    });
    const TestToken = await ethers.getContractFactory("ERC20");
    const LiquidityAmount = await ethers.getContractFactory("contracts/test/periphery/libraries/LiquidityAmounts.sol:LiquidityAmounts");
    const TestStrategy = await ethers.getContractFactory("TestStrategy")

    const liquidityAmount = await LiquidityAmount.deploy()

    const V3Aggregator = await ethers.getContractFactory(
      "UnboundUniswapV3Aggregator2"
    );

    const [owner, addr1, addr2] = await ethers.getSigners();

    const amt = "100000000000000000000000000000";

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

    const factory = await Factory.deploy();
    const v3Aggregator = await V3Aggregator.deploy();

    // approve tokens
    await testToken0.approve(v3Aggregator.address, amt);
    await testToken1.approve(v3Aggregator.address, amt);

    // create a pool
    await factory.createPool(testToken0.address, testToken1.address, "3000");

    // initialize the pool
    const poolAddress = await factory.getPool(
      testToken0.address,
      testToken1.address,
      "3000"
    );

    const pool = await ethers.getContractAt("UniswapV3Pool", poolAddress);

    let reserve0, reserve1;
    let ethAddress, daiAddress;

    // set reserves at ETH price of 3500 DAI per ETh
    const initialDaiReserve = "100000000000000000000000";
    const initialEthReserve = "28571428571400000000";

    // consider token1 is always DAI
    const token0 = await pool.token0();
    const token1 = await pool.token1();

    reserve0 = initialDaiReserve;
    reserve1 = initialEthReserve;

    const sqrtPriceX96 = encodePriceSqrt(reserve0, reserve1);
    await pool.initialize(sqrtPriceX96);

    // add initial liquidity to start the pool
    const tickLower = calculateTick(3000, 60);
    const tickUpper = calculateTick(4500, 60);
    const slot0 = await pool.slot0()
    const sqrtPriceX96_ = slot0.sqrtPriceX96
    const sqrtRatioAX96 = await tickMath.getSqrtRatioAtTick(tickLower)
    const sqrtRatioBX96 = await tickMath.getSqrtRatioAtTick(tickUpper)
    const amount0Desired = initialDaiReserve
    const amount1Desired = initialEthReserve

    // const amount = await liquidityAmount.getLiquidityForAmounts(
    //   sqrtPriceX96_,
    //   sqrtRatioAX96,
    //   sqrtRatioBX96,
    //   amount0Desired,
    //   amount1Desired
    // );

    // console.log({
    //   sqrtPriceX96_,
    //   sqrtRatioAX96,
    //   sqrtRatioBX96,
    //   amount0Desired,
    //   amount1Desired,
    //   amount
    // })
      
    // await pool.mint(
    //   owner.address,
    //   tickLower,
    //   tickUpper,
    //   amount,
    //   expandTo18Decimals(3500)
    // );

    // deploy strategy contract
    const strategy = await TestStrategy.deploy(
      "2500",
      "4500",
      tickLower,
      tickUpper,
      pool.address,
      token0,
      "0"
    )

    const amountA = "100000000000000000000"
    const amountB = "28571428570000000"
    await testToken0.approve(v3Aggregator.address, amountA)
    await testToken1.approve(v3Aggregator.address, amountB)

    // add liquidity using aggregator contract
    await v3Aggregator.addLiquidity(
      strategy.address,
      amountA,
      amountB,
      "0",
      "0"
    )
    // console.log("liquidity added")

    // await v3Aggregator.rebalance(
    //   strategy.address
    // )

    // add liquidity via aggregator contract

    // change the ranges

    // rebalance the pool

    // remove the liquidity
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
