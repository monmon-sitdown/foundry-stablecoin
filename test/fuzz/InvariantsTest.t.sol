// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DeployCollateralManager} from "../../script/DeployCM.s.sol";
import {CollateralManager} from "../../src/CollateralManager.sol";
import {SimpleStableCoin} from "../../src/SimpleStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Handler} from "./Handler.t.sol";

//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//What are the invariants?
//1. The total supply of DSC should be less than the total value of collateral
//2. Getter view functions should never revert <- evergreen invariant

contract invariantsTest is StdInvariant, Test {
    DeployCollateralManager deployer;
    CollateralManager ssccm;
    SimpleStableCoin ssc;
    HelperConfig config;

    address public weth;

    Handler handler;

    function setUp() external {
        deployer = new DeployCollateralManager();
        (ssc, ssccm, config) = deployer.run();
        (, weth,) = config.activeNetworkConfig();

        handler = new Handler(ssccm, ssc);
        targetContract(address(handler));
        //don't call redeemcollateral, unless there is collateral to redeem
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = ssc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(ssccm));

        uint256 wethValue = ssccm.getUsdValue(weth, wethDeposted);

        console.log("wethValue: %s", wethValue);

        console.log("total supply: %s", totalSupply);
        console.log("Times mint called: %d", handler.timesMintIsCalled());

        assert(wethValue >= totalSupply);
    }

    function invariant_gettersCantRevert() public view {
        //ssccm.getAccountCollateralValueETH();
        //ssccm.getUsdValue(address token, uint256 amount)
        //ssccm.getAccountCollateralValueUSD(address user, address tokenAddress)
        //ssccm.getAccountMintedSSC(address user) public view returns (uint256)
        //ssccm.getCollateralTokenPriceFeed(address token)
        //sscm.getCollateralBalanceOfUser(address user, address token)
        ssccm.getAllowedToken();
    }
}
