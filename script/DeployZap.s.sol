// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Zap} from "src/strategies/Zap.sol";

contract DeployZap is Script {
    function run() public returns (address) {
        vm.startBroadcast();
        require(block.chainid == 146, "Not Sonic Chain");
        Zap zap = new Zap();
        vm.stopBroadcast();
        return address(zap);
    }
}
