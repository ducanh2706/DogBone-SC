// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IIChi {
    function deposit(uint256 amount0, uint256 amount1, address to) external returns (uint256 shares);
    function token0() external view returns (address);
    function allowToken0() external view returns (bool);
}
