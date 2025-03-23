// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IZapOut {
    struct ZapOutData {
        address receiver;
        bytes erc20Input;
        bytes withdrawData;
        bytes[] swapData;
        bytes zapOutValidation;
    }

    struct WithdrawData {
        address delegateTo;
        bytes4 funcSelector;
        bytes withdrawStrategyData;
    }

    struct ZapOutValidation {
        address token;
        uint256 minAmountOut;
    }

    struct ZapOutValidationData {
        uint256 beforeBalance;
    }

    struct ERC20Input {
        address[] tokenAddress;
        uint256[] tokenAmount;
    }

    struct SwapData {
        address router;
        address tokenIn;
        uint256 amountIn;
        uint8 scaleFlag;
        bytes data;
    }
}
