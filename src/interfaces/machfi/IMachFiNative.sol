// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMachFiNative {
    function mintAsCollateral() external payable returns (uint256);
}
