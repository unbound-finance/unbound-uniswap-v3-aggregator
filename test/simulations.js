const { expect } = require("chai");

const { BigNumber, utils } = require("ethers");

const { ethers } = require("hardhat");

const {
  encodePriceSqrt,
  toGwei,
  calculateTick,
  getPriceFromTick,
} = require("./utils");

let UniswapV3Factory;
let StrategyFactory;
let TestToken;
let DefiEdgeStrategy;
let Aggregator;
let userA;
let userB;

let LiquidityHelper;

// import artifacts
async function loadContracts() {
  UniswapV3Factory = await ethers.getContractFactory("UniswapV3Factory");
  StrategyFactory = await ethers.getContractFactory("StrategyFactory");
  TestToken = await ethers.getContractFactory("ERC20");
  DefiEdgeStrategy = await ethers.getContractFactory("DefiEdgeStrategy");
  Aggregator = await ethers.getContractFactory("Aggregator");
  LiquidityHelper = await ethers.getContractFactory("LiquidityHelper");
}

let token0;
let token1;
let owner;
let uniswapFactory;
let aggregator;
let strategy0;
let strategy1;

let tickLower;
let tickUpper;
let secondaryTickLower;
let secondaryTickUpper;
let swapRouter;

beforeEach(async () => {
  [owner, userA, userB] = await ethers.getSigners();

  await loadContracts();
  await deployTestTokens();

  // create and initialize the pool
  uniswapFactory = await UniswapV3Factory.deploy();
  await uniswapFactory.createPool(token0.address, token1.address, "3000");
  const poolAddress = await uniswapFactory.getPool(
    token0.address,
    token1.address,
    "3000"
  );
  pool = await ethers.getContractAt("UniswapV3Pool", poolAddress);

  let sqrtPriceX96 = encodePriceSqrt("500000", "1500000000");

  sqrtPriceX96 = sqrtPriceX96.toLocaleString("fullwide", {
    useGrouping: false,
  });

  await pool.initialize(sqrtPriceX96);

  // set token0 and token1 accordinfg to the pool
  if (token1.address < token0.address) {
    const oldToken0 = token0;
    const oldToken1 = token1;
    token0 = oldToken1;
    token1 = oldToken0;
  }

  // deploy aggregator contract
  aggregator = await Aggregator.deploy(owner.address);

  // add some liquidity in the pool
  // deploy strategy contract

  const strategyFactory = await StrategyFactory.deploy(aggregator.address);
  await aggregator.addFactory(strategyFactory.address);

  await strategyFactory.createStrategy(pool.address, owner.address);

  await strategyFactory.createStrategy(pool.address, owner.address);

  const _strategy0 = await strategyFactory.strategyByIndex(1);

  const _strategy1 = await strategyFactory.strategyByIndex(2);

  strategy0 = await ethers.getContractAt("DefiEdgeStrategy", _strategy0);

  strategy1 = await ethers.getContractAt("DefiEdgeStrategy", _strategy1);

  // add initial liquidity to start the pool
  tickLower = calculateTick(2500, 60);
  tickUpper = calculateTick(3500, 60);
  secondaryTickLower = calculateTick(2700, 60);
  secondaryTickUpper = calculateTick(3300, 60);

  await strategy0.initialize([[0, 0, tickLower, tickUpper]]);
  await strategy1.initialize([[0, 0, secondaryTickLower, secondaryTickUpper]]);

  const approveAmt = "100000000000000000000000000000";

  // approve tokens for aggregator
  await token0.approve(aggregator.address, approveAmt);
  await token1.approve(aggregator.address, approveAmt);

  // // adds 5000 token0 and 16580085.099454967 token1

  await aggregator
    .connect(owner)
    .addLiquidity(
      strategy0.address,
      "5000000000000000000000",
      "1500000000000000000000000000",
      0,
      0,
      0
    );
});

describe("🟢  Adding Liquidity in single order", function () {
  beforeEach("add and rebalance pair", async () => {
    // adds 10 and 31630.148889005883
    await aggregator
      .connect(owner)
      .addLiquidity(
        strategy1.address,
        "10000000000000000000",
        "17580085099454966736264154",
        0,
        0,
        0
      );

    const ticks = await aggregator.getTicks(strategy1.address);

    await strategy1.rebalance("0", "0", "0", false, [
      [
        "5000000000000000000",
        "17500000000000000000000",
        secondaryTickLower,
        secondaryTickUpper,
      ],
    ]);
  });

  it("updates unused amounts matching with contract balance", async () => {
    const unused = await aggregator.unused(strategy1.address);
    expect(unused.amount0.toString()).to.equal(
      await token0.balanceOf(aggregator.address)
    );
    expect(unused.amount1.toString()).to.equal(
      await token1.balanceOf(aggregator.address)
    );
  });


  // TODO: Add test to deploy 100% liquidity in single order
});

// deploy test tokens
async function deployTestTokens() {
  token0 = await TestToken.deploy(
    "tstToken",
    "TST0",
    18,
    "100000000000000000000000000000",
    owner.address
  );

  token1 = await TestToken.deploy(
    "tstToken",
    "TST0",
    18,
    "100000000000000000000000000000",
    owner.address
  );
}

async function deployStrategy() {}
