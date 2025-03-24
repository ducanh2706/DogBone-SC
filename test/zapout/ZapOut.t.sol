// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ZapOut} from "src/strategies/ZapOut.sol";
import {IZapOut} from "src/interfaces/zapout/IZapOut.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithdraw} from "src/interfaces/zapout/IWithdraw.sol";
import {Withdraw} from "src/strategies/Withdraw.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ZapOutBaseTest is Test {
    address public constant NATIVE_TOKEN = address(0);

    ZapOut zapOut;
    Withdraw withdrawContract;
    address alice = makeAddr("alice");

    function setUp() public {
        zapOut = new ZapOut(address(this));
        withdrawContract = new Withdraw();
        zapOut.setDelegator(address(withdrawContract));
    }

    function test_pause() public {
        zapOut.pause();
        assertTrue(zapOut.paused());
    }

    function test_unpause() public {
        zapOut.pause();
        zapOut.unpause();
        assertFalse(zapOut.paused());
    }

    function test_pause_failed_notOwner() public {
        zapOut.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        zapOut.pause();
    }

    function test_unpause_failed_notOwner() public {
        zapOut.pause();

        zapOut.transferOwnership(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        zapOut.unpause();
    }

    function test_pause_failed_alreadyPaused() public {
        zapOut.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        zapOut.pause();
    }

    function test_cantZapOut_whenPaused() public {
        zapOut.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        zapOut.zapOut("");
    }

    function test_rescueFunds_native() public {
        deal(address(zapOut), 1e18);

        zapOut.rescueFunds(NATIVE_TOKEN, 1e18, alice);

        assertEq(alice.balance, 1e18);
    }

    function test_cantRescue_ifNotOwner() public {
        deal(address(zapOut), 1e18);

        zapOut.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        zapOut.rescueFunds(NATIVE_TOKEN, 1e18, alice);
    }

    function test_canRescue_whenPaused() public {
        deal(address(zapOut), 1e18);
        zapOut.pause();

        zapOut.rescueFunds(NATIVE_TOKEN, 1e18, alice);

        assertEq(alice.balance, 1e18);
    }

    function test_onlyOwner_canSetDelegator() public {
        zapOut.setDelegator(alice);
        assertEq(zapOut.delegator(), alice);
    }

    function test_cantSetDelegator_ifNotOwner() public {
        zapOut.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        zapOut.setDelegator(alice);
    }

    function test_onlyOwner_canSetInputScaleHelper() public {
        zapOut.setInputScaleHelper(alice);
        assertEq(zapOut.inputScaleHelper(), alice);
    }

    function test_cantSetInputScaleHelper_ifNotOwner() public {
        zapOut.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        zapOut.setInputScaleHelper(alice);
    }
}
