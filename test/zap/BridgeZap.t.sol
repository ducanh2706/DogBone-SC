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

contract DebridgeZapSilo is Test {
    error WrongChain();
    error MismatchedOrderId();
    error InvalideState();
    error FailedExecuteExternalCall();

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 6914041;
    uint256 sonicFork;

    // SILO ADDRESS
    ISiloLens siloLens = ISiloLens(0xE05966aee69CeCD677a30f469812Ced650cE3b5E);
    ISiloConfig s_usdc_siloConfig = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2); // Market ID: 20
    ISilo wS_Vault;
    ISilo usdc_Vault;

    address alice = makeAddr("alice");
    address taker = makeAddr("taker");

    uint256 public constant MAX_ADDRESS_LENGTH = 255;
    IDlnDestination dlnDestination = IDlnDestination(0xE7351Fd770A37282b91D153Ee690B63579D6dd7f);
    address dlnExternalCallAdapter;

    // TOKEN ADDRESS
    address USDC = address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    address WS = address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    uint256 usdc_initial_amount = 1e10;
    uint256 ws_initial_amount = 1e22;

    uint256 zapAmount = 1e10;
    bytes externalCall;

    Zap zap;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        zap = new Zap();

        (address wS_Vault_Address, address usdc_Vault_Address) = s_usdc_siloConfig.getSilos();
        wS_Vault = ISilo(wS_Vault_Address);
        usdc_Vault = ISilo(usdc_Vault_Address);

        deal(USDC, alice, 1e10);
        deal(WS, alice, 1e22);
        deal(USDC, taker, 1e10);
        deal(WS, taker, 1e22);

        externalCall = _prepareExternalCall();
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

        (,address collateralSharesToken,) = s_usdc_siloConfig.getShareTokens(address(usdc_Vault));
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

    // Deposit into Silo
    function _prepareExternalCall() internal view returns (bytes memory) {
        bytes memory payload = abi.encode(
            DlnExternalCallLib.ExternalCallPayload({
                to: address(zap),
                txGas: 0,
                callData: abi.encodeWithSelector(Zap.doStrategy.selector, Zap.Strategy({
                    vault: address(usdc_Vault),
                    token: USDC,
                    receiver: alice,
                    amount: 0,
                    funcSelector: Zap.depositSilo.selector
                }))
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

    function _encodeOrder(DlnOrderLib.Order memory _order) internal pure returns (bytes memory encoded) {
        {
            if (
                _order.makerSrc.length > MAX_ADDRESS_LENGTH || _order.giveTokenAddress.length > MAX_ADDRESS_LENGTH
                    || _order.takeTokenAddress.length > MAX_ADDRESS_LENGTH || _order.receiverDst.length > MAX_ADDRESS_LENGTH
                    || _order.givePatchAuthoritySrc.length > MAX_ADDRESS_LENGTH
                    || _order.allowedTakerDst.length > MAX_ADDRESS_LENGTH
                    || _order.allowedCancelBeneficiarySrc.length > MAX_ADDRESS_LENGTH
            ) revert("Address length is too long");
        }
        // | Bytes | Bits | Field                                                |
        // | ----- | ---- | ---------------------------------------------------- |
        // | 8     | 64   | Nonce
        // | 1     | 8    | Maker Src Address Size (!=0)                         |
        // | N     | 8*N  | Maker Src Address                                              |
        // | 32    | 256  | Give Chain Id                                        |
        // | 1     | 8    | Give Token Address Size (!=0)                        |
        // | N     | 8*N  | Give Token Address                                   |
        // | 32    | 256  | Give Amount                                          |
        // | 32    | 256  | Take Chain Id                                        |
        // | 1     | 8    | Take Token Address Size (!=0)                        |
        // | N     | 8*N  | Take Token Address                                   |
        // | 32    | 256  | Take Amount                                          |                         |
        // | 1     | 8    | Receiver Dst Address Size (!=0)                      |
        // | N     | 8*N  | Receiver Dst Address                                 |
        // | 1     | 8    | Give Patch Authority Address Size (!=0)              |
        // | N     | 8*N  | Give Patch Authority Address                         |
        // | 1     | 8    | Order Authority Address Dst Size (!=0)               |
        // | N     | 8*N  | Order Authority Address Dst                     |
        // | 1     | 8    | Allowed Taker Dst Address Size                       |
        // | N     | 8*N  | * Allowed Taker Address Dst                          |
        // | 1     | 8    | Allowed Cancel Beneficiary Src Address Size          |
        // | N     | 8*N  | * Allowed Cancel Beneficiary Address Src             |
        // | 1     | 8    | Is External Call Presented 0x0 - Not, != 0x0 - Yes   |
        // | 32    | 256  | * External Call Envelope Hash

        encoded = abi.encodePacked(_order.makerOrderNonce, (uint8)(_order.makerSrc.length), _order.makerSrc);
        {
            encoded = abi.encodePacked(
                encoded,
                _order.giveChainId,
                (uint8)(_order.giveTokenAddress.length),
                _order.giveTokenAddress,
                _order.giveAmount,
                _order.takeChainId
            );
        }
        //Avoid stack to deep
        {
            encoded = abi.encodePacked(
                encoded,
                (uint8)(_order.takeTokenAddress.length),
                _order.takeTokenAddress,
                _order.takeAmount,
                (uint8)(_order.receiverDst.length),
                _order.receiverDst
            );
        }
        {
            encoded = abi.encodePacked(
                encoded,
                (uint8)(_order.givePatchAuthoritySrc.length),
                _order.givePatchAuthoritySrc,
                (uint8)(_order.orderAuthorityAddressDst.length),
                _order.orderAuthorityAddressDst
            );
        }
        {
            encoded = abi.encodePacked(
                encoded,
                (uint8)(_order.allowedTakerDst.length),
                _order.allowedTakerDst,
                (uint8)(_order.allowedCancelBeneficiarySrc.length),
                _order.allowedCancelBeneficiarySrc,
                _order.externalCall.length > 0
            );
        }
        if (_order.externalCall.length > 0) {
            encoded = abi.encodePacked(encoded, keccak256(_order.externalCall));
        }
        return encoded;
    }

    // ============ VIEWS ============

    function _getOrderId(DlnOrderLib.Order memory _order) internal pure returns (bytes32) {
        return keccak256(_encodeOrder(_order));
    }

    function _getEnvelopeData(bytes memory _externalCall)
        internal
        pure
        returns (uint8 envelopeVersion, bytes memory envelopData)
    {
        envelopeVersion = BytesLib.toUint8(_externalCall, 0);
        // Remove first byte from data
        envelopData = BytesLib.slice(_externalCall, 1, _externalCall.length - 1);
    }
}
