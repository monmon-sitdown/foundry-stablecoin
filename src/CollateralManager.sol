// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //moved to utils
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleStableCoin} from "./SimpleStableCoin.sol";

contract CollateralManager is ReentrancyGuard {
    error CM__NeedsMoreThanZero();
    error CM__NotAllowedToken();
    error CM__TransferFailed();

    error CM__TokenAddressesAndPriceFeedAddressLenNotSame();

    mapping(address user => mapping(address tokenAddr => uint256 amount)) public userCollateral;
    mapping(address tokenAddr => address priceFeed) private s_priceFeeds;
    address[] private allowedTokenAddr;
    SimpleStableCoin private immutable i_ssc;

    event CollateralDeposited(address indexed user, address indexed tokenAddr, uint256 indexed amount);

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
}
