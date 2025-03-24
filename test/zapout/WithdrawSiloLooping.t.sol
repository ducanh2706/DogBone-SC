// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Zap} from "src/strategies/Zap.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {ISilo} from "src/interfaces/silo/ISilo.sol";
import {ISiloLens} from "src/interfaces/silo/ISiloLens.sol";
import {ISiloConfig} from "src/interfaces/silo/ISiloConfig.sol";
import {IERC3156FlashBorrower} from "src/interfaces/flashloan/IERC3156FlashBorrower.sol";

contract WithdrawSiloLoopingTest is Test {
    enum Scale {
        NOT_SCALE,
        ALLOW_SCALE
    }

    string SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    uint256 blockFork = 15439776;
    uint256 sonicFork;

    address public constant NATIVE_TOKEN = address(0);

    Zap zap;
    ZapOut zapOut;
    Withdraw withdrawContract;
    address alice = makeAddr("alice");

    // SILO ADDRESS
    ISiloLens siloLens = ISiloLens(0xE05966aee69CeCD677a30f469812Ced650cE3b5E);
    ISiloConfig s_usdc_siloConfig = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2); // Market ID: 20
    ISilo wS_Vault = ISilo(0xf55902DE87Bd80c6a35614b48d7f8B612a083C12);
    ISilo usdc_Vault = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3);
    address usdc_e_shareDebtToken = address(0xbc4eF1B5453672a98073fbFF216966F5039ad256);

    // TOKEN ADDRESS
    address USDC = address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    address WS = address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.rollFork(blockFork);

        zap = new Zap();
        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_withdrawSiloLooping_success() public {
        _depositLooping();
        uint256 shares = IERC20(address(wS_Vault)).balanceOf(alice);
        uint256 assets = wS_Vault.previewRedeem(shares, ISilo.CollateralType.Collateral); // 340e18
        uint256 withdrawWS = 300e18;
        shares = wS_Vault.previewWithdraw(withdrawWS);

        bytes memory erc20Input =
            abi.encode(IZapOut.ERC20Input({tokenAddress: new address[](0), tokenAmount: new uint256[](0)}));
        bytes memory withdrawData = _prepareWithdrawData(
            address(wS_Vault), WS, withdrawWS, ISilo.CollateralType.Collateral, 212e18, USDC, 0.54e6
        );

        bytes[] memory swapData = _prepareSwapData(WS, NATIVE_TOKEN, 88e18, uint8(Scale.NOT_SCALE), 1e18);
        bytes memory zapOutValidation = _prepareZapOutValidation(NATIVE_TOKEN, 88e18);

        vm.startPrank(alice);
        IERC20(address(wS_Vault)).approve(address(zapOut), shares);

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

        console.log("Alice native balance: %d", alice.balance);
        assertEq(alice.balance, 88e18);
    }

    function _depositLooping() public {
        uint256 depositAmount = 1e20;
        uint256 flashAmount = 130e6;
        deal(WS, alice, depositAmount);

        vm.startPrank(alice);
        IERC20(WS).approve(address(zap), depositAmount);
        IERC20(usdc_e_shareDebtToken).approve(address(zap), type(uint256).max);
        zap.doStrategy(
            Zap.Strategy({
                vault: address(wS_Vault),
                token: WS,
                amount: depositAmount,
                receiver: alice,
                funcSelector: Zap.depositDogBone.selector,
                leverage: 1,
                flashAmount: flashAmount,
                isProtected: false,
                swapFlashloan: Zap.Swap({
                    fromToken: USDC,
                    fromAmount: flashAmount,
                    router: address(this),
                    data: abi.encodeWithSelector(this.swap.selector, USDC, WS, flashAmount, 1.851e30),
                    value: 0
                })
            })
        );

        vm.stopPrank();

        uint256 shares = IERC20(address(wS_Vault)).balanceOf(alice);
        uint256 assets = wS_Vault.previewRedeem(shares, ISilo.CollateralType.Collateral);
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

    function _prepareWithdrawData(
        address vault,
        address underlyingAsset,
        uint256 amount,
        ISilo.CollateralType collateralType,
        uint256 flashAmount,
        address borrowAsset,
        uint256 coef
    ) internal view returns (bytes memory) {
        bytes memory siloLoopingWithdrawData = abi.encode(
            IWithdraw.LoopingData({
                flashLoanSelector: withdrawContract.onFlashLoanSiloLooping.selector,
                strategyLoopingData: abi.encode(
                    IWithdraw.SiloLoopingWithdrawData({
                        vault: vault,
                        underlyingAsset: underlyingAsset,
                        amount: amount,
                        collateralType: collateralType,
                        flashLoanWhere: address(this),
                        flashAmount: flashAmount,
                        swap: IWithdraw.SiloLoopingSwapData({
                            router: address(this),
                            data: abi.encodeWithSelector(this.swap.selector, underlyingAsset, borrowAsset, flashAmount, coef)
                        })
                    })
                )
            })
        );

        return abi.encode(
            IZapOut.WithdrawData({
                funcSelector: withdrawContract.withdrawSiloLooping.selector,
                withdrawStrategyData: siloLoopingWithdrawData
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

        return (true, abi.encodeWithSelector(selector, tokenIn, tokenOut, _amountIn));
    }

    function flashLoan(IERC3156FlashBorrower borrower, address token, uint256 amount, bytes memory data)
        public
        returns (bool)
    {
        deal(token, address(this), amount);
        IERC20(token).transfer(address(borrower), amount);
        borrower.onFlashLoan(msg.sender, token, amount, 0, data);
        IERC20(token).transferFrom(address(borrower), address(this), amount);
        return true;
    }
}
