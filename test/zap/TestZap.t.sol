// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Zap} from "src/strategies/Zap.sol";
import {ISiloLens} from "src/interfaces/silo/ISiloLens.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

contract ZapTest is Test {
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

    Zap zap;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        (address wS_Vault_Address, address usdc_Vault_Address) = s_usdc_siloConfig.getSilos();
        wS_Vault = ISilo(wS_Vault_Address);
        usdc_Vault = ISilo(usdc_Vault_Address);

        zap = new Zap();
    }

    function test_depositSilo_noSwapData() public {
        uint256 depositAmount = 1e20;
        deal(WS, alice, depositAmount);
        vm.startPrank(alice);
        IERC20(WS).approve(address(zap), depositAmount);
        bytes memory result = zap.zap(
            Zap.Swap({fromToken: address(0), fromAmount: 0, router: address(0), data: "", value: 0}),
            Zap.Strategy({
                vault: address(wS_Vault),
                token: WS,
                amount: depositAmount,
                receiver: alice,
                funcSelector: Zap.depositSilo.selector,
                leverage: 0,
                flashAmount: 0,
                swapFlashloan: Zap.Swap({
                    fromToken: address(0),
                    fromAmount: 0,
                    router: address(0),
                    data: new bytes(0),
                    value: 0
                })
            })
        );
        vm.stopPrank();

        uint256 expectedShares = abi.decode(result, (uint256));
        uint256 shares = IERC20(address(wS_Vault)).balanceOf(alice);

        console.log("expected shares: %d", expectedShares);
        console.log("shares received: %d", shares);
        assertEq(shares, expectedShares);
    }

    function test_depositSilo_swapMock() public {
        uint256 depositAmount = 1e10;
        deal(USDC, alice, depositAmount);

        vm.startPrank(alice);
        IERC20(USDC).approve(address(zap), depositAmount);
        bytes memory result = zap.zap(
            Zap.Swap({
                fromToken: USDC,
                fromAmount: depositAmount,
                router: address(this),
                data: abi.encodeWithSelector(this.mockSwap.selector, USDC, WS, depositAmount),
                value: 0
            }),
            Zap.Strategy({
                vault: address(wS_Vault),
                token: WS,
                receiver: alice,
                amount: 0,
                funcSelector: Zap.depositSilo.selector,
                leverage: 0,
                flashAmount: 0,
                swapFlashloan: Zap.Swap({
                    fromToken: address(0),
                    fromAmount: 0,
                    router: address(0),
                    data: new bytes(0),
                    value: 0
                })
            })
        );
        vm.stopPrank();

        uint256 expectedShares = abi.decode(result, (uint256));
        uint256 shares = IERC20(address(wS_Vault)).balanceOf(alice);

        console.log("expected shares: %d", expectedShares);
        console.log("shares received: %d", shares);

        assertEq(shares, expectedShares);
    }

    function mockSwap(address fromToken, address toToken, uint256 fromAmount) external payable {
        if (fromToken == address(0)) {
            require(msg.value >= fromAmount, "Insufficient  balance");
        } else {
            IERC20(fromToken).transferFrom(msg.sender, address(this), fromAmount);
        }

        if (toToken == address(0)) {
            deal(address(this), fromAmount * 2);
            payable(msg.sender).transfer(fromAmount * 2);
        } else {
            IERC20(toToken).transfer(msg.sender, fromAmount * 2);
        }
    }
}
