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

abstract contract DebridgeZapBase is Test {
    error WrongChain();
    error MismatchedOrderId();
    error InvalideState();
    error FailedExecuteExternalCall();

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 6914041;
    uint256 sonicFork;

    address alice = makeAddr("alice");
    address taker = makeAddr("taker");

    uint256 public constant MAX_ADDRESS_LENGTH = 255;
    IDlnDestination dlnDestination = IDlnDestination(0xE7351Fd770A37282b91D153Ee690B63579D6dd7f);
    address dlnExternalCallAdapter;

    bytes externalCall;

    Zap zap;

    function setUp() public virtual {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        zap = new Zap();
    }

    // Deposit into Silo
    function _prepareExternalCall() internal view virtual returns (bytes memory);

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

    function mockSwap(address fromToken, address toToken, uint256 fromAmount) external payable {
        if (fromToken == address(0)) {
            require(msg.value >= fromAmount, "Insufficient  balance");
        } else {
            IERC20(fromToken).transferFrom(msg.sender, address(this), fromAmount);
        }

        if (toToken == address(0)) {
            deal(address(this), fromAmount * 2);
            payable(msg.sender).transfer(fromAmount * 2);
        } else {
            deal(toToken, address(this), fromAmount * 2);
            IERC20(toToken).transfer(msg.sender, fromAmount * 2);
        }
    }
}
