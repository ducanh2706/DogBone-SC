// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";

contract WithdrawAaveTest is Test {
    enum Scale {
        NOT_SCALE,
        ALLOW_SCALE
    }

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 15357027;
    uint256 sonicFork;

    address public constant NATIVE_TOKEN = address(0);

    ZapOut zapOut;
    Withdraw withdrawContract;
    address alice = makeAddr("alice");

    address public constant AAVE = 0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    address usdc_e = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address scusd = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    address a_usdc_e = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;
    address pendle_a_usdc_e = 0xc4A9d8b486f388CC0E4168d2904277e8C8372FA3;

    uint256 coef;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
    }

    function test_withdrawAave_usdce_success() public {
        coef = 103e16; // 1 usdc.e = 1.03 scusd

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 100e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();

        console.log("Alice's scUSD balance: ", IERC20(scusd).balanceOf(alice));
        assertEq(IERC20(scusd).balanceOf(alice), 100e6 * coef / 1e18);
    }

    function test_withdrawAave_usdc_e_failed_not_enough_amountOut() public {
        coef = 102e16; // 1 usdc.e = 1.02 scusd, assume slippage

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 100e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 103e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        vm.expectRevert("ZapOut: insufficient amount out");
        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();
    }

    function test_withdrawAave_usdc_e_failed_scaleUp_success() public {
        coef = 103e16; // 1 usdc.e = 1.03 scusd

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 99e6, uint8(Scale.ALLOW_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();

        console.log("Alice's scUSD balance: ", IERC20(scusd).balanceOf(alice));
        assertEq(IERC20(scusd).balanceOf(alice), 100e6 * coef / 1e18);
    }

    function test_withdrawAave_usdc_e_failed_scaleDown_success() public {
        coef = 103e16; // 1 usdc.e = 1.03 scusd

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 105e6, uint8(Scale.ALLOW_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();

        console.log("Alice's scUSD balance: ", IERC20(scusd).balanceOf(alice));
        assertEq(IERC20(scusd).balanceOf(alice), 100e6 * coef / 1e18);
    }

    function test_withdrawAave_usdc_e_failed_scaleDown_failed() public {
        coef = 103e16; // 1 usdc.e = 1.03 scusd

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 105e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        vm.expectRevert("ZapOut: insufficient token in balance");
        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();
    }

    function test_withdrawAave_usdc_e_failed_withdraw_exceed() public {
        coef = 103e16; // 1 usdc.e = 1.03 scusd

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 101e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, scusd, 100e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        vm.expectRevert();
        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();
    }

    function test_withdrawAave_usdc_e_success_withdrawNative() public {
        coef = 2e30; // 1 usdc.e = 2 S

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 100e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 100e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 100e6);
        bytes[] memory swapData = _prepareSwapData(usdc_e, NATIVE_TOKEN, 100e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, 200e18);

        console.log("Before Alice balance: ", alice.balance);

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 100e6);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );
        vm.stopPrank();

        console.log("Alice's S balance: ", alice.balance);
        assertEq(alice.balance, 100e6 * coef / 1e18);
    }

    function _prepareERC20Input(address token, uint256 amount) public pure returns (bytes memory) {
        address[] memory tokenAddress = new address[](1);
        tokenAddress[0] = token;

        uint256[] memory tokenAmount = new uint256[](1);
        tokenAmount[0] = amount;

        bytes memory erc20Input = abi.encode(IZapOut.ERC20Input({tokenAddress: tokenAddress, tokenAmount: tokenAmount}));
        return erc20Input;
    }

    function _prepareSwapData(address inputToken, address outputToken, uint256 amount, uint8 scaleFlag)
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory swapDatas = new bytes[](1);
        swapDatas[0] = abi.encode(
            IZapOut.SwapData({
                router: address(this),
                tokenIn: inputToken,
                amountIn: amount,
                scaleFlag: scaleFlag,
                data: abi.encodeWithSelector(this.swap.selector, inputToken, outputToken, amount)
            })
        );
        return swapDatas;
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
                delegateTo: address(withdrawContract),
                funcSelector: withdrawContract.withdrawAave.selector,
                withdrawStrategyData: aaveWithdrawData
            })
        );
    }

    function swap(address inputToken, address outputToken, uint256 amount) public returns (uint256) {
        _transfer(inputToken, msg.sender, address(this), amount);

        if (outputToken == NATIVE_TOKEN) {
            deal(msg.sender, amount * coef / 1e18);
        } else {
            deal(outputToken, msg.sender, amount * coef / 1e18);
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
