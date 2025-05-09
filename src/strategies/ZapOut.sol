// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IInputScaleHelper} from "src/interfaces/IInputScaleHelper.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

contract ZapOut is IZapOut, Ownable, Pausable {
    address public constant NATIVE_TOKEN = address(0);
    address locked;
    address public inputScaleHelper;
    address public delegator;

    constructor(address _inputScaleHelper) Ownable(msg.sender) {
        inputScaleHelper = _inputScaleHelper;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function rescueFunds(address _token, uint256 _amount, address _receiver) external onlyOwner {
        if (_token == NATIVE_TOKEN) {
            (bool ok,) = _receiver.call{value: _amount}("");
            require(ok, "ZapOut: failed to rescue native token");
        } else {
            IERC20(_token).transfer(_receiver, _amount);
        }
    }

    function setDelegator(address _delegator) external onlyOwner {
        delegator = _delegator;
    }

    function setInputScaleHelper(address _inputScaleHelper) external onlyOwner {
        inputScaleHelper = _inputScaleHelper;
    }

    modifier lock() {
        require(locked == address(0), "ZapOut: reentrant call");
        locked = msg.sender;
        _;
        locked = address(0);
    }

    ////////////////////////////////// ZAP OUT /////////////////////////////////////
    function zapOut(bytes memory _zapOutData) external lock whenNotPaused returns (uint256 amountOut) {
        ZapOutData memory zapOutData = abi.decode(_zapOutData, (ZapOutData));
        zapOutData.receiver = locked;
        bytes memory extraData = _prepareValidationData(zapOutData.zapOutValidation);
        _receiveLP(zapOutData.erc20Input);
        _withdraw(zapOutData.withdrawData);
        _swap(zapOutData.swapData);
        amountOut = _validateAndTransfer(zapOutData.zapOutValidation, extraData, zapOutData.receiver);
        locked = address(0);
    }
    ////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////// HELPER FUNCTION ///////////////////////////////////////////////
    function _prepareValidationData(bytes memory _zapOutValidation) internal view returns (bytes memory extraData) {
        ZapOutValidation memory zapOutValidation = abi.decode(_zapOutValidation, (ZapOutValidation));
        ZapOutValidationData memory zapOutValidationData =
            ZapOutValidationData({beforeBalance: _balanceOf(zapOutValidation.token, address(this))});
        return abi.encode(zapOutValidationData);
    }

    function _receiveLP(bytes memory _erc20Input) internal {
        if (_erc20Input.length == 0) {
            return;
        }
        ERC20Input memory erc20Input = abi.decode(_erc20Input, (ERC20Input));
        for (uint256 i = 0; i < erc20Input.tokenAddress.length; i++) {
            IERC20(erc20Input.tokenAddress[i]).transferFrom(msg.sender, address(this), erc20Input.tokenAmount[i]);
        }
    }

    function _withdraw(bytes memory _withdrawData) internal returns (bytes memory) {
        if (_withdrawData.length == 0) {
            return "";
        }

        WithdrawData memory withdrawData = abi.decode(_withdrawData, (WithdrawData));

        (bool ok, bytes memory returnedWithdrawData) =
            delegator.delegatecall(abi.encodeWithSelector(withdrawData.funcSelector, withdrawData.withdrawStrategyData));

        if (!ok) {
            if (returnedWithdrawData.length > 0) {
                revert(string(abi.encodePacked("ZapOut: withdraw from strategy failed: ", returnedWithdrawData)));
            } else {
                revert("ZapOut: withdraw from strategy failed (unknown error)");
            }
        }

        return returnedWithdrawData;
    }

    function _swap(bytes[] memory _swapData) internal {
        for (uint256 _i = 0; _i < _swapData.length; _i++) {
            SwapData memory swapData = abi.decode(_swapData[_i], (SwapData));
            uint256 tokenInBalance = _balanceOf(swapData.tokenIn, address(this));

            if (tokenInBalance < swapData.amountIn && swapData.scaleFlag == 0) {
                revert("ZapOut: insufficient token in balance");
            }

            if (tokenInBalance != swapData.amountIn && swapData.scaleFlag != 0) {
                // scale swap data
                (bool ok, bytes memory newSwapData) =
                    IInputScaleHelper(inputScaleHelper).getScaledInputData(swapData.data, tokenInBalance);
                if (!ok) {
                    revert("ZapOut: failed to scale swap data");
                }
                swapData.data = newSwapData;
                swapData.amountIn = tokenInBalance;
            }

            bool swapSuccess;
            bytes memory swapReturnedData;
            if (swapData.tokenIn != NATIVE_TOKEN) {
                IERC20(swapData.tokenIn).approve(swapData.router, swapData.amountIn);
                (swapSuccess, swapReturnedData) = address(swapData.router).call(swapData.data);
                IERC20(swapData.tokenIn).approve(swapData.router, 0); // for safety
            } else {
                (swapSuccess, swapReturnedData) = address(swapData.router).call{value: swapData.amountIn}(swapData.data);
            }

            require(swapSuccess, string(abi.encodePacked("ZapOut: swap failed: ", swapReturnedData)));
        }
    }

    function _validateAndTransfer(bytes memory _zapOutValidation, bytes memory _extraData, address receiver)
        internal
        returns (uint256 amountOut)
    {
        ZapOutValidation memory zapOutValidation = abi.decode(_zapOutValidation, (ZapOutValidation));
        ZapOutValidationData memory zapOutValidationData = abi.decode(_extraData, (ZapOutValidationData));

        amountOut = _balanceOf(zapOutValidation.token, address(this)) - zapOutValidationData.beforeBalance;

        require(amountOut >= zapOutValidation.minAmountOut, "ZapOut: insufficient amount out");

        if (zapOutValidation.token == NATIVE_TOKEN) {
            (bool ok,) = receiver.call{value: amountOut}("");
            require(ok, "ZapOut: failed to transfer native token out to user");
        } else {
            IERC20(zapOutValidation.token).transfer(receiver, amountOut);
        }
    }

    function _balanceOf(address _token, address _user) internal view returns (uint256 balance) {
        if (_token == NATIVE_TOKEN) {
            return _user.balance;
        } else {
            return IERC20(_token).balanceOf(_user);
        }
    }

    receive() external payable whenNotPaused {}

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function onFlashLoan(address, address _token, uint256 _amount, uint256 _fee, bytes calldata _data)
        external
        whenNotPaused
        returns (bytes32)
    {
        if (locked == address(0)) {
            revert("Zap Out: Can't call onFlashLoan directly");
        }

        IWithdraw.LoopingData memory loopingData = abi.decode(_data, (IWithdraw.LoopingData));

        (bool ok, bytes memory returnedWithdrawData) = delegator.delegatecall(
            abi.encodeWithSelector(
                loopingData.flashLoanSelector, _token, _amount, _fee, locked, loopingData.strategyLoopingData
            )
        );

        if (!ok) {
            if (returnedWithdrawData.length > 0) {
                revert(string(abi.encodePacked("ZapOut: onFlashLoan failed: ", returnedWithdrawData)));
            } else {
                revert("ZapOut: onFlashLoan failed (unknown error)");
            }
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
