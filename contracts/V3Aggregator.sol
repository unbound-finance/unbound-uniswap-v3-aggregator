//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

// How it works:
// 1. We add strategies to the contract
// 2. Users can use our strategies to get maximized yeild by providing liquidity through us

contract UnboundUniswapV3Aggregator {
    address public positionManager;
    address public owner;

    struct Position {
        address token0;
        address token1;
        uint256 valueInUSD;
        uint256 shareOfToken0;
    }

    struct Strategy {
        uint256 _range0;
        uint256 _range1;
    }

    mapping(uint256 => Strategy) public strategies;
    mapping(address => Position) public positions;

    /*
     * @param _positionManager Address of the Uniswap NFT position manager contract
     * @param _owner Address of the owner in control of admin functions
     */
    constructor(INonfungiblePositionManager _positionManager, address _owner)
        public
    {
        positionManager = _positionManager;
        owner = _owner;
    }

    /*
     * @notice Adds liquidity to the existing strategy
     * @param _strategyId Id of the strategy
     * @param _amount0 Amount of the token 0
     * @param _amount1 Amount of the token 1
     */
    function addLiquidity(
        uint256 _strategyId,
        uint256 _amount0,
        uint256 _amount1
    ) public {
        // calculate value of liquidity using Chainlink
        // calculate percentage of the token0
        // store the values in position struct 
        // take tokenId from the strategy mapping
        // add liquidity to the NFT position manager by calling increaseLiquidity() function of the positionManager contract
    }

    /*
     * @notice Adds liquidity to the existing strategy
     * @param _strategyId Id of the strategy
     * @param _amount0 Amount of the token 0
     * @param _amount1 Amount of the token 1
     */
    function removeLiquidity(uint256 _strategyId, uint256 _amount0, uint256 _amount1) public {
        // check how much user has added
        // calculate the price in USD of amount0 and amount1
        // decrease liquidity of the NFT position manager by calling decreaseLiquidity() function of the positionManager contract
        // return it to the user according to his pool weight
    }

    /*
     * Admin Functions
     */
    function addStrategy(
        uint8 _strategyId,
        uint256 _range0,
        uint256 _range1
    ) {
        // store the strategy in struct of mapping
        // mint the NTF
        // store in the mapping
    }

    function rebalanceStrategy(
        uint8 _strategyId,
        uint256 _token0Range,
        uint256 _token1Range
    ) {}
}
