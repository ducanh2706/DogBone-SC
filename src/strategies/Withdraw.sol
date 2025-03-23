// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {IAave} from "src/interfaces/aave/IAave.sol";

contract Withdraw is IWithdraw {
    function withdrawAave(bytes memory _aaveWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_aaveWithdrawData, (AaveWithdrawData));
        amountOut = IAave(withdrawData.vault).withdraw(withdrawData.underlyingAsset, withdrawData.amount, address(this));
    }
}
