// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IDlnDestination} from "src/interfaces/debridge/IDLNDestination.sol";
import {DlnOrderLib} from "src/interfaces/debridge/DlnOrderLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DebridgeTaker is Test {
    error WrongChain();
    error MismatchedOrderId();

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 6914041;
    uint256 sonicFork;

    address alice = makeAddr("alice");
    address taker = makeAddr("taker");

    uint256 public constant MAX_ADDRESS_LENGTH = 255;
    IDlnDestination dlnDestination = IDlnDestination(0xE7351Fd770A37282b91D153Ee690B63579D6dd7f);

    // TOKEN ADDRESS
    address USDC = address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    address WS = address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    uint256 usdc_initial_amount = 1e10;
    uint256 ws_initial_amount = 1e22;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        deal(USDC, alice, 1e10);
        deal(WS, alice, 1e22);
        deal(USDC, taker, 1e10);
        deal(WS, taker, 1e22);
    }

    function test_fulfillOrder() public {
        uint256 takeAmount = 1e10;
        DlnOrderLib.Order memory order = DlnOrderLib.Order({
            makerOrderNonce: 1,
            makerSrc: abi.encodePacked(alice),
            giveChainId: 1,
            giveTokenAddress: abi.encodePacked(WS),
            giveAmount: 1e22,
            takeChainId: 100000014, // Sonic
            takeTokenAddress: abi.encodePacked(USDC),
            takeAmount: takeAmount,
            receiverDst: abi.encodePacked(alice),
            givePatchAuthoritySrc: abi.encodePacked(alice),
            orderAuthorityAddressDst: abi.encodePacked(alice),
            allowedTakerDst: "",
            allowedCancelBeneficiarySrc: "",
            externalCall: ""
        });

        bytes32 orderId = _getOrderId(order);

        vm.startPrank(taker);
        IERC20(USDC).approve(address(dlnDestination), takeAmount);
        dlnDestination.fulfillOrder(order, takeAmount, orderId, "", taker);
        vm.stopPrank();

        console.log("USDC balance of alice", IERC20(USDC).balanceOf(alice));
        console.log("USDC balance of taker", IERC20(USDC).balanceOf(taker));

        assertEq(IERC20(USDC).balanceOf(alice), usdc_initial_amount + takeAmount);
        assertEq(IERC20(USDC).balanceOf(taker), usdc_initial_amount - takeAmount);
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
}
