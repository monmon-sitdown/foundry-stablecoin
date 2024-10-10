// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {DeployCollateralManager} from "../../script/DeployCM.s.sol";
import {CollateralManager} from "../../src/CollateralManager.sol";
import {SimpleStableCoin} from "../../src/SimpleStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * @title CMTest
 * @dev A test contract for the CollateralManager and SimpleStableCoin.
 *      This contract sets up the environment for testing the functionality
 *      of the CollateralManager, including depositing collateral,
 *      handling edge cases like zero deposits and unsupported tokens.
 */
contract CMTest is Test {
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

    address public user = makeAddr("user");

    uint256 public constant STARTING_USER_BALANCE = 1000 ether;

    /**
     * @dev Sets up the testing environment before each test.
     *      Deploys the DeployCollateralManager script, initializes the
     *      CollateralManager and SimpleStableCoin contracts, and mints
     *      mock WETH and WBTC tokens for the user.
     *      The user's starting balance is set to 10 ether.
     */
    function setUp() public {
        deployer = new DeployCollateralManager();
        (ssc, cm, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        // Deploy Mock Tokens
        wethMock = ERC20Mock(weth);
        wbtcMock = ERC20Mock(wbtc);
        //The user mints some tokens
        wethMock.mint(user, STARTING_USER_BALANCE);
        wbtcMock.mint(user, STARTING_USER_BALANCE);
    }

    ////////////////Test Deposit///////////////////

    /**
     * @dev Tests the deposit of collateral into the CollateralManager.
     *      The user approves a specified amount of WETH and deposits it.
     *      Asserts that the expected deposited amount matches the actual
     *      collateral amount recorded for the user in the CollateralManager.
     */
    function testDepositCollateral() public {
        uint256 amountDeposit = 10 ether;

        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);

        //Deposits collateral
        cm.depositCollateral(address(wethMock), amountDeposit);

        //Check the collateral amount of user account
        uint256 expectedDepositedAmount = cm.userCollateral(user, address(wethMock));
        vm.stopPrank();

        assertEq(expectedDepositedAmount, amountDeposit);
    }

    /**
     * @dev Tests that a deposit of zero amount reverts the transaction.
     *      Expects the revert reason to match the defined error in
     *      CollateralManager indicating that the amount must be greater than zero.
     */
    function testDepositZeroAmount() public {
        //Expect Revert
        vm.expectRevert(CollateralManager.CM__NeedsMoreThanZero.selector);
        cm.depositCollateral(address(wethMock), 0);
    }

    /**
     * @dev Tests the deposit of an unsupported token into the CollateralManager.
     *      Mints a new ERC20Mock token for the user and attempts to deposit it.
     *      Expects the transaction to revert with an error indicating
     *      that the token is not allowed for collateral deposits.
     */
    function testDepositNotAllowedToken() public {
        uint256 amountDeposit = 10 ether;
        ERC20Mock anotherToken = new ERC20Mock();
        vm.startPrank(user);
        anotherToken.mint(user, amountDeposit);
        anotherToken.approve(address(cm), amountDeposit);

        vm.expectRevert(CollateralManager.CM__NotAllowedToken.selector);
        cm.depositCollateral(address(anotherToken), amountDeposit);
        vm.stopPrank();
    }

    /**
     * @dev Tests the scenario where the transfer of collateral fails.
     *      Mocks the transferFrom function to return false, simulating
     *      a transfer failure. Expects the transaction to revert with
     *      an error indicating that the transfer failed.
     */
    function testTransferFailed() public {
        vm.startPrank(user);
        // mock transferFrom failed
        vm.mockCall(
            address(wethMock), abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(false)
        );

        // 期望抛出异常
        vm.expectRevert(CollateralManager.CM__TransferFailed.selector);
        cm.depositCollateral(address(wethMock), 10 ether);
        vm.stopPrank();
    }

    ///////////////Test Mint/////////////

    function testMintSsc() public {
        //Deposits collateral
        uint256 amountDeposit = 100;

        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);

        cm.depositCollateral(address(wethMock), amountDeposit);

        //mint SSC
        uint256 amountToMint = 50; //200%collateral

        vm.startPrank(user);
        cm.mintSsc(amountToMint);
        vm.stopPrank();

        uint256 totalMinted = cm.userSSCminted(user);
        assertEq(totalMinted, amountToMint);
    }

    function testMintSscExceedsLimit() public {
        uint256 MAX_SSC_PER_USER = 1000;
        uint256 amountToMint = MAX_SSC_PER_USER + 1;

        //mint
        vm.startPrank(user);
        vm.expectRevert(CollateralManager.CM__MintFailed.selector);
        cm.mintSsc(amountToMint);
        vm.stopPrank();
    }

    function testMintSscHealthFactorBroken() public {
        uint256 PRECISION = 1e18;
        // Deposit Collateral
        uint256 amountDeposit = 100 ether;
        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);
        cm.depositCollateral(address(wethMock), amountDeposit);

        // Calculate the health factor
        // Actually the ssc anchored to USD
        uint256 amountToMint = 90 ether; // over 50eth which is the limitation
        uint256 valueToMint = amountToMint * 2000; //mock price of eth is 2000

        uint256 collateralValueInUsd = cm.getAccountCollateralValue(user); // get the usd value of collteral
        uint256 currentHealthFactor = cm.calculateHealthFactor(valueToMint, collateralValueInUsd);
        console.log(collateralValueInUsd / PRECISION);
        console.log(currentHealthFactor < PRECISION);

        vm.expectRevert(abi.encodeWithSelector(CollateralManager.CM__BreakHealthFactor.selector, currentHealthFactor));
        cm.mintSsc(valueToMint);
        vm.stopPrank();
    }

    //////////////////Test Redeem Collateral//////////////////
    function testRedeemCollateral() public {
        // Deposit Collateral
        uint256 amountDeposit = 100 ether;
        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);
        cm.depositCollateral(address(wethMock), amountDeposit);

        uint256 amountToMint = 10 ether;
        uint256 valueToMint = amountToMint * 2000;
        cm.mintSsc(valueToMint);

        // Arrange
        uint256 redeemAmount = 10 ether; // The amount of redeem

        // Act
        cm.redeemCollateral(address(wethMock), redeemAmount);

        // Assert
        uint256 expectedBalance = amountDeposit - redeemAmount;
        uint256 userBalance = cm.userCollateral(user, address(wethMock)); // 假设有这个函数
        assertEq(userBalance, expectedBalance, "User collateral balance should be updated correctly.");
    }

    function testRedeemCollateralHealthFactorBroken() public {
        // Deposit Collateral
        uint256 amountDeposit = 100 ether;
        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);
        cm.depositCollateral(address(wethMock), amountDeposit);

        uint256 amountToMint = 10 ether;
        uint256 valueToMint = amountToMint * 2000;
        cm.mintSsc(valueToMint);

        // Arrange
        uint256 redeemAmount = 60 ether; // 试图赎回超过用户的抵押品数量
        // 使健康因子破裂

        // Act & Assert
        vm.expectRevert(CollateralManager.CM__BreakHealthFactor.selector);
        cm.redeemCollateral(address(wethMock), redeemAmount);
    }

    //////////////Test public view functions////////////////
    function testGetUsdValue() public view {
        //mock price of eth is 2000
        uint256 amount = 1 ether;
        uint256 expectedUsdValue = amount * 2000;
        uint256 usdValue = cm.getUsdValue(address(wethMock), amount);

        assertEq(usdValue, expectedUsdValue);
    }

    function testGetAccountCollateralValue() public {
        // Deposit
        uint256 amountDeposit = 100 ether;
        vm.startPrank(user);
        wethMock.approve(address(cm), amountDeposit);
        cm.depositCollateral(address(wethMock), amountDeposit);

        // Get value
        uint256 totalCollateralValueInUsd = cm.getAccountCollateralValue(user);
        vm.stopPrank();

        uint256 expectedValue = cm.getUsdValue(address(wethMock), amountDeposit);
        assertEq(totalCollateralValueInUsd, expectedValue);
    }
}
