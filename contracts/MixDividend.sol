pragma solidity ^0.5.6;

import "./klaytn-contracts/math/SafeMath.sol";
import "./libraries/SignedSafeMath.sol";
import "./interfaces/IMixDividend.sol";
import "./interfaces/IMixEmitter.sol";
import "./interfaces/IMix.sol";

contract MixDividend is IMixDividend {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IMixEmitter private mixEmitter;
    IMix private mix;
    uint256 private pid;

    constructor(
        IMixEmitter _mixEmitter,
        IMix _mix,
        uint256 _pid
    ) public {
        mixEmitter = _mixEmitter;
        mix = _mix;
        pid = _pid;
    }

    uint256 internal currentBalance = 0;
    uint256 internal totalShare = 0;
    mapping(address => uint256) internal shares;

    uint256 constant internal pointsMultiplier = 2**128;
    uint256 internal pointsPerShare = 0;
    mapping(address => int256) internal pointsCorrection;
    mapping(address => uint256) internal claimed;

    function updateBalance() internal {
        if (totalShare > 0) {
            mixEmitter.updatePool(pid);
            uint256 balance = mix.balanceOf(address(this));
            uint256 value = balance.sub(currentBalance);
            if (value > 0) {
                pointsPerShare = pointsPerShare.add(value.mul(pointsMultiplier).div(totalShare));
                emit Distribute(msg.sender, value);
            }
            currentBalance = balance;
        }
    }

    function claimedOf(address owner) public view returns (uint256) {
        return claimed[owner];
    }

    function accumulativeOf(address owner) public view returns (uint256) {
        uint256 _pointsPerShare = pointsPerShare;
        if (totalShare > 0) {
            uint256 balance = mixEmitter.pendingMix(pid).add(mix.balanceOf(address(this)));
            uint256 value = balance.sub(currentBalance);
            if (value > 0) {
                _pointsPerShare = _pointsPerShare.add(value.mul(pointsMultiplier).div(totalShare));
            }
            return uint256(int256(_pointsPerShare.mul(shares[owner])).add(pointsCorrection[owner])).div(pointsMultiplier);
        }
        return 0;
    }

    function claimableOf(address owner) external view returns (uint256) {
        return accumulativeOf(owner).sub(claimed[owner]);
    }

    function _accumulativeOf(address owner) internal view returns (uint256) {
        return uint256(int256(pointsPerShare.mul(shares[owner])).add(pointsCorrection[owner])).div(pointsMultiplier);
    }

    function _claimableOf(address owner) internal view returns (uint256) {
        return _accumulativeOf(owner).sub(claimed[owner]);
    }

    function claim() external {
        updateBalance();
        uint256 claimable = _claimableOf(msg.sender);
        if (claimable > 0) {
            claimed[msg.sender] = claimed[msg.sender].add(claimable);
            emit Claim(msg.sender, claimable);
            mix.transfer(msg.sender, claimable);
            currentBalance = currentBalance.sub(claimable);
        }
    }

    function _addShare(uint256 share) internal {
        updateBalance();
        totalShare = totalShare.add(share);
        shares[msg.sender] = shares[msg.sender].add(share);
        pointsCorrection[msg.sender] = pointsCorrection[msg.sender].sub(int256(pointsPerShare.mul(share)));
    }

    function _subShare(uint256 share) internal {
        updateBalance();
        totalShare = totalShare.sub(share);
        shares[msg.sender] = shares[msg.sender].sub(share);
        pointsCorrection[msg.sender] = pointsCorrection[msg.sender].add(int256(pointsPerShare.mul(share)));
    }
}
