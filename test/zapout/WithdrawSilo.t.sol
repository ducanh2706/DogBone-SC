// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";

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

    address wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address silo0_wS_20 = 0xf55902DE87Bd80c6a35614b48d7f8B612a083C12;

    address usdc_e = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address silo1_usdcE_20 = 0x322e1d5384aa4ED66AeCa770B95686271de61dc3;

    address random_wS_holder = 0x8D4D19405Ba352e4767681C28936fc0a9A8C8dFe;

    uint256 coef;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawSilo_wS_success() public {
        coef = 0.56e6; // 1 wS = 0.56 USDC

        uint256 withdrawWS = 100e18;
        // Withdraw 100 wS from silo0_wS_20
        uint256 shares = ISilo(silo0_wS_20).previewWithdraw(withdrawWS);

        vm.prank(random_wS_holder);
        IERC20(silo0_wS_20).transfer(alice, shares);

        bytes memory erc20Input = _prepareERC20Input(silo0_wS_20, shares);
        bytes memory withdrawData = _prepareWithdrawData(silo0_wS_20, wS, withdrawWS);
        bytes[] memory swapData = _prepareSwapData(wS, usdc_e, withdrawWS, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(usdc_e, withdrawWS * coef / 1e18);

        vm.startPrank(alice);
        IERC20(silo0_wS_20).approve(address(zapOut), shares);
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

        console.log("Alice's USDC.e balance", IERC20(usdc_e).balanceOf(alice));
        assertEq(IERC20(usdc_e).balanceOf(alice), withdrawWS * coef / 1e18);
    }

    function test_withdrawSilo_wS_failed_exceedAmount() public {
        coef = 0.56e6; // 1 wS = 0.56 USDC

        uint256 withdrawWS = 100e18;
        // Withdraw 100 wS from silo0_wS_20
        uint256 shares = ISilo(silo0_wS_20).previewWithdraw(withdrawWS) / 2;

        vm.prank(random_wS_holder);
        IERC20(silo0_wS_20).transfer(alice, shares);

        bytes memory erc20Input = _prepareERC20Input(silo0_wS_20, shares);
        bytes memory withdrawData = _prepareWithdrawData(silo0_wS_20, wS, withdrawWS);
        bytes[] memory swapData = _prepareSwapData(wS, usdc_e, withdrawWS, uint8(Scale.NOT_SCALE));
        bytes memory zapOutValidation = _prepareZapOutValidation(usdc_e, withdrawWS * coef / 1e18);

        vm.startPrank(alice);
        IERC20(silo0_wS_20).approve(address(zapOut), shares);
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
        bytes memory siloWithdrawData = abi.encode(
            IWithdraw.SiloWithdrawData({
                vault: vault,
                underlyingAsset: underlyingAsset,
                amount: amount,
                collateralType: ISilo.CollateralType.Collateral
            })
        );

        return abi.encode(
            IZapOut.WithdrawData({
                funcSelector: withdrawContract.withdrawSilo.selector,
                withdrawStrategyData: siloWithdrawData
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
