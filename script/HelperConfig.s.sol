// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @author monmon
 * @dev A contract to configure network-specific parameters for deployment.
 *      It provides a way to set up price feeds and token addresses based on the active network.
 *      The contract determines if it is deployed on the Sepolia network or a local Anvil network,
 *      and initializes the relevant configuration accordingly.
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8; //mock price
    int256 public constant BTC_USD_PRICE = 1000e8; //mock price
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public GANACHE_PRIVATE_KEY = 0xb9c1fd6b4a7d758cf0dcf77295ab143088753c3e48da50737727d6c8aef104e3;

    /**
     * @dev Constructor that initializes the active network configuration based on the current chain ID.
     *      If the chain ID is for Sepolia, it retrieves the Sepolia configuration.
     *      Otherwise, it creates a new configuration for the Anvil network.
     */
    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /**
     * @dev Retrieves the network configuration for the Sepolia network.
     * @return sepoliaNetworkConfig The configuration containing addresses for WETH and WBTC price feeds,
     *         as well as their corresponding ERC20 token addresses and deployer key.
     */
    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /**
     * @dev Retrieves or creates the network configuration for the Anvil network.
     *      If an active network configuration already exists, it returns that.
     *      Otherwise, it deploys mock price feeds and ERC20 tokens for testing purposes.
     * @return anvilNetworkConfig The configuration containing addresses for WETH and WBTC price feeds,
     *         as well as their corresponding ERC20 token addresses and deployer key.
     * @notice This function uses the Chainlink MockV3Aggregator for price feeds and
     *         ERC20Mock tokens for testing.
     */
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            weth: address(wethMock),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            wbtc: address(wbtcMock),
            //deployerKey: GANACHE_PRIVATE_KEY //DEFAULT_ANVIL_PRIVATE_KEY
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
