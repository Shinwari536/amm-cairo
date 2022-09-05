# AMM (Automated Market Maker)
Automated Market Maker (AMM), as you might guess from the name, is a mechanism that allows a simple way for market-making. In an AMM we have two types of users: traders and liquidity providers.

Traders perform trades against liquidity pools. Every liquidity pool supports two or more assets, and allows trading according to some predetermined formula. This means that for every quantity of some asset that you want to buy, you can compute exactly how much you’d have to pay to receive it (given the current state of the pool).

Unlike the regular order book matching, it’s very easy to write and run AMM logic. So easy that it can be fully deployed on Ethereum and still provide efficient, inexpensive trading. The user interface is extremely simple – you only need to specify the quantity of the assets you want to trade, and you know you’ll get a fair rate. An AMM is also very friendly for the Liquidity Providers – anyone can easily provide liquidity (invest money) and potentially profit by doing so.


# Explaination
In this tutorial we will write Cairo code that implements a very simple AMM. The system we are going to build will handle swaps between users and the AMM. Following the release StarkNet Planets Alpha, we released a tutorial that implements the same functionality presented here, only as a StarkNet contract. Comparing those two tutorials can be a fun exercise that highlights the power of StarkNet. To keep the tutorial manageable, a few things were omitted (after reading this page, and assuming you have read the previous pages of the tutorial, you should be able to add all of them by yourself):

1. Only two tokens are supported, and the AMM supports a specific trading curve.

2. Signature verification – in most scenarios you’ll need to verify that the user intended to make the transaction.

3. One direction trades – The system only supports buying one token in exchange for the other one, in one direction.

4. Users providing liquidity (off-chain) – providing liquidity can be handled on-chain with the proposed system, but you can also implement an off-chain version, where a user can move funds from their (off-chain) account to the AMM.

5. Deposits and withdrawals – To make it a real system, you’ll have to allow users to deposit and withdraw their funds. This can be done by outputting the amount deposited or withdrawn and performing the equivalent operation on-chain, based on this output.

6. Trading fees – usually some fee is taken from the traders, to incentivize liquidity providers.



source: https://www.cairo-lang.org/docs/hello_cairo/amm.html
