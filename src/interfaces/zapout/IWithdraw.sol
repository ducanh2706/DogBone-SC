// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISilo} from "src/interfaces/silo/ISilo.sol";

interface IWithdraw {
    struct AaveWithdrawData {
        address vault;
        address underlyingAsset;
        uint256 amount;
    }

    struct LoopingData {
        bytes4 flashLoanSelector;
        bytes strategyLoopingData;
    }

    struct SiloLoopingWithdrawData {
        address vault;
        address underlyingAsset;
        uint256 amount;
        ISilo.CollateralType collateralType;
        address flashLoanWhere;
        uint256 flashAmount;
        SiloLoopingSwapData swap;
    }

    struct SiloLoopingSwapData {
        address router;
        bytes data;
    }

    function withdrawAave(bytes memory withdrawAave) external returns (uint256 amountOut);
    function withdrawVicuna(bytes memory withdrawVicuna) external returns (uint256 amountOut);
    function withdrawMachFi(bytes memory withdrawMachFi) external returns (uint256 amountOut);
    function withdrawSilo(bytes memory withdrawSilo) external returns (uint256 amountOut);
    function withdrawIchi(bytes memory _ichiWithdrawData) external returns (uint256[] memory amountsOut);
    function withdrawBeefyIchi(bytes memory _beefyIchiWithdrawData) external returns (uint256[] memory amountsOut);
    function withdrawYel(bytes memory _yelWithdrawData) external returns (uint256 amountOut);
    function withdrawSiloLooping(bytes memory _siloLoopingWithdrawData) external returns (uint256 amountOut);
}
