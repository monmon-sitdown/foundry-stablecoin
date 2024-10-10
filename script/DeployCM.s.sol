// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {SimpleStableCoin} from "../src/SimpleStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployCollateralManager
 * @author monmon
 * @dev A script to deploy the CollateralManager and SimpleStableCoin contracts.
 *      This contract also initializes price feeds and ERC20 token addresses.
 *      It sets up the necessary configuration for the collateral manager to function.
 */
contract DeployCollateralManager is Script {
    //event ContractsDeployed(address indexed sscAddress, address indexed collateralManagerAddress);
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /**
     * @dev Deploys the SimpleStableCoin and CollateralManager contracts.
     * @return ssc The address of the deployed SimpleStableCoin contract.
     * @return collateralManager The address of the deployed CollateralManager contract.
     * @return helperConfig The instance of the HelperConfig contract used for configuration.
     * @notice This function retrieves the active network configuration, which includes:
     *         - The addresses of allowed ERC20 tokens (WETH and WBTC).
     *         - The addresses of their corresponding price feeds.
     *         - The deployer key used for deploying the contracts.
     * @dev Emits a {ContractsDeployed} event upon successful deployment.
     */
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
