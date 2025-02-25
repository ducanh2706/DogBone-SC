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

contract BridgeZapBeefy is DebridgeZapBase {
    address swapx_ichi_ws_sts_sts = 0x5555636503AE6EDE5d0109c5627b8f4B1250B096;
    address sts = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    address swapx_ichi_usdce_scusd = 0x11e9ba63182f152BB5385c0822fB84Cda92C125C;
    address usdce = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

    address vault;
    address token;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");
        vm.label(swapx_ichi_ws_sts_sts, "swapx_ichi_ws_sts_sts");
        vm.label(sts, "sts");
        vm.label(swapx_ichi_usdce_scusd, "swapx_ichi_usdce_scusd");
        vm.label(usdce, "usdce");
    }

    function test_depositSts() public {
        vault = swapx_ichi_ws_sts_sts;
        token = sts;
        externalCall = _prepareExternalCall();
        uint256 zapAmount = 1e22;
        _deposit(zapAmount);
    }

    function test_depositUsdce() public {
        vault = swapx_ichi_usdce_scusd;
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
            if (entries[i].topics[0] == keccak256("DepositBeefy(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(vault).balanceOf(alice);
        console.log("Expected stkToken Balance: ", expectedBalance);
        console.log("Current stkToken Balance: ", curBalance);

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
                        funcSelector: Zap.depositBeefy.selector,
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
