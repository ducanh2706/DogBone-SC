// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IWithdraw {
    struct AaveWithdrawData {
        address vault;
        address underlyingAsset;
        uint256 amount;
    }

    function withdrawAave(bytes memory withdrawAave) external returns (uint256 amountOut);
}
