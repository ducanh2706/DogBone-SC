// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMachFiERC20 {
    function mintAsCollateral(uint256 mintAmount) external returns (uint256);
}
