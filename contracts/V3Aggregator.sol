//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// How it works:
// 1. We add strategies to the contract
// 2. Users can use our strategies to get maximized yeild by providing liquidity through us

contract UnboundUniswapV3Aggregator {
    using SafeMath for uint256;

    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;
    address public owner;

    struct Strategy {
        int24 _range0;
        int24 _range1;
        uint256 NFTCount; // this will be the highest LiquidityNFT ID for this strategy
        uint24 fee; // fee used by uniswap pool. different fee will have a different strategy ID
        bool valid;
    }

    struct LiquidityNFT {
        address token0;
        address token1;
        uint256 tokenId;
        uint256 totalShares;
        uint256 strategyId;
        address[] pendingUsers;
        uint256[] pendingDeposits;
        uint256 pendingIndex;
        
    }

    // strategyId -> strategy
    mapping(uint256 => Strategy) public strategies;
    uint256[] strategyIds;

    // strategyId -> LiquidityId -> LiquidityNFTStruct
    mapping(uint256 => mapping(uint256 => LiquidityNFT)) liquidityNFTs;
    
    // user shares
    // strategyId -> LiquidityId -> user -> # of stake shares
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) userShares;

    // look up LiquidityNFTId by strategyId and token addresses
    // strategyId -> token1/0 -> token0/1 - > liquidityStructId 
    mapping(uint256 => mapping(address => mapping(address => uint256))) findLiquidityStructId;

    // minimum amount for deposit. Can be changed.
    uint256 minDepositAmount;

    uint256 maxPending;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    /*
     * @param _positionManager Address of the Uniswap NFT position manager contract
     * @param _owner Address of the owner in control of admin functions
    */
    constructor(address _positionManager, address swapRouterAddress, address _owner)
    {
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(swapRouterAddress);
        owner = _owner;

        minDepositAmount = 100000000; // This may need to be moved to liquidity struct
        maxPending = 50;
    }

    /*
     * @notice Adds liquidity to the existing strategy
     * @param _strategyId Id of the strategy
     * @param _amount0 Amount of the stablecoin token (token0)
     */
    function addToPending(
        uint256 _strategyId,
        uint256 _liquidityId,
        uint256 _amount0,
    ) external {
        require(strategies[_strategyId].valid = true, "V3Aggregator: Invalid Strategy Id");
        require(strategies[_strategyId].NFTCount > _liquidityId, "V3Aggregator: Liquidity ID does not exist");
        require(_amount0 >= minDepositAmount, "V3Aggregator: Value must be greater");
        require(liquidityNFTs[_strategyId][_liquidityId].pendingIndex < maxPending, "V3Aggregator: You must wait until next rebase");
        require(IERC20(liquidityNFTs[_strategyId][_liquidityId].token0).balanceOf(msg.sender) >= _amount0);

        liquidityNFTs[_strategyId][_liquidityId].pendingUsers.push(msg.sender);
        liquidityNFTs[_strategyId][_liquidityId].pendingDeposits.push(_amount0);
        liquidityNFTs[_strategyId][_liquidityId].pendingIndex = liquidityNFTs[_strategyId][_liquidityId].pendingIndex.add(1);

        require(IERC20(liquidityNFTs[_strategyId][_liquidityId].token0).transferFrom(msg.sender, address(this), _amount0), "V3Aggregator: transfer failed");

    }

    /*
     * @notice Adds liquidity to the existing strategy
     * @param _strategyId Id of the strategy
     * @param _amount0 Amount of the token 0
     * @param _amount1 Amount of the token 1
     */
    function removeLiquidity(
        uint256 _strategyId, 
        uint256 _amount0, 
        uint256 _amount1
    ) external {
        // check how much user has added
        // calculate the price in USD of amount0 and amount1
        // decrease liquidity of the NFT position manager by calling decreaseLiquidity() function of the positionManager contract
        // return it to the user according to his pool weight
    }

    /*
     * @notice Adds liquidity to the existing strategy
     * @param _strategyId Id of the strategy
     * @param _pair addresses of both erc20 tokens
     * @param _amount0 Amount of the token 0
     * @param _amount1 Amount of the token 1
     */
    function initializeLiquidityPool(
        uint256 _strategyId, 
        address[2] _pair, 
        uint256 _amount0, 
        uint256 _amount1
    ) external override {
        require(strategies[_strategyId].valid, "V3Aggregator: Invalid strategy");
        // this function is called to create a new Liquidity NFT
        
        require(IERC20(_pair[0]).balanceOf(msg.sender) >= _amount0, "V3Aggregator: Insufficient Token0");
        require(IERC20(_pair[1]).balanceOf(msg.sender) >= _amount1, "V3Aggregator: Insufficient Token1");

        // Transfer tokens to contract -- potential vulnerability here, but should be safe because address(this) is the receiver
        require(IERC20(_pair[0]).transferFrom(msg.sender, address(this), _amount0), "V3Aggregator: transferFrom token0 failed");
        require(IERC20(_pair[1]).transferFrom(msg.sender, address(this), _amount1), "V3Aggregator: transferFrom token1 failed");

        // Approve maximum amount here so we do not need to do it again
        IERC20(_pair[0]).approve(address(positionManager), 99999999999999999999999999999999999);
        IERC20(_pair[1]).approve(address(positionManager), 99999999999999999999999999999999999);

        // Add liquidity

        (uint256 tokenId, /* uint128 liquidity */, /* uint256 amt0 */, /* uint256 amt1 */) = positionManager.mint({
            _pair[0],
            _pair[1],
            strategies[_strategyId].fee,
            strategies[_strategyId].range0,
            strategies[_strategyId].range1,
            _amount0,
            _amount1,
            0,         // This may need to be different
            0,         // This may need to be different
            address(this),
            block.timestamp.add(600) // 10 minutes.
        });

        // address(this) should now contain the NFT

        // get current liquidityID then update it
        uint256 liquidityID = strategies[_strategyId].NFTCount;
        strategies[_strategyId].NFTCount = strategies[_strategyId].NFTCount.add(1);

        // ORACLE -- get value of entire pool here (normalized to 18 decimals) + ANY FEES (there should be none at this point)

        uint256 totalValueInPool = _amount0.mul(2); // Assumes stablecoin is _amount0. Also assumes deposit of 50/50 on first add. This can be fixed for ratio. 

        // STAKE points - mint initial amount equal to totalValueInPool, which should be value of
        // amount1 + amount0
        userShares[_strategyId][liquidityID][msg.sender] = totalValueInPool;
        findLiquidityStructId[_strategyId][_pair[0]][_pair[1]] = liquidityID;
        findLiquidityStructId[_strategyId][_pair[1]][_pair[0]] = liquidityID;

        liquidityNFTs[_strategyId][liquidityID] = LiquidityNFT({
            token0: _pair[0],
            token1: _pair[1],
            tokenId: tokenId,
            totalShares: totalValueInPool,
            strategyId: _strategyId,
            pendingUsers: [],
            pendingDeposits: [],
            pendingIndex: 0;
        });
        // address to address mapping ADD
    }

    /*
     * GET functions
     */

    function getAllStrategyIDs() external view override returns(uint256[]) {
        return strategyIds;
    }

    function getStrategy(uint256 strategyId) external view override returns(
        int24 range0,
        int24 range1,
        uint256 NFTCount,
        uint24 fee,
        bool valid
    ) {
        range0 = strategies[strategyId]._range0;
        range1 = strategies[strategyId]._range1;
        NFTCount = strategies[strategyId].NFTCount;
        fee = strategies[strategyId].fee;
        valid = strategies[strategyId].valid; // will range0 or range1 ever be zero? If no, we can remove the valid bool.
    }

    function getLiquidityIdByPairAndStrategy(
        uint256 strategyId,
        address address0,
        address address1
    ) external view override returns(uint256) {
        return findLiquidityNFTId[strategyId][address0][address1];
    }

    function getLiquidityInfo(
        uint256 strategyId,
        uint256 liquidityId
    ) external view override returns(
        address token0,
        address token1,
        uint256 tokenId,
        uint256 totalShares
        // uint24 fee
    ) {
        token0 = liquidityNFTs[strategyId][liquidityId].token0;
        token1 = liquidityNFTs[strategyId][liquidityId].token1;
        tokenId = liquidityNFTs[strategyId][liquidityId].tokenId;
        totalShares = liquidityNFTs[strategyId][liquidityId].totalShares;
        // fee = liquidityNFTs[strategyId][liquidityId].fee;
    }

    function getSharesOfUser(
        address user,
        uint256 strategyId,
        uint256 liquidityId
    ) external view override returns(uint256) {
        return userShares[strategyId][liquidityId][user];
    }

    /*
     * Admin Functions
     */
    function addStrategy(
        uint256 _strategyId,
        int24 _range0,
        int24 _range1,
        uint24 fee
    ) external onlyOwner {
        require(strategies[_strategy].valid == false, "V3Aggregator: strategy ID already active");
        strategies[_strategy] = Strategy({
            _range0: _range0,
            _range1: _range1,
            NFTCount: 0,
            fee: fee,
            valid: true
        });
        strategyIds.push(_strategyId);
    }

    // this needs fixing
    function rebasePosition(
        uint256 _strategyId,
        uint256 _liquidityId,
        uint256 _tickUp,
        uint256 _tickLow,
        uint256 amtToSwap // we can change this. Just a temp method
    ) external onlyOwner {
        // remove all existing fees and liquidity first
        ( , , , , , , , , , , uint128 tokens0, uint128 tokens1) = positionManager.positions(liquidityNFTs[_strategyId][_liquidityId].tokenId);

        // We need to know the ratio here
        // this variable needs to be the total value of the NFT
        uint256 totalValueInStable = tokens0.mul(2); // placeholder: need to know ratio to calculate correct total
        
        uint256 totalStablecoin = tokens0; // value of stablecoin only.
        
        // remove liquidity
        positionManager.collect(INonfungiblePositionManager.CollectParams({
            tokenId: liquidityNFTs[_strategyId][_liquidityId].tokenId,
            recipeint: address(this),
            amount0Max: tokens0,
            amount1Max: tokens1
        }));

        // Burn liquidity. This is if we want to change ranges
        positionManager.burn(liquidityNFTs[_strategyId][_liquidityId].tokenId);

        uint256 shares;
        // give each pending user stake points
        for (uint256 i = 0; i < 50; i++) {
            shares = liquidityNFTs[_strategyId][_liquidityId].pendingDeposits[i].mul(liquidityNFTs[_strategyId][_liquidityId].totalShares).div(totalValueInStable);
            userShares[_strategyId][_liquidityId][liquidityNFTs[_strategyId][_liquidityId].pendingUsers[i]] = shares;
            liquidityNFTs[_strategyId][_liquidityId].totalShares = liquidityNFTs[_strategyId][_liquidityId].totalShares.add(shares);
            totalValueInStable = totalValueInStable.add(liquidityNFTs[_strategyId][_liquidityId].pendingDeposits[i]);
            totalStablecoin = totalStablecoin.add(liquidityNFTs[_strategyId][_liquidityId].pendingDeposits[i]);
        }

        // totalValueInStable should now include pending deposits
        
        // Swap
        uint256 amountOut = swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: liquidityNFTs[_strategyId][_liquidityId].token0,
            tokenOut: liquidityNFTs[_strategyId][_liquidityId].token1,
            fee: strategies[_strategyId].fee,
            recipient: address(this),
            deadline: block.timestamp.add(1000),
            amountIn: amtToSwap,
            amountOutMinimum: 0, // we can include a variable for this
            sqrtPriceLimitX96: 1020120, // I have no idea what goes here
        }));

        // mint liquidity
        (uint256 newId, , , ) = positionManager.mint(INonfungiblePositionManager.MintParams({
            token0: liquidityNFTs[_strategyId][_liquidityId].token0,
            token1: liquidityNFTs[_strategyId][_liquidityId].token1,
            fee: strategies[_strategyId].fee,
            tickLower: _tickLow,
            tickUpper: _tickUp,
            amount0Desired: totalStablecoin,
            amount1Desired: amountOut,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp.add(1000)
        }));

        liquidityNFTs[_strategyId][_liquidityId].tokenId = newId;

    }

    function changeMinDepositAmount(uint256 newAmt) external onlyOwner {
        require(newAmt > 0);
        minDepositAmount = newAmt;
        
    }
}
