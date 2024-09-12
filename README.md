# Fixed-Weight Pool for uniswap v4

### **A auto-rebalance LP portfolio for Uniswap v4 Hooks 🦄**

The `Fixed-Weight` Pool gives the Liquidity Provider a auto-rebalance portfolio that
consists of fixed value-weighted ratio of the two assets based on the internal pricing curve.

If we set the weight of the X token to 0.5 and Y token to 0.5, the LP will have a portfolio that
is 50% <-> 50% by each value no matter how the swap change each token's reserve.

## Trading Curve

Given each reserves and weights, the liquidity can be solved by:

```
(Rx^Wx) * (Ry^Wy) = L
```

The price of Token X respect to Token Y is defined:

```
P = (Wx / Wy) * (Ry / Rx)
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
