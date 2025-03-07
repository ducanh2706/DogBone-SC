// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILST {
    function deposit() external payable;
    function OS() external view returns (address);
    function ans() external view returns (address);
}
