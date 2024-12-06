// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
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
    address public tokenAddresses;
    address public priceFeedAddresses;

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
        console.log("Deployed helperConfig at:", address(helperConfig));

        (address wethUsdPriceFeed, address weth, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        tokenAddresses = weth;
        priceFeedAddresses = wethUsdPriceFeed;
        console.log("weth address at:", weth);
        console.log("priceFeedAddress:", priceFeedAddresses);

        vm.startBroadcast(deployerKey);
        SimpleStableCoin ssc = new SimpleStableCoin();
        console.log("Deployed SimpleStableCoin at:", address(ssc));

        CollateralManager collateralManager = new CollateralManager(tokenAddresses, priceFeedAddresses, address(ssc));
        console.log("Deployed CollateralManager at:", address(collateralManager));
        ssc.transferOwnership(address(collateralManager));

        //emit ContractsDeployed(address(ssc), address(collateralManager));

        vm.stopBroadcast();
        return (ssc, collateralManager, helperConfig);
    }
}

/**
 * == Logs ==
 *   Deployed helperConfig at: 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141
 *   weth address at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
 *   priceFeedAddress: 0x5FbDB2315678afecb367f032d93F642f64180aa3
 *   Deployed SimpleStableCoin at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
 *   Deployed CollateralManager at: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
 */
