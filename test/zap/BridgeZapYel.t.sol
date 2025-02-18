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

contract BridgeZapYel is DebridgeZapBase {
    address public constant LSTS = 0x555733fBa1CA24ec45e7027E00C4B6c5065BaC96;
    address public constant STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    address public constant LSONIC = 0x7Ba0abb5f6bDCbf6409BB2803CdF801215424490;
    address public constant WS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;

    address public constant LSCUSD = 0x2C7A01DE0c419421EB590F9ECd98cBbca4B9eC2A;
    address public constant SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    address vault;
    address token;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");

        vm.label(LSTS, "LSTS");
        vm.label(STS, "STS");
        vm.label(LSONIC, "LSONIC");
        vm.label(WS, "WS");
        vm.label(LSCUSD, "LSCUSD");
        vm.label(SCUSD, "SCUSD");
    }

    function test_depositStS() public {
        vault = LSTS;
        token = STS;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e22;
        _deposit(zapAmount);
    }

    function test_depositWs() public {
        vault = LSONIC;
        token = WS;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e22;
        _deposit(zapAmount);
    }

    function test_depositScUsd() public {
        vault = LSCUSD;
        token = SCUSD;
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
            if (entries[i].topics[0] == keccak256("DepositYels(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(vault).balanceOf(alice);
        console.log("Expected stkToken Balance: ", expectedBalance);
        console.log("Current stkToken Balance: ", curBalance);
        assertEq(curBalance, expectedBalance);
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
                        funcSelector: Zap.depositYels.selector
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
