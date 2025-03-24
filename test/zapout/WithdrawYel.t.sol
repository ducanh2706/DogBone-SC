// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {IYel} from "src/interfaces/yel/IYel.sol";

contract WithdrawYelTest is Test {
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

    address public constant LSTS = 0x555733fBa1CA24ec45e7027E00C4B6c5065BaC96;
    address public constant STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawYel_success() public {
        uint256 amount = 100e18;
        uint256 shares = _deposit(amount) / 2;

        bytes memory erc20Input = _prepareERC20Input(LSTS, shares);
        bytes memory withdrawData = _prepareWithdrawData(LSTS, STS, shares);
        bytes[] memory swapDatas = _prepareSwapData(STS, NATIVE_TOKEN, amount / 2, uint8(Scale.ALLOW_SCALE), 1e18);
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, amount / 2 - 1e18);

        vm.startPrank(alice);

        IERC20(LSTS).approve(address(zapOut), shares);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: withdrawData,
                    swapData: swapDatas,
                    zapOutValidation: zapOutValidation
                })
            )
        );

        vm.stopPrank();

        console.log("Alice native balance", address(alice).balance);
    }

    function _deposit(uint256 amount) internal returns (uint256 shares) {
        deal(STS, alice, amount);

        vm.startPrank(alice);

        IERC20(STS).approve(LSTS, amount);
        IYel(LSTS).bond(STS, amount, 0);

        vm.stopPrank();

        shares = IERC20(LSTS).balanceOf(alice);
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
        returns (bytes[] memory)
    {
        bytes[] memory swapDatas = new bytes[](1);
        swapDatas[0] = abi.encode(
            IZapOut.SwapData({
                router: address(this),
                tokenIn: inputToken,
                amountIn: amount,
                scaleFlag: scaleFlag,
                data: abi.encodeWithSelector(this.swap.selector, inputToken, outputToken, amount, coef)
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
                funcSelector: withdrawContract.withdrawYel.selector,
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
        uint256 coef;
        assembly {
            selector := mload(add(_data, 32))
            tokenIn := mload(add(_data, 36))
            tokenOut := mload(add(_data, 68))
            coef := mload(add(_data, 132))
        }

        return (true, abi.encodeWithSelector(selector, tokenIn, tokenOut, _amountIn, coef));
    }
}
