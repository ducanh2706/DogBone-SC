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

contract BridgeZapLST is DebridgeZapBase {
    address stSVault = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address osVault = 0xe25A2B256ffb3AD73678d5e80DE8d2F6022fAb21;
    address OS = 0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794;
    address STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    address vault;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");
        vm.label(stSVault, "stSVault");
        vm.label(osVault, "osVault");
        vm.label(OS, "OS");
    }

    function test_zapIntoSTS() public {
        _setUpVault(stSVault);

        uint256 zapAmount = 1e21;

        DlnOrderLib.Order memory order = DlnOrderLib.Order({
            makerOrderNonce: 1,
            makerSrc: abi.encodePacked(alice),
            giveChainId: 1,
            giveTokenAddress: abi.encodePacked(OS),
            giveAmount: 1e22,
            takeChainId: 100000014, // Sonic
            takeTokenAddress: abi.encodePacked(address(0)),
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
        deal(taker, zapAmount);
        vm.recordLogs();
        dlnDestination.fulfillOrder{value: zapAmount}(order, zapAmount, orderId, "", taker, taker);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 expectedBalance;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DepositLST(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(stSVault).balanceOf(alice);
        console.log("Expected ST-S balance: ", expectedBalance);
        console.log("Current ST-S balance: ", curBalance);

        assertEq(curBalance, expectedBalance);
    }

    function test_zapIntoOS() public {
        _setUpVault(osVault);

        uint256 zapAmount = 1e21;

        DlnOrderLib.Order memory order = DlnOrderLib.Order({
            makerOrderNonce: 1,
            makerSrc: abi.encodePacked(alice),
            giveChainId: 1,
            giveTokenAddress: abi.encodePacked(OS),
            giveAmount: 1e22,
            takeChainId: 100000014, // Sonic
            takeTokenAddress: abi.encodePacked(address(0)),
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
        deal(taker, zapAmount);
        vm.recordLogs();
        dlnDestination.fulfillOrder{value: zapAmount}(order, zapAmount, orderId, "", taker, taker);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 expectedBalance;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DepositLST(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(OS).balanceOf(alice);
        console.log("Expected OS balance: ", expectedBalance);
        console.log("Current OS balance: ", curBalance);

        assertEq(curBalance, expectedBalance);
    }

    function test_swapAndZapStS() public {
        vm.startPrank(alice);
        uint256 inAmount = 1e20;
        deal(STS, alice, inAmount);
        IERC20(STS).approve(address(zap), inAmount);
        zap.zap(
            Zap.Swap({
                fromToken: STS,
                fromAmount: inAmount,
                router: address(this),
                data: abi.encodeWithSelector(this.mockSwap.selector, STS, address(0), inAmount),
                value: 0
            }),
            Zap.Strategy({
                vault: osVault,
                token: address(0),
                receiver: alice,
                amount: 0,
                funcSelector: Zap.depositOS.selector,
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
        );
        vm.stopPrank();

        console.log("OS alice balance: %d", IERC20(OS).balanceOf(alice));
    }

    function _setUpVault(address vaultAddress) internal {
        vault = vaultAddress;
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
                        vault: address(vault),
                        token: address(0),
                        receiver: alice,
                        amount: 0,
                        funcSelector: vault == stSVault ? Zap.depositStS.selector : Zap.depositOS.selector,
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
