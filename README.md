# Unbound's Uniswap V3 Liquidity Aggregation Contract

Aggregator contract is responsible for holding the liquidity and rebalancing it to get maximum yeilds from Uniswap V3. Users can pick the strategy of their choice and add liquidity. The strategy owner manages the liquidity of the users,in return the strategy owner can charge fee.

A strategy can be deployed by using standard strategy interface as described in `/interfaces/IUnboundStrategy.sol`

As users deposits the liquidity, they get share representing their liquidity in the pool.

A strategy owner can perform following actions to manage user's liquidity.

1. Only Range Order: Place only the range order between two ranges. The remaning liquidity after deploying to ranges will be stored as unused amounts
2. Range Order and Limit Order: Places range order and the remaninng liquidity is deployed to limit order.
3. Hold: Strategy owner can hold the liquidity in the aggregator contract.
4. Swap and Range Order: User can perform a swap and then put all the liquidity in range order to use 100% of the liquidity.
