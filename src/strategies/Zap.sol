// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Zap {
    struct Strategy {
        address vault;
        address token;
        address receiver;
        bytes4 funcSelector;
    }

    struct Swap {
        address fromToken;
        uint256 fromAmount;
        address router;
        bytes data;
        uint256 value;
    }

    function zap(Swap memory swapData, Strategy memory T) external payable returns (bytes memory) {
        _swap(swapData);
        (bool success, bytes memory data) = address(this).call(
            abi.encodeWithSelector(
                T.funcSelector, T.vault, T.token, T.receiver, IERC20(T.token).balanceOf(address(this))
            )
        );
        require(success, "Strategy Zap Failed");
        return data;
    }

    function _swap(Swap memory swapData) internal {
        if (swapData.router == address(0)) {
            return;
        }

        if (swapData.fromToken != address(0)) {
            IERC20(swapData.fromToken).transferFrom(msg.sender, address(this), swapData.fromAmount);
            IERC20(swapData.fromToken).approve(swapData.router, swapData.fromAmount);
        }

        require(address(this).balance >= swapData.value, "Insufficient native balance");

        (bool success,) = swapData.router.call{value: swapData.value}(swapData.data);
        require(success, "Swap failed");
    }

    function depositSilo(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        IERC20(token).approve(vault, amount);
        return ISilo(vault).deposit(amount, receiver, ISilo.CollateralType.Collateral);
    }
}
