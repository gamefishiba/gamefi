//SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GameFiBatchTool is Ownable {
    IERC20 public immutable _gamefi;

    constructor(address gamefi_) {
        _gamefi = IERC20(gamefi_);
    }

    function transfer(address[] memory accept, uint256[] memory amount)
        public
    {
        for (uint256 i = 0; i < accept.length; i++) {
            _gamefi.transferFrom(msg.sender, accept[i], amount[i]);
        }
    }
}
