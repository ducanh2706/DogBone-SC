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

    address public constant AAVE = 0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    address usdc_e = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address scusd = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    address a_usdc_e = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;
    address pendle_a_usdc_e = 0xc4A9d8b486f388CC0E4168d2904277e8C8372FA3;

    uint256 coef;

    function setUp() public {
        sonicFork = vm.createFork(SONIC_RPC_URL);
        vm.selectFork(sonicFork);
        vm.roll(blockFork);

        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
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

    function test_withdrawAave_usdc_e_success_withRealSwapData_noScale() public {
        zapOut.setInputScaleHelper(0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D);

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 115e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 115e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 115e6);
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 100e6);

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = abi.encode(
            IZapOut.SwapData({
                router: 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5,
                tokenIn: usdc_e,
                amountIn: 115e6,
                scaleFlag: uint8(Scale.NOT_SCALE),
                data: hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000408cc7a56b0000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8cd4d2b142235d5650ffa6a38787ed0b7d7a51c0c00000000000000000000003700000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000007300000000000000000000000006db648800000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000000000006dac2c00000000000000000000000000000000000000000000000000000000006d9a3260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002447b22536f75726365223a226e756c6c3a646f63732e6b79626572737761702e636f6d222c22416d6f756e74496e555344223a223131352e3039333637343037313839313236222c22416d6f756e744f7574555344223a223131342e3935383835383632393736303534222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22313135303431343136222c2254696d657374616d70223a313734323731383332342c22526f7574654944223a22222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22424f6a72646173634857495577514f4b565a6d685a6b626339744d517748494b3274582b617258514e356e31477047307841426348555262343157694f5644334f4d66714847494e5a30494f4c4f653654334639422f3149564a5277526a367a6d694c4a49674675644f4f564a4e473938694d3278555044547737344f363943636e723279306d5a4846317a475162615a4956557450624a747764534547624e4b457064534945734371303339324d7a37507461615730795a36335576685361706337706c6c7354746f49586d754d2b3362756b6531362b7a476e4b364b6f726b46635843737a70442f4977586e42624d473134784d7632634a664b714643777165515657324c78456f36484e536956734b654c6d5a4e2b494a527456674f63547737437773773734616e7734562b3941617778413631596c764a7145573055696247387458464d5068623738503956363930664c773d3d227d7d00000000000000000000000000000000000000000000000000000000"
            })
        );

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 115e6);

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
    }

    function test_withdrawAave_usdc_e_success_withRealSwapData_scaleDown() public {
        zapOut.setInputScaleHelper(0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D);

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 110e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 110e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 110e6);
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 110e6);

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = abi.encode(
            IZapOut.SwapData({
                router: 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5,
                tokenIn: usdc_e,
                amountIn: 115e6,
                scaleFlag: uint8(Scale.ALLOW_SCALE),
                data: hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000408cc7a56b0000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8cd4d2b142235d5650ffa6a38787ed0b7d7a51c0c00000000000000000000003700000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000007300000000000000000000000006db648800000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000000000006dac2c00000000000000000000000000000000000000000000000000000000006d9a3260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002447b22536f75726365223a226e756c6c3a646f63732e6b79626572737761702e636f6d222c22416d6f756e74496e555344223a223131352e3039333637343037313839313236222c22416d6f756e744f7574555344223a223131342e3935383835383632393736303534222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22313135303431343136222c2254696d657374616d70223a313734323731383332342c22526f7574654944223a22222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22424f6a72646173634857495577514f4b565a6d685a6b626339744d517748494b3274582b617258514e356e31477047307841426348555262343157694f5644334f4d66714847494e5a30494f4c4f653654334639422f3149564a5277526a367a6d694c4a49674675644f4f564a4e473938694d3278555044547737344f363943636e723279306d5a4846317a475162615a4956557450624a747764534547624e4b457064534945734371303339324d7a37507461615730795a36335576685361706337706c6c7354746f49586d754d2b3362756b6531362b7a476e4b364b6f726b46635843737a70442f4977586e42624d473134784d7632634a664b714643777165515657324c78456f36484e536956734b654c6d5a4e2b494a527456674f63547737437773773734616e7734562b3941617778413631596c764a7145573055696247387458464d5068623738503956363930664c773d3d227d7d00000000000000000000000000000000000000000000000000000000"
            })
        );

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 110e6);

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
    }

    function test_withdrawAave_usdc_e_success_withRealSwapData_scaleUp() public {
        zapOut.setInputScaleHelper(0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D);

        vm.prank(pendle_a_usdc_e);
        IERC20(a_usdc_e).transfer(alice, 120e6);

        bytes memory erc20Input = _prepareERC20Input(a_usdc_e, 120e6);
        bytes memory withdrawData = _prepareWithdrawData(AAVE, usdc_e, 120e6);
        bytes memory zapOutValidation = _prepareZapOutValidation(scusd, 120e6);

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = abi.encode(
            IZapOut.SwapData({
                router: 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5,
                tokenIn: usdc_e,
                amountIn: 115e6,
                scaleFlag: uint8(Scale.ALLOW_SCALE),
                data: hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000005a000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000408cc7a56b0000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8cd4d2b142235d5650ffa6a38787ed0b7d7a51c0c00000000000000000000003700000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae0000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000007300000000000000000000000006db648800000000000000000000000029219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000d3dce716f3ef535c5ff8d041c1a41c3bd89b97ae000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000005615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f0000000000000000000000000000000000000000000000000000000006dac2c00000000000000000000000000000000000000000000000000000000006d9a3260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002447b22536f75726365223a226e756c6c3a646f63732e6b79626572737761702e636f6d222c22416d6f756e74496e555344223a223131352e3039333637343037313839313236222c22416d6f756e744f7574555344223a223131342e3935383835383632393736303534222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22313135303431343136222c2254696d657374616d70223a313734323731383332342c22526f7574654944223a22222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22424f6a72646173634857495577514f4b565a6d685a6b626339744d517748494b3274582b617258514e356e31477047307841426348555262343157694f5644334f4d66714847494e5a30494f4c4f653654334639422f3149564a5277526a367a6d694c4a49674675644f4f564a4e473938694d3278555044547737344f363943636e723279306d5a4846317a475162615a4956557450624a747764534547624e4b457064534945734371303339324d7a37507461615730795a36335576685361706337706c6c7354746f49586d754d2b3362756b6531362b7a476e4b364b6f726b46635843737a70442f4977586e42624d473134784d7632634a664b714643777165515657324c78456f36484e536956734b654c6d5a4e2b494a527456674f63547737437773773734616e7734562b3941617778413631596c764a7145573055696247387458464d5068623738503956363930664c773d3d227d7d00000000000000000000000000000000000000000000000000000000"
            })
        );

        vm.startPrank(alice);
        IERC20(a_usdc_e).approve(address(zapOut), 120e6);

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
