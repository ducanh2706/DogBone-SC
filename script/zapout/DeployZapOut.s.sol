// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";

contract DeployZapOut is Script {
    address owner = 0x7aF234d569aB6360693806D7e7f439Ec2114F93c;
    address inputScaleHelper = 0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D;

    function run() public returns (address) {
        vm.startBroadcast();

        require(block.chainid == 146, "Not Sonic Chain");

        ZapOut zapOut = new ZapOut(inputScaleHelper);

        vm.stopBroadcast();

        assert(zapOut.owner() == owner);
        assert(zapOut.paused() == false);
        assert(zapOut.delegator() == address(0));

        return address(zapOut);
    }
}
