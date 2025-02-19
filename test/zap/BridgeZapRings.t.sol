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

contract BridgeZapRings is DebridgeZapBase {
    address stkscUSDTeller = 0x5e39021Ae7D3f6267dc7995BB5Dd15669060DAe0;
    address stkscETHTeller = 0x49AcEbF8f0f79e1Ecb0fd47D684DAdec81cc6562;

    address scUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address scETH = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;

    address stkscUSD = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    address stkscETH = 0x455d5f11Fea33A8fa9D3e285930b478B6bF85265;

    address vault;
    address token;
    address stkToken;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");
        vm.label(stkscUSDTeller, "stkscUSDTeller");
        vm.label(stkscETHTeller, "stkscETHTeller");
        vm.label(scUSD, "scUSD");
        vm.label(scETH, "scETH");
        vm.label(stkscUSD, "stkscUSD");
        vm.label(stkscETH, "stkscETH");
    }

    function test_depositStkscUSD() public {
        vault = stkscUSDTeller;
        token = scUSD;
        stkToken = stkscUSD;
        externalCall = _prepareExternalCall();
        uint256 zapAmount = 1e10;
        _deposit(zapAmount);
    }

    function test_depositStkscETH() public {
        vault = stkscETHTeller;
        token = scETH;
        stkToken = stkscETH;
        externalCall = _prepareExternalCall();
        uint256 zapAmount = 1e22;
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
            if (entries[i].topics[0] == keccak256("DepositRings(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(stkToken).balanceOf(alice);
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
                        funcSelector: Zap.depositRings.selector,
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
