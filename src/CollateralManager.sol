// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //moved to utils
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleStableCoin} from "./SimpleStableCoin.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";

contract CollateralManager is ReentrancyGuard {
    error CM__NeedsMoreThanZero();
    error CM__NotAllowedToken();
    error CM__TransferFailed();
    error CM__BreakHealthFactor();
    error CM__HealthFactorOk();
    error CM__WithDrawTooMuchCollateral();
    error CM__NotEnoughSSCToBurn();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateral means 100USD collateral, only considered as 50USD under this threshold, so if you want to get 100USD value, you need to collateral 100*(100/50) = 200USD, so 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating

    address private allowedToken;
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private userCollateral;
    mapping(address user => uint256 amount) private userMintedSsc;

    SimpleStableCoin private immutable i_ssc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event SSCMinted(address indexed user, uint256 indexed amountSSCToMint);
    event CollateralRedeemed(
        address indexed user, address indexed token, uint256 indexed amount, uint256 sscAmountBurned
    );
    event CollateralLiquidated(
        address indexed user, address indexed token, uint256 indexed amount, uint256 debtToCover
    );

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert CM__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert CM__NotAllowedToken();
        }
        _;
    }

    constructor(address tokenAddress, address priceFeedAddress, address sscAddress) {
        priceFeeds[tokenAddress] = priceFeedAddress;
        allowedToken = tokenAddress;
        i_ssc = SimpleStableCoin(sscAddress);
    }

    function depositCollateral(address tokenAddress, uint256 depositAmount)
        public
        moreThanZero(depositAmount)
        isAllowedToken(tokenAddress)
        nonReentrant
    {
        userCollateral[msg.sender][tokenAddress] += depositAmount;
        emit CollateralDeposited(msg.sender, tokenAddress, depositAmount);

        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), depositAmount);
        if (!success) {
            revert CM__TransferFailed();
        }
    }

    function mintSsc(uint256 amountSSCToMint) public moreThanZero(amountSSCToMint) nonReentrant {
        userMintedSsc[msg.sender] += amountSSCToMint;

        // Get User's Collateral Value (In USD)
        uint256 collateralValueInUsd = getAccountCollateralValueUSD(msg.sender, allowedToken);

        // Check if there are enough collateral to mint SSC
        uint256 userHealthFactor = _calculateHealthFactor(amountSSCToMint, collateralValueInUsd);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert CM__BreakHealthFactor();
        }

        // Update the amount of SSC
        i_ssc.mint(msg.sender, amountSSCToMint); //
        emit SSCMinted(msg.sender, amountSSCToMint);
    }

    function withdrawCollateral(address tokenAddress, uint256 withdrawAmount) public nonReentrant {
        // Check if there are enough collateral to withdraw
        if (userCollateral[msg.sender][tokenAddress] <= withdrawAmount) {
            revert CM__WithDrawTooMuchCollateral();
        }

        // Calculate the user's collateral value in USD after withdrawal
        uint256 collateralValueInUsd = getAccountCollateralValueUSD(msg.sender, tokenAddress);
        uint256 newCollateralValueInUsd = collateralValueInUsd - getUsdValue(tokenAddress, withdrawAmount);

        // Check if the new health factor would be below the minimum
        uint256 userHealthFactor = _calculateHealthFactor(userMintedSsc[msg.sender], newCollateralValueInUsd);
        /*console.log(collateralValueInUsd);
        console.log(newCollateralValueInUsd);
        console.log(userHealthFactor);
        console.log(i_ssc.totalSupply());*/
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert CM__BreakHealthFactor();
        }

        // Update the amount
        userCollateral[msg.sender][tokenAddress] -= withdrawAmount;

        // TRansfer collateral back to users
        bool success = IERC20(tokenAddress).transfer(msg.sender, withdrawAmount);
        if (!success) {
            revert CM__TransferFailed();
        }
    }

    function burnSsc(uint256 amountSscToBurn) public moreThanZero(amountSscToBurn) {
        userMintedSsc[msg.sender] -= amountSscToBurn;

        bool success = i_ssc.transferFrom(msg.sender, address(this), amountSscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert CM__TransferFailed();
        }

        i_ssc.burn(amountSscToBurn);
    }

    function redeemCollateral(address tokenAddress, uint256 redeemAmount, uint256 sscAmountToBurn)
        public
        moreThanZero(redeemAmount)
        isAllowedToken(tokenAddress)
    {
        //console.log(userCollateral[msg.sender][tokenAddress], userMintedSsc[msg.sender]);
        //console.log(redeemAmount, sscAmountToBurn);
        // Check if the user has enough collateral to redeem
        if (userCollateral[msg.sender][tokenAddress] < redeemAmount) {
            revert CM__WithDrawTooMuchCollateral();
        }
        // Update the amount
        userCollateral[msg.sender][tokenAddress] += redeemAmount;

        // Check if the user has enough SSC to burn
        if (userMintedSsc[msg.sender] < sscAmountToBurn) {
            revert CM__NotEnoughSSCToBurn();
        }

        // Burn SSC
        burnSsc(sscAmountToBurn);
        //console.log(userCollateral[msg.sender][tokenAddress], userMintedSsc[msg.sender]);

        // Transfer collateral back to user
        bool success = IERC20(tokenAddress).transfer(msg.sender, redeemAmount);
        if (!success) {
            revert CM__TransferFailed();
        }

        emit CollateralRedeemed(msg.sender, tokenAddress, redeemAmount, sscAmountToBurn);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor =
            _calculateHealthFactor(getAccountMintedSSC(user), getAccountCollateralValueUSD(user, collateral));
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert CM__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = (debtToCover * PRECISION / getUsdValue(collateral, debtToCover));
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;
        console.log(totalCollateral);
        redeemCollateral(collateral, totalCollateral, debtToCover);
        emit CollateralLiquidated(user, collateral, totalCollateral, debtToCover);
    }

    //Private functions
    function _calculateHealthFactor(uint256 totalSscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalSscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalSscMinted;
    }

    //Public & View Function
    function getAccountCollateralValueETH(address user, address tokenAddress) public view returns (uint256) {
        return userCollateral[user][tokenAddress];
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //The returned value will be ETH * 1e8, but the amount scale is 1e18, so need to x 1e10-additional feed precision
        //so price can mutiply amount at the same scale, and divide 1e18 at last
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountCollateralValueUSD(address user, address tokenAddress)
        public
        view
        returns (uint256 totalCollateralValueInUSD)
    {
        totalCollateralValueInUSD = getUsdValue(tokenAddress, userCollateral[user][tokenAddress]);
    }

    function getAccountMintedSSC(address user) public view returns (uint256) {
        return userMintedSsc[user];
    }

    function calculateHealthFactor(address user, address tokenAddress) public view returns (uint256) {
        return _calculateHealthFactor(getAccountMintedSSC(user), getAccountCollateralValueUSD(user, tokenAddress));
    }

    function reviseMintedSSCForTest(address user) public {
        userMintedSsc[user] += 1;
    }
}
