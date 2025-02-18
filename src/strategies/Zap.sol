// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExternalCallExecutor} from "src/interfaces/debridge/IExternalCallExecutor.sol";
import {DlnExternalCallLib} from "src/interfaces/debridge/DLNExternalCallLib.sol";
import {ILST} from "src/interfaces/LST/ILST.sol";
import {IRings} from "src/interfaces/rings/IRings.sol";

contract Zap is IExternalCallExecutor {
    event DepositRings(address indexed vault, address indexed receiver, uint256 shares);
    event DepositLST(address indexed vault, address indexed receiver, uint256 shares);
    event DepositSilo(address indexed vault, address indexed receiver, uint256 shares);

    struct Strategy {
        address vault;
        address token;
        uint256 amount;
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

    /// Zap with tokens on the same chain. Swap first, then deposit
    /// @param swapData swap Data
    /// @param T strategy Data
    function zap(Swap memory swapData, Strategy memory T) external payable returns (bytes memory) {
        _swap(swapData);
        return doStrategy(T);
    }

    ////// DEBRIDGE FUNCTIONS //////
    function onEtherReceived(bytes32, address, bytes memory _payload)
        external
        payable
        returns (bool callSucceeded, bytes memory callResult)
    {
        DlnExternalCallLib.ExternalCallPayload memory payload =
            abi.decode(_payload, (DlnExternalCallLib.ExternalCallPayload));
        (callSucceeded, callResult) = address(payload.to).call(payload.callData);
    }

    function onERC20Received(
        bytes32,
        address _token,
        uint256 _transferredAmount,
        address _fallbackAddress,
        bytes memory _payload
    ) external returns (bool callSucceeded, bytes memory callResult) {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        assert(_transferredAmount <= tokenBal);
        DlnExternalCallLib.ExternalCallPayload memory payload =
            abi.decode(_payload, (DlnExternalCallLib.ExternalCallPayload));
        (callSucceeded, callResult) = address(payload.to).call(payload.callData);
        tokenBal = IERC20(_token).balanceOf(address(this));
        if (tokenBal > 0) IERC20(_token).transfer(_fallbackAddress, tokenBal);
    }

    /// API for all strategy zaps
    /// @param T strategy Data
    function doStrategy(Strategy memory T) public returns (bytes memory) {
        if (T.amount > 0) {
            IERC20(T.token).transferFrom(msg.sender, address(this), T.amount);
        }

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

    //// STRATEGY FUNCTIONS //////
    function depositSilo(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (amount > 0) IERC20(token).approve(vault, amount);
        shares = ISilo(vault).deposit(amount, receiver, ISilo.CollateralType.Collateral);
        emit DepositSilo(vault, receiver, shares);
        return shares;
    }

    function depositLST(address vault, address, address receiver, uint256 amount) public returns (uint256 shares) {
        ILST(vault).deposit{value: amount}();
        shares = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(receiver, IERC20(vault).balanceOf(address(this)));
        emit DepositLST(vault, receiver, shares);
        return shares;
    }

    function depositRings(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (amount > 0) IERC20(token).approve(vault, amount);
        shares = IRings(vault).deposit(token, amount, 0);
        address lpToken = IRings(vault).vault();
        IERC20(lpToken).transfer(receiver, IERC20(lpToken).balanceOf(address(this)));
        emit DepositRings(vault, receiver, shares);
        return shares;
    }

    function depositYels(address vault, address token, address receiver, uint256 amount) public {
        
    }

    function depositMachFi(address vault, address token, address receiver, uint256 amount) public {}

    function depositIchi(address vault, address token, address receiver, uint256 amount) public {}

    function depositBeefy(address vault, address token, address receiver, uint256 amount) public {}

    function depositEggs(address vault, address token, address receiver, uint256 amount) public {}

    function depositEggsLeverage(address vault, address token, address receiver, uint256 amount) public {}
}
