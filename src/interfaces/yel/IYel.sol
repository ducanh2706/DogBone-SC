// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IYel {
    function bond(address _token, uint256 _amount, uint256 _amountMintMin) external;
    function debond(uint256 _amount, address[] memory, uint8[] memory) external;
}
