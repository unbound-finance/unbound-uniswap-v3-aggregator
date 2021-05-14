const { expect } = require("chai");

const { BigNumber } = require("ethers");
const { ethers } = require('hardhat');
const bn = require('bignumber.js');

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

describe("V3Aggregator", function () {
  it("Should add liquidity successfully", async function () {
    const Factory = await ethers.getContractFactory("UniswapV3Factory");
    const TestToken = await ethers.getContractFactory("ERC20");
    const V3Aggregator = await ethers.getContractFactory("UnboundUniswapV3Aggregator2")

    const [owner, addr1, addr2] = await ethers.getSigners();

    const amt = "100000000000000000000000000000"
  
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
    const v3Aggregator =  await V3Aggregator.deploy()

    // approve tokens
    await testToken0.approve(v3Aggregator.address, amt)
    await testToken1.approve(v3Aggregator.address, amt)

    // create a pool
    await factory.createPool(testToken0.address, testToken1.address, "3000")
  
    // initialize the pool
    const poolAddress = await factory.getPool(testToken0.address, testToken1.address, "3000")
    
    const pool = await ethers.getContractAt("UniswapV3Pool", poolAddress)

    let reserve0, reserve1;
    let ethAddress, daiAddress;
    
    // set reserves at ETH price of 3500 DAI per ETh
    const initialDaiReserve = "100000000000000000000000"
    const initialEthReserve = "28571428571400000000"

    // consider token1 is always DAI
    const token0 = await pool.token0()
    const token1 = await pool.token1()
    
    reserve0 = initialDaiReserve
    reserve1 = initialEthReserve

    const sqrtPriceX96 = encodePriceSqrt(reserve0, reserve1)
    await pool.initialize(sqrtPriceX96)

    // add liquidity
    
    
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
  )
}