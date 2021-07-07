const {expect} = require('chai');

describe ('DefiEdgeStrategy Contract Test Variables', async function () {
    let DefiEdgeStrategy ,StrategyFactory,strategy, Aggregator, aggredeploy,_pool, _operator ,tickLow, tickHigh, _pendingOperator, _aggregator, deployFunction,_swapAmount,sqrtPriceLimittX96,zeroToOne,allowPriceSlipage, managementFee,_newFeeTo,testAddress,initialized,onHold,lengthOfData,strat0,strat1;
    beforeEach(async function () {
        DefiEdgeStrategy = await ethers.getContractFactory('DefiEdgeStrategy');
        Aggregator = await ethers.getContractFactory('Aggregator');
        StrategyFactory = await ethers.getContractFactory('StrategyFactory');
        [_pool,_operator,strategy,_pendingOperator,_newFeeTo,testAddress,_aggregator,deployFunction,_swapAmount,sqrtPriceLimittX96,zeroToOne,allowPriceSlipage,managementFee,initialized,onHold,lengthOfData] = await ethers.getSigners();
        deployFunction = await DefiEdgeStrategy.deploy(_aggregator.address,_pool.address,_operator.address);
    });

    describe ('Deployment Function', async function () {
        it('Deployment Confirmer', async function () {
            expect(await deployFunction.aggregator())
                .to
                .equal(
                    _aggregator.address
                );
            //const pendingOperatorAddress = (await deployFunction.pendingOperator);


            expect (await deployFunction.initialized())
                .to
                .equal(
                    false
                );
            const addressOfFee = await  (deployFunction.feeTo());
            console.log(addressOfFee);
            expect (await  deployFunction.onHold())
                .to
                .equal(
                    false
                );
            expect (await deployFunction.swapAmount())
                .to
                .equal(
                    0
                );
            expect (await deployFunction.sqrtPriceLimitX96())
                .to
                .equal(
                    0
                );
            expect (await deployFunction.zeroToOne())
                .to
                .equal(
                    false
                );
            expect (await deployFunction.allowedPriceSlippage())
                .to
                .equal(
                    0
                );
            expect(await deployFunction.pool())
                .to
                .equal(
                    _pool.address
                );
            expect(await deployFunction.operator())
                .to
                .equal(
                    _operator.address
                );
            expect(await deployFunction.managementFee())
                .to
                .equal(
                    0
                );
        });
    });
    //todo initialize function done
    describe ('intialize function',async  function() {
        it('Testing the initialized function', async function () {
            tickLow = calculateTick(2700, 60);
            tickHigh = calculateTick(3500, 60);
            console.log(tickLow, tickHigh);
            deployFunction.connect(_operator).initialize([[0, 0, tickLow, tickHigh]]);
            await expect(deployFunction.initialized())
                .is
                .equal
            {
                true
            }
            ;
            //used this function in the DefiStrategy.sol to test the return of total ticks.length its passing the test
            // function myfunc() public view returns (uint256){
            //     return ticks.length;
            // }
            // console.log('The lenght of data is '+ await deployFunction.lenghtOfData());
            // await expect(await deployFunction.myfunc()).to.equal(1);
            console.log('its done');

            await deployFunction.connect(_operator).hold();
            await deployFunction.ticks.delete;
            console.log(deployFunction.ticks.length);
            expect(await deployFunction.onHold())
                .is
                .equal
                (
                    true
                );
            expect(await deployFunction.swapAmount())
                .is
                .equal(
                    0
                );
            expect(await deployFunction.sqrtPriceLimitX96())
                .is
                .equal(
                    0
                );
            expect(await deployFunction.allowedPriceSlippage())
                .is
                .equal(
                    0
                );

        });

    });
    describe ('changeOperator ',async function () {
            it ('should return me changeOperator == pendingOperator', async function () {
                await deployFunction.connect(_operator).changeOperator(_operator.address);
                const pender = await deployFunction.pendingOperator();
                expect(await deployFunction.pendingOperator())
                    .to
                    .equals
                    (
                        _operator.address
                    );

                await deployFunction.acceptOperator();
                expect(await deployFunction.operator())
                    .is
                    .equal
                    (
                        pender
                    );
                console.log('Operator == PendingOperator '+await deployFunction.operator() +' val= '+pender);

            // it ('should acceptOperator', async function () {
            //     console.log(await deployFunction.pendingOperator());
            // })
            });
                it ('changeFeeTo', async function () {
                    await deployFunction.connect(_operator).changeFeeTo(_newFeeTo.address)
                    expect(await deployFunction.feeTo())
                        .is
                        .equal(
                            _newFeeTo.address
                        );
                    console.log('feeto == _newFeeTo is establised');
                });

                it('changeFee() Function', async function () {
                    await deployFunction.connect(_operator).changeFee(0);
                    expect(await deployFunction.managementFee())
                        .is
                        .equal(
                            1000000
                        );
                    await deployFunction.connect(_operator).changeFee(1);
                    expect(await deployFunction.managementFee())
                        .is
                        .equal(
                            2000000
                        );
                    await deployFunction.connect(_operator).changeFee(2);
                    expect(await deployFunction.managementFee())
                        .is
                        .equal(
                            5000000
                        );
                });


        });





    //todo changeTicks()
    // describe ('changeTicks function', async  function(){
    //     it('testing if the changes in the ticks results in error or not',async function(){
    //         tickLow = calculateTick(2700,60);
    //         tickHigh = calculateTick(3500,60);
    //         //experimented with the bounf of int24 by increasing the limit from 16777216 to 1677721600
    //         // await expect(deployFunction.changeTicks([[0,0,tickLow,tickHigh]])).to.be.revertedWith('Error: value out-of-bounds (argument="tickUpper", value=1677721600, code\n' +
    //         //     '=INVALID_ARGUMENT, version=abi/5.4.0)');
    //         await deployFunction.changeTicks(([0,0,tickLow,tickHigh]))
    //         const eqauls = deployFunction.tickUpper===167772160;
    //         expect(eqauls).to.equal(false);
    //     })
    //
    //     it ('testing if the negative value is accepted as tickLower or not',async function(){
    //         tickLow = -1;
    //         tickHigh = calculateTick(3500,60);
    //         expect(await deployFunction.changeTicks(([0,0,tickLow,tickHigh]))).to.be.revertedWith('error');
    //
    //      })
    //  });
    describe ('rebalance', async function () {
        it('deploying rebalance function', async function () {
            await deployFunction.connect(_operator).initialize([[0,0,tickLow,tickHigh]]);
            await deployFunction.connect(_operator).rebalance('0',0,'1000000',true,[['100000000000000000','35000000000000000000', calculateTick(2600, 60), calculateTick(2800, 60),],]);
            expect(await  deployFunction.zeroToOne())
                .is
                .equal(
                    true
                );
            expect(await  deployFunction.swapAmount())
                .is
                .equal(
                    0
                );
            expect(await  deployFunction.sqrtPriceLimitX96())
                .is
                .equal(
                    0
                );
            expect(await  deployFunction.allowedPriceSlippage())
                .is
                .equal(
                    1000000
                );
            expect(await  deployFunction.onHold())
                .is
                .equal(
                    false
                );
        });
        it ('ChnageTicks', async function () {
            await deployFunction.changeTicks([['100000000000000000','35000000000000000000', calculateTick(2600, 60), calculateTick(2800, 60),],]);
            console.log(await  deployFunction.tickLower());
            console.log(await  deployFunction.tickUpper());
            console.log(await  deployFunction.ticks[1]);


        })
    });
});
function calculateTick(price, tickSpacing) {
    const logTick = 46054 * Math.log10(Math.sqrt(price));
    return parseInt(logTick) + tickSpacing - (parseInt(logTick) % tickSpacing);
}
