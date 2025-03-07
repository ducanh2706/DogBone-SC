// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExternalCallExecutor} from "src/interfaces/debridge/IExternalCallExecutor.sol";
import {DlnExternalCallLib} from "src/interfaces/debridge/DLNExternalCallLib.sol";
import {ILST} from "src/interfaces/LST/ILST.sol";
import {IRings} from "src/interfaces/rings/IRings.sol";
import {IYel} from "src/interfaces/yel/IYel.sol";
import {IMachFiERC20} from "src/interfaces/machfi/IMachFiERC20.sol";
import {IMachFiNative} from "src/interfaces/machfi/IMachFiNative.sol";
import {IIChi} from "src/interfaces/ichi/IIChi.sol";
import {IBeefy} from "src/interfaces/beefy/IBeefy.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {IERC3156FlashBorrower} from "src/interfaces/flashloan/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/flashloan/IERC3156FlashLender.sol";
import {IAave} from "src/interfaces/aave/IAave.sol";

contract Zap is IExternalCallExecutor, IERC3156FlashBorrower {
    event DepositRings(address indexed vault, address indexed receiver, uint256 shares);
    event DepositLST(address indexed vault, address indexed receiver, uint256 shares);
    event DepositSilo(address indexed vault, address indexed receiver, uint256 shares);
    event DepositYels(address indexed vault, address indexed receiver, uint256 shares);
    event DepositMachFi(address indexed vault, address indexed receiver, uint256 shares);
    event DepositIchi(address indexed vault, address indexed receiver, uint256 shares);
    event DepositBeefy(address indexed vault, address indexed receiver, uint256 shares);
    event DepositDogBone(address indexed vault, uint256 indexed leverage, address indexed receiver, uint256 shares);

    struct Strategy {
        address vault;
        address token;
        uint256 amount;
        address receiver;
        bytes4 funcSelector;
        uint256 leverage;
        uint256 flashAmount;
        bool isProtected;
        Swap swapFlashloan;
    }

    struct Swap {
        address fromToken;
        uint256 fromAmount;
        address router;
        bytes data;
        uint256 value;
    }

    address public constant AAVE = 0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    address public constant VICUNA = 0xaa1C02a83362BcE106dFf6eB65282fE8B97A1665;
    address public constant NATIVE_TOKEN = address(0);

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
        if (tokenBal > 0 && _fallbackAddress != address(0)) IERC20(_token).transfer(_fallbackAddress, tokenBal);
    }

    /// API for all strategy zaps
    /// @param T strategy Data
    function doStrategy(Strategy memory T) public payable returns (bytes memory) {
        if (T.amount > 0) {
            if (NATIVE_TOKEN == T.token) {
                require(msg.value >= T.amount, "Incorrect native amount");
            } else {
                IERC20(T.token).transferFrom(msg.sender, address(this), T.amount);
            }
        }

        uint256 tokenBal = T.token == NATIVE_TOKEN ? address(this).balance : IERC20(T.token).balanceOf(address(this));
        bool success;
        bytes memory data;

        if (T.leverage == 0) {
            (success, data) =
                address(this).call(abi.encodeWithSelector(T.funcSelector, T.vault, T.token, T.receiver, tokenBal));
        } else {
            (success, data) = address(this).call(abi.encodeWithSelector(T.funcSelector, T));
        }
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

    function depositPendle(address, address, address, uint256) public {

    }

    function depositAave(address, address token, address receiver, uint256 amount) public {
        if (amount > 0) IERC20(token).approve(AAVE, amount);
        IAave(AAVE).supply(token, amount, receiver, 0);
    }

    function depositVicuna(address, address token, address receiver, uint256 amount) public {
        if (amount > 0) IERC20(token).approve(VICUNA, amount);
        IAave(VICUNA).supply(token, amount, receiver, 0);
    }

    function depositSilo(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (amount > 0) IERC20(token).approve(vault, amount);
        shares = ISilo(vault).deposit(amount, receiver, ISilo.CollateralType.Collateral);
        emit DepositSilo(vault, receiver, shares);
        return shares;
    }

    function depositStS(address vault, address, address receiver, uint256 amount) public returns (uint256 shares) {
        ILST(vault).deposit{value: amount}();
        shares = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(receiver, shares);
        emit DepositLST(vault, receiver, shares);
        return shares;
    }

    function depositOS(address vault, address, address receiver, uint256 amount) public returns (uint256 shares) {
        ILST(vault).deposit{value: amount}();
        shares = IERC20(ILST(vault).OS()).balanceOf(address(this));
        IERC20(ILST(vault).OS()).transfer(receiver, shares);
        emit DepositLST(vault, receiver, shares);
        return shares;
    }

    function depositANS(address vault, address, address receiver, uint256 amount) public returns (uint256 shares) {
        ILST(vault).deposit{value: amount}();
        shares = IERC20(ILST(vault).ans()).balanceOf(address(this));
        IERC20(ILST(vault).ans()).transfer(receiver, shares);
        emit DepositLST(vault, receiver, shares);
        return shares;
    }

    function depositRings(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        address lpToken = IRings(vault).vault();
        if (amount > 0) IERC20(token).approve(lpToken, amount);
        shares = IRings(vault).deposit(token, amount, 0);
        IERC20(lpToken).transfer(receiver, IERC20(lpToken).balanceOf(address(this)));
        emit DepositRings(vault, receiver, shares);
        return shares;
    }

    function depositYels(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (amount > 0) IERC20(token).approve(vault, amount);
        IYel(vault).bond(token, amount, 0);
        shares = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(receiver, shares);
        emit DepositYels(vault, receiver, shares);
        return shares;
    }

    function depositMachFi(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (token == NATIVE_TOKEN) {
            IMachFiNative(vault).mintAsCollateral{value: amount}();
        } else {
            IERC20(token).approve(vault, amount);
            IMachFiERC20(vault).mintAsCollateral(amount);
        }
        shares = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(receiver, shares);
        emit DepositMachFi(vault, receiver, shares);
        return shares;
    }

    function depositIchi(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        if (amount > 0) {
            IERC20(token).approve(vault, amount);
        }

        bool allowToken0 = IIChi(vault).allowToken0();
        shares = IIChi(vault).deposit(allowToken0 ? amount : 0, !allowToken0 ? amount : 0, receiver);

        emit DepositIchi(vault, receiver, shares);
        return shares;
    }

    function depositBeefy(address vault, address token, address receiver, uint256 amount)
        public
        returns (uint256 shares)
    {
        address iChiVault = IBeefy(vault).want();
        depositIchi(iChiVault, token, address(this), amount);

        uint256 ichiShares = IERC20(iChiVault).balanceOf(address(this));
        IERC20(iChiVault).approve(vault, ichiShares);
        IBeefy(vault).deposit(ichiShares);

        shares = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(receiver, shares);
        emit DepositBeefy(vault, receiver, shares);
        return shares;
    }

    function depositDogBone(Strategy memory T) public {
        address siloConfig = ISilo(T.vault).config();
        address borrowVault;
        {
            (address silo0, address silo1) = ISiloConfig(siloConfig).getSilos();
            borrowVault = T.vault == silo0 ? silo1 : silo0;
        }

        bool ok = IERC3156FlashLender(borrowVault).flashLoan(
            IERC3156FlashBorrower(address(this)), ISilo(borrowVault).asset(), T.flashAmount, abi.encode(T)
        );

        require(ok, "Flash loan failed");
    }

    receive() external payable {}

    function onFlashLoan(address, address _token, uint256 _amount, uint256 _fee, bytes calldata _data)
        external
        returns (bytes32)
    {
        Strategy memory T = abi.decode(_data, (Strategy));
        IERC20(_token).approve(T.swapFlashloan.router, _amount);
        (bool success,) = T.swapFlashloan.router.call{value: T.swapFlashloan.value}(T.swapFlashloan.data);
        require(success, "Swap failed");
        IERC20(T.token).approve(T.vault, IERC20(T.token).balanceOf(address(this)));
        uint256 shares =
            _depositSilo(T.vault, T.token, T.receiver, IERC20(T.token).balanceOf(address(this)), T.isProtected);
        // borrow required amount to pay back flash loan
        ISilo(msg.sender).borrow(_amount + _fee, address(this), T.receiver);
        IERC20(_token).approve(msg.sender, _amount + _fee);
        emit DepositDogBone(T.vault, T.leverage, T.receiver, shares);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _depositSilo(address vault, address token, address receiver, uint256 amount, bool isProtected)
        internal
        returns (uint256 shares)
    {
        if (amount > 0) IERC20(token).approve(vault, amount);
        shares = ISilo(vault).deposit(
            amount, receiver, isProtected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral
        );
        emit DepositSilo(vault, receiver, shares);
        return shares;
    }
}
