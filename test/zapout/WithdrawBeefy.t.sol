// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {IIChi} from "src/interfaces/ichi/IIChi.sol";
import {IBeefy} from "src/interfaces/beefy/IBeefy.sol";

contract WithdrawBeefyTest is Test {
    enum Scale {
        NOT_SCALE,
        ALLOW_SCALE
    }

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 15385168;
    uint256 sonicFork;

    address public constant NATIVE_TOKEN = address(0);

    ZapOut zapOut;
    Withdraw withdrawContract;
    address alice = makeAddr("alice");

    address usdc_e = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address ichiVault_usdc_e = 0xc263e421Df94bdf57B27120A9B7B8534A6901D95;
    address beefy = 0x6f8F189250203C6387656B2cAbb00C23b7b7e680;
    address scUsd = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawBeefy_success_differentToken() public {
        uint256 depositAmount = 1000e6;
        uint256 shares = _depositBeefy(depositAmount);

        console.log("Shares: ", shares);

        // Withdraw 1/2 amount shares
        uint256 withdrawShares = shares / 2;

        vm.startPrank(alice);
        IBeefy(beefy).withdraw(withdrawShares);
        uint256 ichiShares = IERC20(ichiVault_usdc_e).balanceOf(alice);
        (uint256 wS_out, uint256 usdce_out) = IIChi(ichiVault_usdc_e).withdraw(ichiShares, alice);
        vm.stopPrank();

        console.log("wS_out: ", wS_out);
        console.log("usdce_out: ", usdce_out);

        bytes memory erc20Input = _prepareERC20Input(beefy, withdrawShares);
        bytes[] memory swapDatas = new bytes[](2);
        swapDatas[0] = _prepareSwapData(usdc_e, scUsd, usdce_out, uint8(Scale.ALLOW_SCALE), 1e18 + 1e16);
        swapDatas[1] = _prepareSwapData(wS, scUsd, wS_out, uint8(Scale.ALLOW_SCALE), 0.54e6);
        bytes memory withdrawData = _prepareWithdrawData(beefy, usdc_e, withdrawShares);
        bytes memory zapOutValidation = _prepareZapOutValidation(scUsd, 500e6);

        vm.startPrank(alice);

        IERC20(beefy).approve(address(zapOut), withdrawShares);
        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    erc20Input: erc20Input,
                    swapData: swapDatas,
                    withdrawData: withdrawData,
                    zapOutValidation: zapOutValidation,
                    receiver: alice
                })
            )
        );
        vm.stopPrank();

        console.log("Alice scUsd balance: %d", IERC20(scUsd).balanceOf(alice));
    }

    function test_withdrawBeefy_success_sameToken() public {
        uint256 depositAmount = 1000e6;
        uint256 shares = _depositBeefy(depositAmount);

        console.log("Shares: ", shares);

        // Withdraw 1/2 amount shares
        uint256 withdrawShares = shares / 2;

        vm.startPrank(alice);
        IBeefy(beefy).withdraw(withdrawShares);
        uint256 ichiShares = IERC20(ichiVault_usdc_e).balanceOf(alice);
        (uint256 wS_out, uint256 usdce_out) = IIChi(ichiVault_usdc_e).withdraw(ichiShares, address(this));
        vm.stopPrank();

        console.log("wS_out: ", wS_out);
        console.log("usdce_out: ", usdce_out);

        bytes memory erc20Input = _prepareERC20Input(beefy, withdrawShares);
        bytes[] memory swapDatas = new bytes[](1);
        swapDatas[0] = _prepareSwapData(wS, usdc_e, wS_out, uint8(Scale.ALLOW_SCALE), 0.55e6);
        bytes memory withdrawData = _prepareWithdrawData(beefy, usdc_e, withdrawShares);
        bytes memory zapOutValidation = _prepareZapOutValidation(usdc_e, 450e6);

        vm.startPrank(alice);

        IERC20(beefy).approve(address(zapOut), withdrawShares);
        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    erc20Input: erc20Input,
                    swapData: swapDatas,
                    withdrawData: withdrawData,
                    zapOutValidation: zapOutValidation,
                    receiver: alice
                })
            )
        );
        vm.stopPrank();

        console.log("Alice usdcE balance: %d", IERC20(usdc_e).balanceOf(alice));
    }

    function _depositBeefy(uint256 _amount) internal returns (uint256) {
        deal(usdc_e, alice, _amount);
        vm.startPrank(alice);

        IERC20(usdc_e).approve(ichiVault_usdc_e, _amount);
        uint256 shares = IIChi(ichiVault_usdc_e).deposit(0, _amount, alice);

        IERC20(ichiVault_usdc_e).approve(beefy, shares);
        IBeefy(beefy).deposit(shares);

        vm.stopPrank();
        return IERC20(beefy).balanceOf(alice);
    }

    function _prepareERC20Input(address token, uint256 amount) public pure returns (bytes memory) {
        address[] memory tokenAddress = new address[](1);
        tokenAddress[0] = token;

        uint256[] memory tokenAmount = new uint256[](1);
        tokenAmount[0] = amount;

        bytes memory erc20Input = abi.encode(IZapOut.ERC20Input({tokenAddress: tokenAddress, tokenAmount: tokenAmount}));
        return erc20Input;
    }

    function _prepareSwapData(address inputToken, address outputToken, uint256 amount, uint8 scaleFlag, uint256 coef)
        internal
        view
        returns (bytes memory)
    {
        bytes memory swapData = abi.encode(
            IZapOut.SwapData({
                router: address(this),
                tokenIn: inputToken,
                amountIn: amount,
                scaleFlag: scaleFlag,
                data: abi.encodeWithSelector(this.swap.selector, inputToken, outputToken, amount, coef)
            })
        );
        return swapData;
    }

    function _prepareZapOutValidation(address token, uint256 minAmountOut) internal pure returns (bytes memory) {
        return abi.encode(IZapOut.ZapOutValidation({token: token, minAmountOut: minAmountOut}));
    }

    function _prepareWithdrawData(address vault, address underlyingAsset, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes memory aaveWithdrawData =
            abi.encode(IWithdraw.AaveWithdrawData({vault: vault, underlyingAsset: underlyingAsset, amount: amount}));

        return abi.encode(
            IZapOut.WithdrawData({
                funcSelector: withdrawContract.withdrawBeefyIchi.selector,
                withdrawStrategyData: aaveWithdrawData
            })
        );
    }

    function swap(address inputToken, address outputToken, uint256 amount, uint256 coef) public returns (uint256) {
        _transfer(inputToken, msg.sender, address(this), amount);

        if (outputToken == NATIVE_TOKEN) {
            deal(address(this), amount * coef / 1e18);
            (bool ok,) = msg.sender.call{value: amount * coef / 1e18}("");
            require(ok, "Transfer failed");
        } else {
            deal(outputToken, address(this), amount * coef / 1e18);
            IERC20(outputToken).transfer(msg.sender, amount * coef / 1e18);
        }

        return amount * coef / 1e18;
    }

    function _transfer(address _token, address _from, address _to, uint256 amount) internal {
        if (_token != NATIVE_TOKEN) {
            IERC20(_token).transferFrom(_from, _to, amount);
        } else {
            (bool ok,) = _to.call{value: amount}("");
            require(ok, "Transfer failed");
        }
    }

    function getScaledInputData(bytes memory _data, uint256 _amountIn) public pure returns (bool, bytes memory) {
        bytes4 selector;
        address tokenIn;
        address tokenOut;
        assembly {
            selector := mload(add(_data, 32))
            tokenIn := mload(add(_data, 36))
            tokenOut := mload(add(_data, 68))
        }

        console.logBytes4(selector);
        console.log(tokenIn);
        console.log(tokenOut);

        return (true, abi.encodeWithSelector(selector, tokenIn, tokenOut, _amountIn));
    }
}
