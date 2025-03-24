// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SetDelegatorZapOut is Script {
    // config here
    address payable zapOut = payable(address(0));
    address newWithdraw = address(0);

    function run() public {
        require(block.chainid == 146, "Not Sonic Chain");
        require(msg.sender == ZapOut(zapOut).owner(), "Not owner of ZapOut");

        vm.startBroadcast();
        ZapOut(zapOut).setDelegator(newWithdraw);
        vm.stopBroadcast();

        require(ZapOut(zapOut).delegator() == newWithdraw, "Delegator not set successfully");
    }
}

contract SetInputScaleHelperZapOut is Script {
    // config here
    address payable zapOut = payable(address(0));
    address newInputScaleHelper = address(0);

    function run() public {
        require(block.chainid == 146, "Not Sonic Chain");
        require(msg.sender == ZapOut(zapOut).owner(), "Not owner of ZapOut");

        vm.startBroadcast();
        ZapOut(zapOut).setInputScaleHelper(newInputScaleHelper);
        vm.stopBroadcast();

        require(ZapOut(zapOut).inputScaleHelper() == newInputScaleHelper, "InputScaleHelper not set successfully");
    }
}

contract PauseZapOut is Script {
    // config here
    address payable zapOut = payable(address(0));

    function run() public {
        require(block.chainid == 146, "Not Sonic Chain");

        require(ZapOut(zapOut).paused() == false, "ZapOut already paused");
        require(msg.sender == ZapOut(zapOut).owner(), "Not owner of ZapOut");

        vm.startBroadcast();
        ZapOut(zapOut).pause();
        vm.stopBroadcast();

        require(ZapOut(zapOut).paused() == true, "ZapOut not paused successfully");
    }
}

contract UnpauseZapOut is Script {
    // config here
    address payable zapOut = payable(address(0));

    function run() public {
        require(block.chainid == 146, "Not Sonic Chain");

        require(ZapOut(zapOut).paused() == true, "ZapOut not paused");
        require(msg.sender == ZapOut(zapOut).owner(), "Not owner of ZapOut");

        vm.startBroadcast();
        ZapOut(zapOut).unpause();
        vm.stopBroadcast();

        require(ZapOut(zapOut).paused() == false, "ZapOut not unpaused successfully");
    }
}

contract RescueTokensZapOut is Script {
    // config here
    address payable zapOut = payable(address(0));
    address token = address(0);
    uint256 amount = 0;
    address receiver = address(0);

    function run() public {
        require(block.chainid == 146, "Not Sonic Chain");
        require(msg.sender == ZapOut(zapOut).owner(), "Not owner of ZapOut");

        uint256 balanceZapOut = IERC20(token).balanceOf(address(ZapOut(zapOut)));
        uint256 balanceReceiver = IERC20(token).balanceOf(receiver);

        vm.startBroadcast();
        ZapOut(zapOut).rescueFunds(token, amount, receiver);
        vm.stopBroadcast();

        require(
            IERC20(token).balanceOf(address(ZapOut(zapOut))) == balanceZapOut - amount, "Token not rescued successfully"
        );
        require(IERC20(token).balanceOf(receiver) == balanceReceiver + amount, "Token not rescued successfully");
    }
}
