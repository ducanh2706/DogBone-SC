// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBeefy {
    function want() external view returns (address);
    function deposit(uint256 _amount) external;
}
