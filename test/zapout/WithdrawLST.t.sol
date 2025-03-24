// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";

contract WithdrawLSTTest is Test {
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

    address OS = 0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794;
    address STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address ANS = 0x0C4E186Eae8aCAA7F7de1315D5AD174BE39Ec987;

    address random_OS_holder = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    address random_ANS_holder = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;

    uint256 coef;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawStS_success() public {
        coef = 1e18 + 1e16;
        uint256 amount = 1e18;
        deal(STS, alice, amount);

        bytes memory erc20Input = _prepareERC20Input(STS, amount);
        bytes[] memory swapData = _prepareSwapData(STS, NATIVE_TOKEN, amount, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, amount * coef / 1e18);

        vm.startPrank(alice);

        IERC20(STS).approve(address(zapOut), amount);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: "",
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );

        vm.stopPrank();

        console.log("alice balance: %d", alice.balance);
        assertEq(alice.balance, amount * coef / 1e18);
    }

    function test_withdrawOS_success() public {
        coef = 1e18 + 1e16;
        uint256 amount = 1e18;
        vm.prank(random_OS_holder);
        IERC20(OS).transfer(alice, amount);

        bytes memory erc20Input = _prepareERC20Input(OS, amount);
        bytes[] memory swapData = _prepareSwapData(OS, NATIVE_TOKEN, amount, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, amount * coef / 1e18);

        vm.startPrank(alice);

        IERC20(OS).approve(address(zapOut), amount);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: "",
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );

        vm.stopPrank();

        console.log("alice balance: %d", alice.balance);
        assertEq(alice.balance, amount * coef / 1e18);
    }

    function test_withdrawAnS_success() public {
        coef = 1e18 + 1e16;
        uint256 amount = 1e18;
        vm.prank(random_ANS_holder);
        IERC20(ANS).transfer(alice, amount);

        bytes memory erc20Input = _prepareERC20Input(ANS, amount);
        bytes[] memory swapData = _prepareSwapData(ANS, NATIVE_TOKEN, amount, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, amount * coef / 1e18);

        vm.startPrank(alice);

        IERC20(ANS).approve(address(zapOut), amount);

        zapOut.zapOut(
            abi.encode(
                IZapOut.ZapOutData({
                    receiver: alice,
                    erc20Input: erc20Input,
                    withdrawData: "",
                    swapData: swapData,
                    zapOutValidation: zapOutValidation
                })
            )
        );

        vm.stopPrank();

        console.log("alice balance: %d", alice.balance);
        assertEq(alice.balance, amount * coef / 1e18);
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
