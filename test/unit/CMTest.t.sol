// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {DeployCollateralManager} from "../../script/DeployCM.s.sol";
import {CollateralManager} from "../../src/CollateralManager.sol";
import {SimpleStableCoin} from "../../src/SimpleStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract CMTest is Test {
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DeployCollateralManager deployer;

    CollateralManager public cm;
    SimpleStableCoin public ssc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public weth;
    uint256 public deployerKey;

    address public tokenAddresses;
    address public feedAddresses;

    ERC20Mock private wethMock;

    address public user = makeAddr("user");

    uint256 public constant STARTING_USER_BALANCE = 1000 ether;

    function setUp() public {
        deployer = new DeployCollateralManager();
        (ssc, cm, helperConfig) = deployer.run();
        (ethUsdPriceFeed, weth, deployerKey) = helperConfig.activeNetworkConfig();

        // Deploy Mock Tokens
        wethMock = ERC20Mock(weth);

        //The user mints some tokens
        wethMock.mint(user, STARTING_USER_BALANCE);
    }

    ///DepositCollateral
    function testDepositCollateralSuccess() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user);
        uint256 initialAmount = cm.getAccountCollateralValueETH(user, weth);

        wethMock.approve(address(cm), depositAmount);
        cm.depositCollateral(address(wethMock), depositAmount);

        uint256 depositedAmount = cm.getAccountCollateralValueETH(user, weth);
        vm.stopPrank();

        assertEq(depositedAmount, initialAmount + depositAmount);
    }

    function testDepositCollateralFailsZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(CollateralManager.CM__NeedsMoreThanZero.selector);
        cm.depositCollateral(address(wethMock), 0);
        vm.stopPrank();
    }

    function testDepositCollateralFailsUnallowedToken() public {
        address unallowedToken = address(new ERC20Mock());
        uint256 depositAmount = 100 ether;

        vm.startPrank(user);
        vm.expectRevert(CollateralManager.CM__NotAllowedToken.selector);
        cm.depositCollateral(unallowedToken, depositAmount);

        vm.stopPrank();
    }

    function testDepositCollateralUpdatesUserBalance() public {
        // Arrange
        vm.startPrank(user); // Start simulating actions for the user
        uint256 depositAmount = 100 ether;
        uint256 initialContractBalance = wethMock.balanceOf(address(cm));
        uint256 initialUserBalance = wethMock.balanceOf(user);

        // Act
        wethMock.approve(address(cm), depositAmount);
        cm.depositCollateral(address(wethMock), depositAmount);

        // Assert
        uint256 finalContractBalance = wethMock.balanceOf(address(cm));
        uint256 finalUserBalance = wethMock.balanceOf(user);

        assertEq(
            finalContractBalance, initialContractBalance + depositAmount, "Contract should have the deposited amount"
        );
        assertEq(
            finalUserBalance, initialUserBalance - depositAmount, "User balance should be reduced by the deposit amount"
        );

        vm.stopPrank();
    }

    //MintSSC
    function testMintSscSucceeds() public {
        uint256 COLLATERAL_AMOUNT = 500 ether;

        // Approve CollateralManager to spend user's WETH
        vm.startPrank(user);
        wethMock.approve(address(cm), COLLATERAL_AMOUNT);

        // Deposit collateral
        cm.depositCollateral(address(wethMock), COLLATERAL_AMOUNT);

        uint256 userInitialSscBalance = ssc.balanceOf(user);
        uint256 SSC_TO_MINT = 100 ether;

        // Mint SSC
        cm.mintSsc(SSC_TO_MINT);
        vm.stopPrank();

        // Check SSC balance of the user
        uint256 userFinalSscBalance = ssc.balanceOf(user);
        assertEq(userFinalSscBalance, userInitialSscBalance + SSC_TO_MINT);
    }

    function testMintSscFailsDueToLowCollateral() public {
        uint256 COLLATERAL_AMOUNT = 500 ether; //500 * 2000 = 10000,00

        // Approve CollateralManager to spend user's WETH
        vm.startPrank(user);
        wethMock.approve(address(cm), COLLATERAL_AMOUNT);

        // Deposit collateral
        cm.depositCollateral(address(wethMock), COLLATERAL_AMOUNT);

        uint256 insufficientSscAmount = 500001 ether; // Trying to mint more than allowed based on collateral
        //500000 fail; 500001 pass; means the calculation was correct
        // Expect the mint to revert due to breaking health factor
        vm.expectRevert();
        cm.mintSsc(insufficientSscAmount);
        vm.stopPrank();
    }

    //WithDrawCollateral
    function testWithdrawCollateralSuccess() public {
        uint256 INITIAL_COLLATERAL = 1000 ether;
        uint256 MINT_AMOUNT = 100 ether * 2000;
        uint256 WITHDRAW_AMOUNT = 800 ether;
        //uint256 WITHDRAW_TOO_MUCH = 1100 ether;

        // Deposit collateral
        vm.startPrank(user);
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        cm.depositCollateral(address(wethMock), INITIAL_COLLATERAL); //1000 * 2000 = 2000,000
        cm.mintSsc(MINT_AMOUNT); // 200,000 -> 400,000 needed

        // User withdraws collateral
        cm.withdrawCollateral(address(wethMock), WITHDRAW_AMOUNT); // 800 * 2000 = 1600,000

        // Check the remaining collateral for the user
        uint256 remainingCollateral = cm.getAccountCollateralValueETH(user, address(wethMock));
        vm.stopPrank();
        assertEq(remainingCollateral, INITIAL_COLLATERAL - WITHDRAW_AMOUNT);
    }

    function testWithdrawCollateralFailsBreakHealthFactor() public {
        uint256 INITIAL_COLLATERAL = 1000 ether;
        uint256 MINT_AMOUNT = 100 ether * 2000;
        uint256 WITHDRAW_AMOUNT = 800 ether;
        uint256 withdrawTooMuch = WITHDRAW_AMOUNT + 1;

        // Deposit collateral
        vm.startPrank(user);
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        cm.depositCollateral(address(wethMock), INITIAL_COLLATERAL); //1000 * 2000 = 2000,000
        cm.mintSsc(MINT_AMOUNT); // 200,000 -> 400,000 needed

        // User withdraws collateral
        vm.expectRevert(CollateralManager.CM__BreakHealthFactor.selector);
        cm.withdrawCollateral(address(wethMock), withdrawTooMuch); // 800 * 2000 = 1600,000
        vm.stopPrank();
    }

    function testWithdrawCollateralFailsTooMuch() public {
        uint256 INITIAL_COLLATERAL = 500 ether;
        uint256 MINT_AMOUNT = 100 ether * 2000;
        uint256 WITHDRAW_AMOUNT = 600 ether; //Over than initial collateral

        // Deposit collateral
        vm.startPrank(user);
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        cm.depositCollateral(address(wethMock), INITIAL_COLLATERAL);
        cm.mintSsc(MINT_AMOUNT);

        // User withdraws collateral
        vm.expectRevert(CollateralManager.CM__WithDrawTooMuchCollateral.selector);
        cm.withdrawCollateral(address(wethMock), WITHDRAW_AMOUNT);
        vm.stopPrank();
    }

    //Redeem
    function testRedeemCollateral() public {
        uint256 redeemAmount = 100 ether;
        uint256 sscToBurn = redeemAmount * 2000;

        vm.startPrank(user);
        // User deposits collateral
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        ssc.approve(address(cm), sscToBurn);
        cm.depositCollateral(weth, STARTING_USER_BALANCE);

        // User mints SSC
        cm.mintSsc(sscToBurn); // Mint 100 SSC * 2000

        // User redeems collateral
        uint256 collateralBalance = cm.getAccountCollateralValueETH(user, weth);
        cm.redeemCollateral(weth, redeemAmount, sscToBurn);

        // Verify the user's collateral balance after redeeming
        uint256 newCollateralBalance = cm.getAccountCollateralValueETH(user, weth);
        uint256 newMintedBalance = cm.getAccountMintedSSC(user);
        vm.stopPrank();
        assertEq(
            newCollateralBalance,
            collateralBalance - redeemAmount,
            "User's collateral balance should increase after redeeming"
        );

        //Verify the user's minted SSC amount is reduced
        assertEq(newMintedBalance, 0, "User's minted SSC amount should decrease after burning");
    }

    function testRedeemCollateralInsufficientCollateral() public {
        uint256 depositAmount = 500 ether;
        uint256 sscToBurn = depositAmount / 2 * 2000;
        // User2 tries to redeem more collateral than they have
        vm.startPrank(user);
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        ssc.approve(address(cm), sscToBurn);
        cm.depositCollateral(weth, depositAmount);
        cm.mintSsc(sscToBurn); // User2 mints 100 SSC

        // Try to redeem more collateral than available
        uint256 excessRedeemAmount = depositAmount + 1 ether;
        vm.expectRevert(CollateralManager.CM__WithDrawTooMuchCollateral.selector);
        cm.redeemCollateral(weth, excessRedeemAmount, sscToBurn);
        vm.stopPrank();
    }

    function testRedeemCollateralInsufficientSSC() public {
        uint256 depositAmount = 500 ether;
        uint256 sscToBurn = depositAmount / 3 * 2000;
        // User2 tries to redeem more collateral than they have
        vm.startPrank(user);
        wethMock.approve(address(cm), STARTING_USER_BALANCE);
        ssc.approve(address(cm), sscToBurn);
        cm.depositCollateral(weth, depositAmount);
        cm.mintSsc(sscToBurn);

        uint256 excessSscAmountToBurn = sscToBurn + 1; // More than the minted amount

        vm.expectRevert(CollateralManager.CM__NotEnoughSSCToBurn.selector);
        cm.redeemCollateral(weth, depositAmount, excessSscAmountToBurn);
        vm.stopPrank();
    }

    //Liquidate
    function testLiquidate() public {
        // set the initial status
        uint256 initialCollateralAmount = 100 ether;
        uint256 debtToCover = 50 ether * 2000;

        // 用户抵押资产
        vm.startPrank(user);
        wethMock.approve(address(cm), initialCollateralAmount);
        wethMock.mint(user, initialCollateralAmount);
        ssc.approve(address(cm), debtToCover + 1);
        cm.depositCollateral(address(wethMock), initialCollateralAmount);

        cm.mintSsc(debtToCover);

        //触发清算
        cm.reviseMintedSSCForTest(user);

        // 确保用户的健康因子已低于允许值，
        uint256 userHealthFactor = cm.calculateHealthFactor(user, weth);
        assert(userHealthFactor < MIN_HEALTH_FACTOR);

        // 确认清算前的状态
        uint256 initialCollateralBalance = cm.getAccountCollateralValueETH(user, weth);
        uint256 initialDebtBalance = cm.getAccountMintedSSC(user);

        // 执行清算
        cm.liquidate(address(wethMock), user, debtToCover);

        // 确认清算后的状态
        uint256 finalCollateralBalance = cm.getAccountCollateralValueETH(user, weth);
        uint256 finalDebtBalance = cm.getAccountMintedSSC(user);
        vm.stopPrank();

        console.log(initialCollateralBalance, finalCollateralBalance);
        console.log(initialDebtBalance, finalDebtBalance);
    }
}
