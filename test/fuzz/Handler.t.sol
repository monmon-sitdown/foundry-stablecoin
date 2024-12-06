// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {CollateralManager} from "../../src/CollateralManager.sol";
import {SimpleStableCoin} from "../../src/SimpleStableCoin.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    CollateralManager public ssccm;
    SimpleStableCoin public ssc;

    ERC20Mock weth;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;

    MockV3Aggregator public ethUsdPriceFeed;

    constructor(CollateralManager _sscCM, SimpleStableCoin _ssc) {
        ssccm = _sscCM;
        ssc = _ssc;

        address collateralToken = ssccm.getAllowedToken();
        weth = ERC20Mock(collateralToken);

        ethUsdPriceFeed = MockV3Aggregator(ssccm.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 amountCollateral) public {
        ERC20Mock collateral = weth;
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(ssccm), amountCollateral);
        ssccm.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function withdrawCollateral(uint256 amountCollateral) public {
        ERC20Mock collateral = weth;
        uint256 maxCollateral = ssccm.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateral);

        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        ssccm.withdrawCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount) public {
        uint256 totalDscMinted = ssccm.getAccountMintedSSC(msg.sender);
        uint256 collateralValueInUsd = ssccm.getAccountCollateralValueUSD(msg.sender, address(weth));
        uint256 maxDscToMint = collateralValueInUsd / 2 - totalDscMinted;
        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 1, maxDscToMint);
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        ssccm.mintSsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function updateCollateralPrice(uint96 newPrice) public {
        int256 intNewPrice = int256(uint256(newPrice));
        ERC20Mock collateral = weth;
        MockV3Aggregator priceFeed = MockV3Aggregator(ssccm.getCollateralTokenPriceFeed(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }
}
