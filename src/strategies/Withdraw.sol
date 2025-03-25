// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {IAave} from "src/interfaces/aave/IAave.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMachFiERC20} from "src/interfaces/machfi/IMachFiERC20.sol";
import {IYel} from "src/interfaces/yel/IYel.sol";
import {IIChi} from "src/interfaces/ichi/IIChi.sol";
import {IBeefy} from "src/interfaces/beefy/IBeefy.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {IERC3156FlashBorrower} from "src/interfaces/flashloan/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/flashloan/IERC3156FlashLender.sol";

contract Withdraw is IWithdraw {
    address public constant AAVE = 0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    address public constant VICUNA = 0xaa1C02a83362BcE106dFf6eB65282fE8B97A1665;

    function withdrawAave(bytes memory _aaveWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_aaveWithdrawData, (AaveWithdrawData));
        amountOut = IAave(AAVE).withdraw(withdrawData.underlyingAsset, withdrawData.amount, address(this));
    }

    function withdrawVicuna(bytes memory _vicunaWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_vicunaWithdrawData, (AaveWithdrawData));
        amountOut = IAave(VICUNA).withdraw(withdrawData.underlyingAsset, withdrawData.amount, address(this));
    }

    function withdrawMachFi(bytes memory _machFiWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_machFiWithdrawData, (AaveWithdrawData));
        uint256 ok = IMachFiERC20(withdrawData.vault).redeemUnderlying(withdrawData.amount);
        if (ok != 0) {
            revert(string(abi.encodePacked("Withdraw MachFi failed: ", ok)));
        }
        amountOut = withdrawData.amount;
    }

    function withdrawSilo(bytes memory _siloWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_siloWithdrawData, (AaveWithdrawData));
        ISilo(withdrawData.vault).withdraw(withdrawData.amount, address(this), address(this));
        amountOut = withdrawData.amount;
    }

    function withdrawIchi(bytes memory _ichiWithdrawData) public override returns (uint256[] memory amountsOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_ichiWithdrawData, (AaveWithdrawData));
        // amount here is the lp amount to withdraw
        amountsOut = new uint256[](2);
        (amountsOut[0], amountsOut[1]) = IIChi(withdrawData.vault).withdraw(withdrawData.amount, address(this));
    }

    function withdrawBeefyIchi(bytes memory _beefyIchiWithdrawData)
        public
        override
        returns (uint256[] memory amountsOut)
    {
        AaveWithdrawData memory withdrawData = abi.decode(_beefyIchiWithdrawData, (AaveWithdrawData));
        address iChiVault = IBeefy(withdrawData.vault).want();
        IBeefy(withdrawData.vault).withdraw(withdrawData.amount);
        uint256 ichiLPWithdraw = IERC20(iChiVault).balanceOf(address(this));
        amountsOut = new uint256[](2);
        (amountsOut[0], amountsOut[1]) = IIChi(iChiVault).withdraw(ichiLPWithdraw, address(this));
    }

    function withdrawYel(bytes memory _yelWithdrawData) public override returns (uint256 amountOut) {
        AaveWithdrawData memory withdrawData = abi.decode(_yelWithdrawData, (AaveWithdrawData));
        // amount here is the lp amount to withdraw
        uint256 beforeBalance = IERC20(withdrawData.underlyingAsset).balanceOf(address(this));
        IYel(withdrawData.vault).debond(withdrawData.amount, new address[](0), new uint8[](0));
        amountOut = IERC20(withdrawData.underlyingAsset).balanceOf(address(this)) - beforeBalance;
    }

    function withdrawSiloLooping(bytes memory _loopingWithdrawData) public override returns (uint256 amountOut) {
        LoopingData memory loopingData = abi.decode(_loopingWithdrawData, (LoopingData));
        SiloLoopingWithdrawData memory withdrawData =
            abi.decode(loopingData.strategyLoopingData, (SiloLoopingWithdrawData));

        address siloConfig = ISilo(withdrawData.vault).config();
        address borrowVault;
        {
            (address silo0, address silo1) = ISiloConfig(siloConfig).getSilos();
            borrowVault = withdrawData.vault == silo0 ? silo1 : silo0;
        }

        uint256 beforeBalance = IERC20(withdrawData.underlyingAsset).balanceOf(address(this));
        bool ok = IERC3156FlashLender(withdrawData.flashLoanWhere).flashLoan(
            IERC3156FlashBorrower(address(this)),
            withdrawData.underlyingAsset,
            withdrawData.flashAmount,
            _loopingWithdrawData
        );
        require(ok, "Silo Looping flash loan failed");
        amountOut = IERC20(withdrawData.underlyingAsset).balanceOf(address(this)) - beforeBalance;
    }

    function onFlashLoanSiloLooping(
        address _token,
        uint256 _amount,
        uint256 _fee,
        address _receiver,
        bytes calldata _data
    ) external {
        SiloLoopingWithdrawData memory withdrawData = abi.decode(_data, (SiloLoopingWithdrawData));
        address siloConfig = ISilo(withdrawData.vault).config();
        address borrowVault;
        {
            (address silo0, address silo1) = ISiloConfig(siloConfig).getSilos();
            borrowVault = withdrawData.vault == silo0 ? silo1 : silo0;
        }
        address borrowedToken = ISilo(borrowVault).asset();

        if (withdrawData.underlyingAsset != _token) {
            revert("Silo Looping: wrong token");
        }

        // Swap all to borrowed token
        // Assume native token will be first swapped into wrapped native token before the swapping
        {
            IERC20(_token).approve(withdrawData.swap.router, _amount);
            (address router, bytes memory data) = (withdrawData.swap.router, withdrawData.swap.data);
            (bool success, bytes memory returnedData) = router.call(data);
            if (!success) {
                revert(string(abi.encodePacked("Silo Looping: swap failed: ", returnedData)));
            }
            IERC20(_token).approve(withdrawData.swap.router, 0);
        }

        // Repay borrow token
        {
            uint256 borrowTokenBalance = IERC20(borrowedToken).balanceOf(address(this));
            IERC20(borrowedToken).approve(borrowVault, borrowTokenBalance);
            ISilo(borrowVault).repay(borrowTokenBalance, _receiver);
            IERC20(borrowedToken).approve(borrowVault, 0);
        }

        // Withdraw from silo
        {
            ISilo(withdrawData.vault).withdraw(
                withdrawData.amount, address(this), _receiver, withdrawData.collateralType
            );
        }

        // payback flashloan
        // this is assumed to be ok because the contract holds no funds.
        IERC20(_token).approve(msg.sender, _amount + _fee);
    }
}
