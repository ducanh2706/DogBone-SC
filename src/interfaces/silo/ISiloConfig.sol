// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ISiloConfig {
    /// @notice Retrieves the addresses of the two silos
    /// @return silo0 The address of the first silo
    /// @return silo1 The address of the second silo
    function getSilos() external view returns (address silo0, address silo1);
}
