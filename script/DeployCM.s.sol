// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {SimpleStableCoin} from "../src/SimpleStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployCollateralManager is Script {
    //event ContractsDeployed(address indexed sscAddress, address indexed collateralManagerAddress);
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (SimpleStableCoin, CollateralManager, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        SimpleStableCoin ssc = new SimpleStableCoin();

        CollateralManager collateralManager = new CollateralManager(tokenAddresses, priceFeedAddresses, address(ssc));
        ssc.transferOwnership(address(collateralManager));

        //emit ContractsDeployed(address(ssc), address(collateralManager));

        vm.stopBroadcast();
        return (ssc, collateralManager, helperConfig);
    }
}
