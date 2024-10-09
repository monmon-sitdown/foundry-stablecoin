// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {DeployCollateralManager} from "../../script/DeployCM.s.sol";
import {CollateralManager} from "../../src/CollateralManager.sol";
import {SimpleStableCoin} from "../../src/SimpleStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployCollateralManager deployer;

    CollateralManager public cm;
    SimpleStableCoin public ssc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address[] public tokenAddresses;
    address[] public feedAddresses;

    ERC20Mock private wethMock;
    ERC20Mock private wbtcMock;

    function setUp() public {
        deployer = new DeployCollateralManager();
        (ssc, cm, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
    }
}
