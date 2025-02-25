// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Zap} from "src/strategies/Zap.sol";
import {ISiloLens} from "src/interfaces/silo/ISiloLens.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

contract DepositDogBone is Test {
    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 8667498;
    uint256 sonicFork;

    address alice = makeAddr("alice");

    // SILO ADDRESS
    ISiloLens siloLens = ISiloLens(0xE05966aee69CeCD677a30f469812Ced650cE3b5E);
    ISiloConfig s_usdc_siloConfig = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2); // Market ID: 20
    ISilo wS_Vault; // 0.6859 price
    ISilo usdc_Vault;
    address usdc_e_shareDebtToken = address(0xbc4eF1B5453672a98073fbFF216966F5039ad256);

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

    function test_cc() public {
        console.logBytes4(Zap.depositDogBone.selector);
    }

    function test_depositDogBone() public {
        uint256 depositAmount = 1e20;
        uint256 flashAmount = 140e6;
        deal(WS, alice, depositAmount);

        vm.startPrank(alice);
        IERC20(WS).approve(address(zap), depositAmount);
        IERC20(usdc_e_shareDebtToken).approve(address(zap), flashAmount * 2);
        zap.doStrategy(
            Zap.Strategy({
                vault: address(wS_Vault),
                token: WS,
                amount: depositAmount,
                receiver: alice,
                funcSelector: Zap.depositDogBone.selector,
                leverage: 1,
                flashAmount: flashAmount,
                isProtected: false,
                swapFlashloan: Zap.Swap({
                    fromToken: USDC,
                    fromAmount: flashAmount,
                    router: address(this),
                    data: abi.encodeWithSelector(this.mockSwap.selector, USDC, WS, flashAmount),
                    value: 0
                })
            })
        );

        vm.stopPrank();

        uint256 shares = IERC20(address(wS_Vault)).balanceOf(alice);
        uint256 assets = wS_Vault.previewRedeem(shares, ISilo.CollateralType.Collateral);
        console.log("shares received: %d", shares);
        console.log("assets received: %d", assets);
    }

    function mockSwap(address fromToken, address toToken, uint256 amount) public {
        IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
        deal(toToken, address(this), 2e20);
        IERC20(toToken).transfer(msg.sender, 2e20);
    }
}
