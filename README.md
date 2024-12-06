# CollateralManager Contract

## Project Overview

The `CollateralManager` contract is a smart contract used to manage collateral deposits, minting, redemption, and liquidation in a stablecoin system (SSC). The system accepts external collateral (wETH) and maintains algorithmic stability, aiming to peg the stablecoin 1:1 to USD.

### Features

- **External Collateral**: The system accepts only external assets as collateral.
- **USD Peg**: The stablecoin is designed to maintain a 1:1 peg with the US Dollar.
- **Algorithmic Stability**: There is no governance mechanism; the system’s stability is controlled algorithmically.
- **DAI-like**: Similar to MakerDAO’s DAI, but without governance, fees, and with only wETH as the collateral asset.

## Installation and Usage

### Prerequisites

- Solidity compiler version 0.8.20 or later
- OpenZeppelin contracts library
- Chainlink price feed contract

### Install Dependencies

Use `forge` or `hardhat` to compile and deploy the contract. Ensure the installation of the `openzeppelin` and `chainlink` libraries.

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

### Contract Deployment

When initializing the `CollateralManager` contract, the following address parameters must be provided:

- `tokenAddress`: Address of the accepted collateral token (e.g., wETH address)
- `priceFeedAddress`: Chainlink price feed contract address for the token
- `sscAddress`: SSC stablecoin contract address

### Key Functions

1. **Deposit Collateral** : Users can deposit collateral assets (e.g., wETH) into the contract for future minting of SSC.
2. **Mint SSC** : Users can mint SSC by providing sufficient collateral. The system calculates the health factor based on the current collateral value and minted SSC amount, ensuring no over-borrowing.
3. **Redeem Collateral** : Users can redeem their collateral by burning SSC.
4. **Withdraw Collateral** : Users can withdraw their deposited collateral, but the withdrawal must ensure the health factor remains within acceptable limits.
5. **Burn SSC** : Users can burn their minted SSC, reducing the total supply.
6. **Liquidation** : If a user's health factor falls below the minimum requirement, the contract can liquidate their collateral.

### Events

- `CollateralDeposited`: Emitted when a user deposits collateral.
- `SSCMinted`: Emitted when a user mints SSC.
- `CollateralRedeemed`: Emitted when a user redeems collateral.
- `CollateralLiquidated`: Emitted when a user’s collateral is liquidated.

### Error Handling

- `CM__NeedsMoreThanZero:` Thrown when a parameter is zero or negative.
- `CM__NotAllowedToken`: Thrown when an unsupported token is used.
- `CM__TransferFailed`: Thrown when a transfer fails.
- `CM__BreakHealthFactor`: Thrown when the health factor falls below the minimum threshold.
- `CM__HealthFactorOk`: Thrown when the health factor meets requirements.
- `CM__WithDrawTooMuchCollateral`: Thrown when a user attempts to withdraw more collateral than they have.
- `CM__NotEnoughSSCToBurn`: Thrown when the burn amount exceeds the user's balance.

### Important Constant

- `ADDITIONAL_FEED_PRECISION`: Precision for price data
- `PRECISION`: Precision constant used for calculations
- `LIQUIDATION_THRESHOLD`: The liquidation threshold, below which a user’s collateral will be liquidated
- `LIQUIDATION_PRECISION`: Precision used for liquidation calculations
- `MIN_HEALTH_FACTOR`: Minimum health factor required to prevent liquidation
- `LIQUIDATION_BONUS`: Bonus offered during liquidation

### Public View Functions

- `getAccountCollateralValueETH(address user, address tokenAddress)`: Returns the total collateral value of a user’s account in ETH.
- `getUsdValue(address token, uint256 amount)`: Returns the USD value of a given amount of token.
- `getAccountCollateralValueUSD(address user, address tokenAddress)`: Returns the total collateral value of a user’s account in USD.

### Other

To prevent reentrancy attacks, this contract uses OpenZeppelin’s ReentrancyGuard to ensure that critical operations are not exploited through reentrancy.
