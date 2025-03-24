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
    uint256 blockFork = 15385168;
    uint256 sonicFork;

    address public constant NATIVE_TOKEN = address(0);

    ZapOut zapOut;
    Withdraw withdrawContract;
    address alice = makeAddr("alice");

    address S_vault = 0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6;
    address usdcE_Vault = 0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445;
    address usdcE = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

    address random_mUsdcE_holder = 0x32eEdcdBd7469ad0dC486E6551BC83E2cf21F77F;
    address random_mS_holder = 0xE9755DEf636fe3a6Fa28a59421616B144a772Ae1;
    uint256 coef;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawMachFi_usdce_success() public {
        coef = 1.85e30;

        uint256 sharesAmount = 100000e8;
        vm.prank(random_mUsdcE_holder);
        IERC20(usdcE_Vault).transfer(alice, sharesAmount);

        bytes memory erc20Input = _prepareERC20Input(usdcE_Vault, sharesAmount);
        bytes memory withdrawData = _prepareWithdrawData(usdcE_Vault, usdcE, 2000e6);
        bytes[] memory swapData = _prepareSwapData(usdcE, NATIVE_TOKEN, 2000e6, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, 2000e6 * coef / 1e18);

        vm.startPrank(alice);
        IERC20(usdcE_Vault).approve(address(zapOut), sharesAmount);
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

        console.log("Alice native balance: ", address(alice).balance);
    }

    function test_withdrawMachFi_S_success() public {}

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
                funcSelector: withdrawContract.withdrawMachFi.selector,
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
