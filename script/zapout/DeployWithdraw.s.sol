// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";

contract DeployWithdraw is Script {
    address owner = 0x7aF234d569aB6360693806D7e7f439Ec2114F93c;
    address inputScaleHelper = 0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D;

    function run() public returns (address) {
        vm.startBroadcast();

        require(block.chainid == 146, "Not Sonic Chain");

        Withdraw withdraw = new Withdraw();

        vm.stopBroadcast();

        return address(withdraw);
    }
}
