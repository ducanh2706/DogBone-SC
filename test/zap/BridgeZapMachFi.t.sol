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

contract BridgeZapMachFi is DebridgeZapBase {
    address SONIC_VAULT = 0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6;
    address SONIC = 0x0000000000000000000000000000000000000000;

    address USDCE_VAULT = 0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445;
    address USDCE = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

    address WETH_VAULT = 0x15eF11b942Cc14e582797A61e95D47218808800D;
    address WETH = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;

    address SCUSD_VAULT = 0xe5A79Db6623BCA3C65337dd6695Ae6b1f53Bec45;
    address SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    address STS_VAULT = 0xbAA06b4D6f45ac93B6c53962Ea861e6e3052DC74;
    address STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    address vault;
    address token;

    function setUp() public override {
        super.setUp();

        vm.label(address(this), "TestContract");
        vm.label(address(zap), "ZapContract");
    }

    function test_depositSonic() public {
        vault = SONIC_VAULT;
        token = SONIC;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e22;
        _deposit(zapAmount);
    }

    function test_depositUsdce() public {
        vault = USDCE_VAULT;
        token = USDCE;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e10;
        _deposit(zapAmount);
    }

    function test_depositWeth() public {
        vault = WETH_VAULT;
        token = WETH;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e18;
        _deposit(zapAmount);
    }

    function test_depositScusd() public {
        vault = SCUSD_VAULT;
        token = SCUSD;
        externalCall = _prepareExternalCall();

        uint256 zapAmount = 1e10;
        _deposit(zapAmount);
    }

    function test_depositSts() public {
        vault = STS_VAULT;
        token = STS;
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
        if (token == address(0)) {
            deal(taker, zapAmount);
            vm.recordLogs();
            dlnDestination.fulfillOrder{value: zapAmount}(order, zapAmount, orderId, "", taker, taker);
            vm.stopPrank();
        } else {
            deal(token, taker, zapAmount);
            IERC20(token).approve(address(dlnDestination), zapAmount);
            vm.recordLogs();
            dlnDestination.fulfillOrder(order, zapAmount, orderId, "", taker, taker);
            vm.stopPrank();
        }

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 expectedBalance;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("DepositMachFi(address,address,uint256)")) {
                expectedBalance = abi.decode(entries[i].data, (uint256));
            }
        }

        uint256 curBalance = IERC20(vault).balanceOf(alice);
        console.log("Expected Share Balance: ", expectedBalance);
        console.log("Current Share Balance: ", curBalance);

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
                        funcSelector: Zap.depositMachFi.selector
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
