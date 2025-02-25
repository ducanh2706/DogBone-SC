// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DebridgeZapBase} from "./BridgeBase.t.sol";
import {DlnOrderLib} from "src/interfaces/debridge/DlnOrderLib.sol";
import {DlnExternalCallLib} from "src/interfaces/debridge/DLNExternalCallLib.sol";
import {BytesLib} from "src/interfaces/debridge/BytesLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Zap} from "src/strategies/Zap.sol";
import {Vm} from "forge-std/Vm.sol";

contract BridgeZapIChi is DebridgeZapBase {
    address ws_sts_sts_vault = 0xa68D5DbAe00960De66DdEaD4d53faea39f21983b;
    address sts = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    address scusd_usdce_usdce_vault = 0xF77CeeD15596BfC127D17bA45dEA9767BC349Be0;
    address usdce = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

    address vault;
    address token;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");
        vm.label(ws_sts_sts_vault, "ws_sts_sts_vault");
        vm.label(sts, "sts");
        vm.label(scusd_usdce_usdce_vault, "scusd_usdce_usdce_vault");
        vm.label(usdce, "usdce");
    }

    function test_depositWsStsSts() public {
        vault = ws_sts_sts_vault;
        token = sts;
        externalCall = _prepareExternalCall();
        uint256 zapAmount = 1e22;
        _deposit(zapAmount);
    }

    function test_depositScusdUsdceUsdce() public {
        vault = scusd_usdce_usdce_vault;
        token = usdce;
        externalCall = _prepareExternalCall();
        uint256 zapAmount = 1e10;
        _deposit(zapAmount);
    }

    function _deposit(uint256 zapAmount) internal {
        DlnOrderLib.Order memory order = DlnOrderLib.Order({
            makerOrderNonce: 1,
            makerSrc: abi.encodePacked(alice),
            giveChainId: 1,
            giveTokenAddress: abi.encodePacked(address(0x69)),
            giveAmount: 1e22,
            takeChainId: 100000014, // Sonic
            takeTokenAddress: abi.encodePacked(token),
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
        deal(token, taker, zapAmount);
        IERC20(token).approve(address(dlnDestination), zapAmount);
        vm.recordLogs();
        dlnDestination.fulfillOrder(order, zapAmount, orderId, "", taker, taker);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 expectedBalance;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DepositIchi(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(vault).balanceOf(alice);
        console.log("Expected Ichi LP Balance: ", expectedBalance);
        console.log("Current Ichi LP Balance: ", curBalance);

        assertEq(expectedBalance, curBalance);
    }

    function _prepareExternalCall() internal view override returns (bytes memory) {
        bytes memory payload = abi.encode(
            DlnExternalCallLib.ExternalCallPayload({
                to: address(zap),
                txGas: 0,
                callData: abi.encodeWithSelector(
                    Zap.doStrategy.selector,
                    Zap.Strategy({
                        vault: address(vault),
                        token: address(token),
                        receiver: alice,
                        amount: 0,
                        funcSelector: Zap.depositIchi.selector,
                        leverage: 0,
                        flashAmount: 0,
                        isProtected: false,
                        swapFlashloan: Zap.Swap({
                            fromToken: address(0),
                            fromAmount: 0,
                            router: address(0),
                            data: new bytes(0),
                            value: 0
                        })
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
}
