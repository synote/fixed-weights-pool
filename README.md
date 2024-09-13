# Fixed-Weight Pool for uniswap v4

### **A auto-rebalance LP portfolio for Uniswap v4 Hooks 🦄**

The `Fixed-Weight` Pool gives the Liquidity Provider a auto-rebalance portfolio that
consists of fixed value-weighted ratio of the two assets based on the internal pricing curve.

If we set the weight of the X token to 0.5 and Y token to 0.5, the LP will have a portfolio that
is 50% <-> 50% by each value no matter how the swap change each token's reserve.

## Mechanism of swap

The Fixed Weight trading curve create a value-weighted portfolio of assets. The liquidity pool is
defined by weight and swap fee. The value ratio of two assets remain stable when swapping which
rebalance the portfolio reserve and keep dollar value balanced.

For example, we may set a pool with weight 80% of ETH and weight 20% of DAI to rebalance the
portfolio 80%:20% and earn swapping fee for providing liquidity.

### Trading Curve

Given each reserves and weights, the liquidity can be solved by:

```
(Rx^Wx) * (Ry^Wy) = L
```

The price of Token X respect to Token Y is defined:

```
P = (Wx / Wy) * (Ry / Rx)
```

The delta of reserve X when adding liquidity is:

```
ΔL = L(ΔX/X)
```

## Forge Installation

*Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:*

```
foundryup
```

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```
