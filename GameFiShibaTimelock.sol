//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


////////////////////////////////////////////////////////////////////////
////      ________                         ___________ __           ////
////     /  _____/ _____     _____    ____ \_   _____/|__|          ////    
////    /   \  ___ \__  \   /     \ _/ __ \ |    __)  |  |          ////
////    \    \_\  \ / __ \_|  Y Y  \\  ___/ |     \   |  |          ////
////     \______  /(____  /|__|_|  / \___  >\___  /   |__|          ////
////            \/      \/       \/      \/     \/                  ////
////           _________ __      __ ___                             ////
////          /   _____/|  |__  |__|\_ |__  _____                   ////
////          \_____  \ |  |  \ |  | | __ \ \__  \                  ////
////          /        \|   Y  \|  | | \_\ \ / __ \_                ////
////         /_______  /|___|  /|__| |___  /(____  /                ////
////                 \/      \/          \/      \/                 ////
////                                                gamefishiba.io  ////   
////////////////////////////////////////////////////////////////////////

/// @title Gamefi Token Timelock
/// @author Gamefi Shiba team
contract GameFiShibaTimelock {
    using SafeMath for uint256;

    using SafeERC20 for IERC20;

    // ERC20 basic token contract being held
    IERC20 private immutable _token;

    // beneficiary of tokens after they are released
    address private immutable _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    uint256 private _createTime;

    uint256 private _delayTime;

    uint256 private _numReleasePerSecond;

    uint256 private _lastReleaseTime;

    bool public _initializeable;

    constructor(IERC20 token_, address beneficiary_) {
        _token = token_;
        _beneficiary = beneficiary_;
    }

    function initialize(uint256 releaseTime_, uint256 delayTime_) public {
        require(
            releaseTime_ > block.timestamp,
            "TokenTimelock: release time is before current time"
        );
        require(!_initializeable, "Initialize fail");
        _initializeable = true;
        _releaseTime = releaseTime_;
        _createTime = block.timestamp;
        _delayTime = delayTime_;
        _lastReleaseTime = delayTime_.add(block.timestamp);
        _numReleasePerSecond = releaseTime_.sub(
            block.timestamp.add(delayTime_)
        );
        _numReleasePerSecond = _token.balanceOf(address(this)).div(
            _numReleasePerSecond
        );
        require(_numReleasePerSecond > 0, "numReleasePerSecond must gt 0");
    }

    /**
     * @return the token being held.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the time when the tokens are released.
     */
    function releaseTime() public view returns (uint256) {
        return _releaseTime;
    }

    function delayTime() public view returns (uint256) {
        return _delayTime;
    }

    function createTime() public view returns (uint256) {
        return _createTime;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public returns (uint256 amount) {
        require(_initializeable, "not initialize");
        require(
            block.timestamp >= _lastReleaseTime,
            "TokenTimelock: current time is before release time"
        );
        amount = _numReleasePerSecond.mul(block.timestamp - _lastReleaseTime);
        require(amount > 0, "TokenTimelock: no tokens to release");
        uint256 balance = token().balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        _lastReleaseTime = block.timestamp;
        token().safeTransfer(beneficiary(), amount);
    }
}
