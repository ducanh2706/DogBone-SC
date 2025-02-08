// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISilo} from "./ISilo.sol";

interface ISiloLens {
    /// @notice Calculates current borrow interest rate
    /// @param _silo Address of the silo
    /// @return borrowAPR The interest rate value in 18 decimals points. 10**18 is equal to 100% per year
    function getBorrowAPR(ISilo _silo) external view returns (uint256 borrowAPR);

    /// @notice Calculates current deposit interest rate.
    /// @param _silo Address of the silo
    /// @return depositAPR The interest rate value in 18 decimals points. 10**18 is equal to 100% per year.
    function getDepositAPR(ISilo _silo) external view returns (uint256 depositAPR);
}
