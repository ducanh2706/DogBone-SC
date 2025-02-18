// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IDlnDestination} from "src/interfaces/debridge/IDLNDestination.sol";
import {DlnOrderLib} from "src/interfaces/debridge/DlnOrderLib.sol";
import {DlnExternalCallLib} from "src/interfaces/debridge/DLNExternalCallLib.sol";
import {BytesLib} from "src/interfaces/debridge/BytesLib.sol";
import {ISiloLens} from "src/interfaces/silo/ISiloLens.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Zap} from "src/strategies/Zap.sol";
import {DebridgeZapBase} from "test/zap/BridgeBase.t.sol";

contract DebridgeZapSilo is DebridgeZapBase {
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

    uint256 zapAmount = 1e10;

    function setUp() public override {
        super.setUp();
        (address wS_Vault_Address, address usdc_Vault_Address) = s_usdc_siloConfig.getSilos();
        wS_Vault = ISilo(wS_Vault_Address);
        usdc_Vault = ISilo(usdc_Vault_Address);

        deal(USDC, alice, 1e10);
        deal(WS, alice, 1e22);
        deal(USDC, taker, 1e10);
        deal(WS, taker, 1e22);

        externalCall = _prepareExternalCall();
    }

    function _prepareExternalCall() internal view override returns (bytes memory) {
        bytes memory payload = abi.encode(
            DlnExternalCallLib.ExternalCallPayload({
                to: address(zap),
                txGas: 0,
                callData: abi.encodeWithSelector(
                    Zap.doStrategy.selector,
                    Zap.Strategy({
                        vault: address(usdc_Vault),
                        token: USDC,
                        receiver: alice,
                        amount: 0,
                        funcSelector: Zap.depositSilo.selector
                    })
                )
            })
        );

        DlnExternalCallLib.ExternalCallEnvelopV1 memory externalCallEnvelope = DlnExternalCallLib.ExternalCallEnvelopV1({
            fallbackAddress: address(0),
            executorAddress: address(zap),
            executionFee: 0,
            allowDelayedExecution: false,
            requireSuccessfullExecution: true,
            payload: payload
        });

        return BytesLib.concat(abi.encodePacked(uint8(1)), abi.encode(externalCallEnvelope));
    }

    function test_bridgeIntoSilo() public {
        DlnOrderLib.Order memory order = DlnOrderLib.Order({
            makerOrderNonce: 1,
            makerSrc: abi.encodePacked(alice),
            giveChainId: 1,
            giveTokenAddress: abi.encodePacked(WS),
            giveAmount: 1e22,
            takeChainId: 100000014, // Sonic
            takeTokenAddress: abi.encodePacked(USDC),
            takeAmount: zapAmount,
            receiverDst: abi.encodePacked(alice),
            givePatchAuthoritySrc: abi.encodePacked(alice),
            orderAuthorityAddressDst: abi.encodePacked(alice),
            allowedTakerDst: "",
            allowedCancelBeneficiarySrc: "",
            externalCall: externalCall
        });

        bytes32 orderId = _getOrderId(order);

        vm.startPrank(taker);
        IERC20(USDC).approve(address(dlnDestination), zapAmount);
        dlnDestination.fulfillOrder(order, zapAmount, orderId, "", taker, taker);
        vm.stopPrank();

        console.log("USDC balance of taker", IERC20(USDC).balanceOf(taker));
        assertEq(IERC20(USDC).balanceOf(taker), usdc_initial_amount - zapAmount);

        (, address collateralSharesToken,) = s_usdc_siloConfig.getShareTokens(address(usdc_Vault));
        uint256 userCollateralShares = IERC20(collateralSharesToken).balanceOf(alice);
        uint256 userCollateralAssets = usdc_Vault.previewRedeem(userCollateralShares, ISilo.CollateralType.Collateral);
        console.log("alice collateral shares", userCollateralShares);

        assertApproxEqAbs(userCollateralAssets, zapAmount, 1e2);

        _redeem(userCollateralShares);
        console.log("alice USDC balance", IERC20(USDC).balanceOf(alice));
        assertApproxEqAbs(IERC20(USDC).balanceOf(alice), usdc_initial_amount + zapAmount, 1e2);
    }

    function _redeem(uint256 shares) internal returns (uint256 depositAssets) {
        vm.startPrank(alice);
        IERC20(address(usdc_Vault)).approve(address(usdc_Vault), shares);
        depositAssets = usdc_Vault.redeem(shares, alice, alice, ISilo.CollateralType.Collateral);
        vm.stopPrank();
    }
}
