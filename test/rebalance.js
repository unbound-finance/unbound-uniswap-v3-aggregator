const { expect } = require("chai");

const { BigNumber, utils } = require("ethers");

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

// import artifacts
async function loadContracts() {
  UniswapV3Factory = await ethers.getContractFactory("UniswapV3Factory");
  StrategyFactory = await ethers.getContractFactory("StrategyFactory");
  TestToken = await ethers.getContractFactory("ERC20");
  DefiEdgeStrategy = await ethers.getContractFactory("UnboundStrategy");
  Aggregator = await ethers.getContractFactory("V3Aggregator");
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
  strategy0 = await DefiEdgeStrategy.deploy(
    aggregator.address,
    pool.address,
    owner.address
  );

  strategy1 = await DefiEdgeStrategy.deploy(
    aggregator.address,
    pool.address,
    owner.address
  );

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

    console.log(ticks);

    await strategy1.changeTicksAndRebalance([
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

  it("matches and stores debited amounts in the contract variable ", async () => {
    const ticks = await aggregator.getTicks(strategy1.address);
    const unused = await aggregator.unused(strategy1.address);
    expect(
      parseInt("10000000000000000000") - parseInt(unused.amount0)
    ).to.equal(parseInt(ticks[0].amount0));
  });

  it("adds liquidity after rebalance", async () => {
    const oldTicksData = await aggregator.getTicks(strategy1.address);
    await aggregator.addLiquidity(
      strategy1.address,
      "1000000000000000000",
      "3500000000000000000000",
      0,
      0,
      0
    );
    const newTicksData = await aggregator.getTicks(strategy1.address);

    console.log("oldTickData", oldTicksData);
    console.log("newTicksData", newTicksData);

    expect(parseInt("1000000000000000000")).to.equal(
      newTicksData[0].amount0.toString() - oldTicksData[0].amount0.toString()
    );
    expect(3.163014888900589e21).to.equal(
      newTicksData[0].amount1.toString() - oldTicksData[0].amount1.toString()
    );
  });

  it("is able to rebalance again", async () => {
    await strategy1.changeTicksAndRebalance([
      [
        "1000000000000000000",
        "350000000000000000000",
        calculateTick(2600, 60),
        calculateTick(3300, 60),
      ],
    ]);
    const ticks = await aggregator.getTicks(strategy1.address);
    console.log("ticks in abel to rebalance", ticks);
    expect(parseInt("350000000000000000000")).to.equal(
      parseInt(ticks[0].amount1)
    );
  });

  // TODO: Add test to deploy 100% liquidity in single order
});

describe("🟢 🟢 Rebalance using Multiple Ranges", () => {
  let ticksBefore;

  beforeEach("Add and Rebalance liquidity in two ranges", async () => {
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

    // ticks before rebalance
    ticksBefore = await aggregator.getTicks(strategy1.address);

    await strategy1.changeTicksAndRebalance([
      [
        "1000000000000000000",
        "35000000000000000000000",
        calculateTick(2600, 60),
        calculateTick(3300, 60),
      ],
      [
        "1000000000000000000",
        "35000000000000000000000",
        calculateTick(2300, 60),
        calculateTick(3700, 60),
      ],
    ]);
  });

  it("updates the unused amounts", async () => {
    const unused = await aggregator.unused(strategy1.address);
    expect(unused.amount0.toString()).to.equal(
      await token0.balanceOf(aggregator.address)
    );
    expect(unused.amount1.toString()).to.equal(
      await token1.balanceOf(aggregator.address)
    );
  });

  it("updates the used amounts", async () => {
    let token0After = 0,
      token1After = 0;
    const ticksAfter = await aggregator.getTicks(strategy1.address);
    const unused = await aggregator.unused(strategy1.address);

    for (const tick of ticksAfter) {
      token0After += parseInt(tick.amount0);
      token1After += parseInt(tick.amount1);
    }

    console.log("tokens0After", token0After);
    console.log("tokens1After", token1After);

    expect(token0After).to.equal(parseInt("2000000000000000000"));
    expect(token1After).to.equal(7.838492351944538e21);
  });

  it("adds liquidity after rebalance", async () => {
    const oldTicksData = await aggregator.getTicks(strategy1.address);
    await aggregator.addLiquidity(
      strategy1.address,
      "1000000000000000000",
      "3500000000000000000000",
      0,
      0,
      0
    );
    const newTicksData = await aggregator.getTicks(strategy1.address);

    expect(parseInt("830921251876009000")).to.equal(
      newTicksData[0].amount0.toString() - oldTicksData[0].amount0.toString()
    );
    expect(3.5000000000000005e21).to.equal(
      newTicksData[0].amount1.toString() - oldTicksData[0].amount1.toString()
    );
  });
});

describe("🤯 Swap With Rebalance", () => {
  beforeEach("Add liquidity and swap amount", async () => {
    const balanceInToken0 = await token0.balanceOf(aggregator.address);
    const balanceInToken1 = await token1.balanceOf(aggregator.address);

    console.log({
      balanceInToken0,
      balanceInToken1,
    });

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

    const unusedBefore = await aggregator.unused(strategy1.address);
    console.log(unusedBefore);

    await strategy1.swapAndRebalance(
      "2000000000000000000",
      "1000000",
      "1000000",
      true,
      [
        [
          "1000000000000000000",
          "35000000000000000000000",
          calculateTick(2600, 60),
          calculateTick(3300, 60),
        ],
        [
          "1000000000000000000",
          "35000000000000000000000",
          calculateTick(2300, 60),
          calculateTick(3700, 60),
        ],
      ]
    );
  });

  it("updates the unused amounts", async () => {
    const unused = await aggregator.unused(strategy1.address);
    console.log(
      "balance of token0",
      await token0.balanceOf(aggregator.address)
    );
    console.log(
      "balance of token1",
      await token1.balanceOf(aggregator.address)
    );

    console.log(await aggregator.getTicks(strategy1.address));
    expect(unused.amount0.toString()).to.equal(
      await token0.balanceOf(aggregator.address)
    );
    expect(unused.amount1.toString()).to.equal(
      await token1.balanceOf(aggregator.address)
    );
  });

  it("rebaalnces again", async () => {
    await token0.transfer(userA.address, "1000000000000000000000");
    await token1.transfer(userA.address, "1758008509945496673626415400");
    await token0
      .connect(userA)
      .approve(aggregator.address, "1000000000000000000000");
    await token1
      .connect(userA)
      .approve(aggregator.address, "1758008509945496673626415400");

    console.log(
      "approval of token0",
      await token0.allowance(userA.address, aggregator.address)
    );
    console.log(
      "approval of token1",
      await token1.allowance(userA.address, aggregator.address)
    );

    await aggregator
      .connect(userA)
      .addLiquidity(
        strategy1.address,
        "30000000000000000000",
        "17580085099454966736264154",
        0,
        0,
        0
      );

    await aggregator
      .connect(userA)
      .addLiquidity(
        strategy1.address,
        "30000000000000000000",
        "17580085099454966736264154",
        0,
        0,
        0
      );

    await strategy1.swapAndRebalance(
      "1500000000000000000",
      "1000000",
      "1000000",
      true,
      [
        [
          "2000000000000000000",
          "35000000000000000000000",
          calculateTick(2800, 60),
          calculateTick(3300, 60),
        ],
        [
          "2000000000000000000",
          "35000000000000000000000",
          calculateTick(2000, 60),
          calculateTick(3700, 60),
        ],
        [
          "2000000000000000000",
          "35000000000000000000000",
          calculateTick(2000, 60),
          calculateTick(3900, 60),
        ],
      ]
    );

    const ticks = await aggregator.getTicks(strategy1.address);
    console.log(ticks);

    const newTicks = await aggregator.getTicks(strategy1.address);
    console.log(newTicks);
  });

  // it("updates used amounts", async () => {
  //   let token0After = 0,
  //     token1After = 0;
  //   const ticksAfter = await aggregator.getTicks(strategy1.address);
  //   for (const tick of ticksAfter) {
  //     token0After += parseInt(tick.amount0);
  //     token1After += parseInt(tick.amount1);
  //   }
  //   expect(3.862630017115979e22).to.equal(3.862630017115979e22);
  //   // expect(token0After).to.equal(parseInt("2000000000000000000"));
  // });
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
