// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ISiloLens} from "src/interfaces/silo/ISiloLens.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositSilo is Test {
    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 6914041;
    uint256 sonicFork;

    address alice = makeAddr("alice");

    // SILO ADDRESS
    ISiloLens siloLens = ISiloLens(0xE05966aee69CeCD677a30f469812Ced650cE3b5E);
    ISiloConfig s_usdc_siloConfig = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2); // Market ID: 20
    ISilo wS_Vault;
    ISilo usdc_Vault;

    // TOKEN ADDRESS
    address USDC = address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    address WS = address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);

    uint256 usdc_initial_amount = 1e10;
    uint256 ws_initial_amount = 1e22;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        (address wS_Vault_Address, address usdc_Vault_Address) = s_usdc_siloConfig.getSilos();
        wS_Vault = ISilo(wS_Vault_Address);
        usdc_Vault = ISilo(usdc_Vault_Address);

        deal(USDC, alice, usdc_initial_amount);
        deal(WS, alice, ws_initial_amount);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(usdc_Vault), 1e10);
        IERC20(WS).approve(address(wS_Vault), 1e22);

        vm.stopPrank();
    }

    /// @notice Test depositing USDC into the silo
    function test_deposit() public {
        uint256 depositAmount = 1e8;
        uint256 shares = _deposit(depositAmount);

        assertEq(shares, IERC20(address(usdc_Vault)).balanceOf(alice));
        assertEq(IERC20(USDC).balanceOf(alice), usdc_initial_amount - depositAmount);
    }

    /// @notice Test withdrawing USDC from the silo
    function test_withdraw() public {
        uint256 depositAmount = 1e10;
        uint256 shares = _deposit(depositAmount);
        uint256 redeemedAmount = _redeem(shares);

        console.log("Deposit amount %s", depositAmount);
        console.log("Redeemed amount %s", redeemedAmount);

        assertApproxEqAbs(redeemedAmount, depositAmount, 1e3);
        assertEq(IERC20(USDC).balanceOf(alice), usdc_initial_amount - depositAmount + redeemedAmount);
    }

    /// @notice Test borrowing S from the silo
    function test_borrow() public {
        uint256 depositAmount = 1e10;
        // deposit USDC as collateral into Silo
        _deposit(depositAmount);

        // borrow WS from Silo
        uint256 maxBorrow = wS_Vault.maxBorrow(alice);
        uint256 previewBorrow = wS_Vault.previewBorrow(maxBorrow);
        vm.startPrank(alice);
        IERC20(WS).approve(address(wS_Vault), maxBorrow);
        uint256 shares = wS_Vault.borrow(maxBorrow, alice, alice);
        vm.stopPrank();

        assertEq(previewBorrow, shares);
        assertEq(IERC20(WS).balanceOf(alice), ws_initial_amount + maxBorrow);
    }

    function test_getDepositAPR() public view {
        console.log("USDC Deposit APR: %s", siloLens.getDepositAPR(usdc_Vault));
        console.log("WS Deposit APR: %s", siloLens.getDepositAPR(wS_Vault));
    }

    function _deposit(uint256 depositAmount) internal returns (uint256 shares) {
        vm.startPrank(alice);
        shares = usdc_Vault.deposit(depositAmount, alice, ISilo.CollateralType.Collateral);
        vm.stopPrank();
    }

    function _redeem(uint256 shares) internal returns (uint256 depositAssets) {
        vm.startPrank(alice);
        IERC20(address(usdc_Vault)).approve(address(usdc_Vault), shares);
        depositAssets = usdc_Vault.redeem(shares, alice, alice);
        vm.stopPrank();
    }
}
