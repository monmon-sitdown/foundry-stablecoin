// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //moved to utils
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleStableCoin} from "./SimpleStableCoin.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title CollateralManager
 * @author monmon
 * @dev This contract manages the collateral for the SimpleStableCoin.
 *      It allows users to deposit collateral in approved ERC20 tokens.
 *      This contract manages the minting and collateralization of SSC tokens.
 *      The contract uses a price feed to validate the allowed tokens.
 *      It is designed to prevent reentrancy attacks using the ReentrancyGuard.
 */
contract CollateralManager is ReentrancyGuard {
    error CM__NeedsMoreThanZero();
    error CM__NotAllowedToken();
    error CM__TransferFailed();

    error CM__TokenAddressesAndPriceFeedAddressLenNotSame();
    error CM__MintFailed();

    error CM__BreakHealthFactor(uint256 healthFactor);

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateral means 100USD collateral, only considered as 50USD under this threshold, so if you want to get 100USD value, you need to collateral 100*(100/50) = 200USD, so 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 public constant MAX_SSC_PER_USER = 2000000 ether; // Set a limitation

    mapping(address user => mapping(address tokenAddr => uint256 amount)) public userCollateral;
    mapping(address tokenAddr => address priceFeed) private s_priceFeeds;
    address[] private allowedTokenAddr;
    SimpleStableCoin private immutable i_ssc;
    mapping(address user => uint256 amount) public userSSCminted;

    /**
     * @dev Emitted when collateral is successfully deposited.
     * @param user The address of the user who deposited collateral.
     * @param tokenAddr The address of the token being deposited.
     * @param amount The amount of tokens deposited.
     */
    event CollateralDeposited(address indexed user, address indexed tokenAddr, uint256 indexed amount);
    event SSCMinted(address indexed user, uint256 amount);
    event CollateralRedeemed(address from, address to, address tokenAddr, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert CM__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert CM__NotAllowedToken();
        }
        _;
    }

    /**
     * @dev Constructor to initialize the CollateralManager contract.
     * @param tokenAddresses An array of addresses for the allowed ERC20 tokens.
     * @param priceFeedAddresses An array of addresses for the corresponding price feeds.
     * @param sscAddress The address of the SimpleStableCoin contract.
     * @notice The lengths of tokenAddresses and priceFeedAddresses must be the same.
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address sscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert CM__TokenAddressesAndPriceFeedAddressLenNotSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            allowedTokenAddr.push(tokenAddresses[i]);
        }
        i_ssc = SimpleStableCoin(sscAddress);
    }

    /**
     * @dev Deposit collateral in an approved ERC20 token.
     * @param tokenAddress The address of the ERC20 token to be deposited.
     * @param amount The amount of the token to deposit.
     * @notice This function will revert if:
     *         - The amount is zero.
     *         - The token is not allowed (not present in the price feed mapping).
     *         - The transfer of tokens fails.
     * @dev This function is non-reentrant to prevent attacks during the transfer process.
     * Emits a {CollateralDeposited} event upon successful deposit.
     */
    function depositCollateral(address tokenAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenAddress)
        nonReentrant
    {
        //Update the amount of collateral in user account
        userCollateral[msg.sender][tokenAddress] += amount;

        emit CollateralDeposited(msg.sender, tokenAddress, amount);

        //Transfer the token to the contract
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert CM__TransferFailed();
        }
    }

    /**
     * Mints SSC tokens for the caller. SSC is pegged to USD.
     * @dev The amount of SSC to mint cannot exceed the maximum allowed per user.
     *      The caller's health factor is checked to ensure they have sufficient collateral.
     * @param amountSSCToMint amountSSCToMint The amount of SSC tokens to mint.
     * @custom:error CM__MintFailed The minting process has failed.
     */
    function mintSsc(uint256 amountSSCToMint) public moreThanZero(amountSSCToMint) nonReentrant {
        uint256 totalMinted = userSSCminted[msg.sender] + amountSSCToMint;
        // Check if the SSC that user minted exceeds the limitation
        if (totalMinted > MAX_SSC_PER_USER) {
            revert CM__MintFailed();
        }

        userSSCminted[msg.sender] = totalMinted;
        //Check if they minted too much(SSC > ETH e.g. $150 SSC, $100ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_ssc.mint(msg.sender, amountSSCToMint);
        if (!minted) {
            revert CM__MintFailed();
        }
        // Emit SSCMinted event after successful minting
        emit SSCMinted(msg.sender, amountSSCToMint);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        //1. health factor must be over 1 after collateral pulled
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        //(uint256 totalSscMinted, uint256 collateralValueInUsd) = _getAccountInformation(msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////
    /// Private Functions ////
    //////////////////////////

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        userCollateral[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert CM__TransferFailed();
        }
    }

    /**
     * @notice Retrieves the total SSC minted and the collateral value in USD for a user.
     * @param user The address of the user whose information is being retrieved.
     * @return totalSscMinted The total amount of SSC minted by the user.
     * @return collateralValueInUsd The total collateral value of the user in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalSscMinted, uint256 collateralValueInUsd)
    {
        totalSscMinted = userSSCminted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Calculates the health factor based on the total SSC minted and the collateral value.
     * @param totalSscMinted The total amount of SSC minted.
     * @param collateralValueInUsd The total collateral value in USD.
     * @return The calculated health factor.
     */
    function _calculateHealthFactor(uint256 totalSscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalSscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalSscMinted;
    }

    /**
     * @notice Computes the health factor for a user.
     * @param user The address of the user.
     * @return The user's health factor.
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total SSC minted
        //total collateral VALUE
        (uint256 totalSscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalSscMinted, collateralValueInUsd);
    }

    /**
     * @notice Reverts if the user's health factor is below the minimum threshold.
     * @param user The address of the user to check.
     * @custom:error CM__BreakHealthFactor The user's health factor is below the minimum threshold.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        //Check health factor do they have enough collateral
        //Revert if they dont have Hf = Sum(collaterali in ETH) x Liquidation / Total Borrows in ETH
        //if Hf < 1, then liquidate
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert CM__BreakHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////
    //// Public View Functions//
    ////////////////////////////
    /**
     * @notice Retrieves the USD value of a specified amount of a token.
     * @param token The address of the token to check.
     * @param amount The amount of the token to convert to USD.
     * @return The USD value of the specified amount of the token.
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //The returned value will be ETH * 1e8, but the amount scale is 1e18, so need to x1e10-additional feed precision
        //so price can mutiply amount at the same scale, and divide 1e18 at last
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice Calculates the total collateral value in USD for a user.
     * @param user The address of the user whose collateral value is being calculated.
     * @return totalCollateralValueInUsd The total collateral value of the user in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through each collateral tokens, get the total value
        for (uint256 i = 0; i < allowedTokenAddr.length; i++) {
            address token = allowedTokenAddr[i];
            uint256 amount = userCollateral[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
            //console.log(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Calculates the health factor based on total SSC minted and collateral value.
     * @param totalSscMinted The total amount of SSC minted.
     * @param collateralValueInUsd The total collateral value in USD.
     * @return The calculated health factor.
     */
    function calculateHealthFactor(uint256 totalSscMinted, uint256 collateralValueInUsd)
        public
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalSscMinted, collateralValueInUsd);
    }
}
