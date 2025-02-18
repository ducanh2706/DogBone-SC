// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IRings {
    function deposit(address depositAsset, uint256 depositAmount, uint256 minimuzmMint)
        external
        payable
        returns (uint256 shares);
    function vault() external returns (address);
}
