//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./GameFiShibaCommon.sol";

contract GameFiShibaCoinPool is Ownable, Pausable {
    using SafeMath for uint256;

    IGameFiShibaSire private immutable _sire;

    IGameFiShiba private immutable _cryptoshiba;

    IERC20 private immutable _gameFiToken;

    event Withdraw(address, uint256);

    event LBChange(address, uint256);

    event NPBChange(address, uint256);

    event ReceiveAward(uint tokenId,uint beginBlock,uint curBlock,uint amount);

    mapping(uint256 => uint256) blockNumber;

    uint256 private _longestBlockNumber;
    uint256 private _numPerBlockNumber;

    constructor(
        address cryptoshiba_,
        address sire_,
        address gameFiToken_
    ) {
        _sire = IGameFiShibaSire(sire_);
        _cryptoshiba = IGameFiShiba(cryptoshiba_);
        _gameFiToken = IERC20(gameFiToken_);
        setLB(14400);
        setNPB(0x13bcbf936b38e);
    }

    function longestBlockNumber() public view returns (uint256) {
        return _longestBlockNumber;
    }

    function numPerBlockNumber() public view returns (uint256) {
        return _numPerBlockNumber;
    }

    function setLB(uint256 longestBlockNumber_) public onlyOwner {
        _longestBlockNumber = longestBlockNumber_;
        emit LBChange(msg.sender, longestBlockNumber_);
    }

    function setNPB(uint256 numPerBlockNumber_) public onlyOwner {
        _numPerBlockNumber = numPerBlockNumber_;
        emit NPBChange(msg.sender, numPerBlockNumber_);
    }

    function _withdraw(uint256 tokenId) private returns (uint256) {
        require(_cryptoshiba.ownerOf(tokenId) == msg.sender,"not owner of tokenId");
        uint256 _nunmOfBlock = _estimatedIncome(tokenId);
        require( _gameFiToken.balanceOf(address(this)) > _nunmOfBlock, "error balance" );
        emit ReceiveAward(tokenId,blockNumber[tokenId],block.number,_nunmOfBlock);
        blockNumber[tokenId] = block.number;
        _gameFiToken.transfer(msg.sender, _nunmOfBlock);
        return _nunmOfBlock;
    }

    function withdraw(uint256[] memory tokenIds)
        public
        whenNotPaused
        returns (uint256 _nunmOfBlock)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _nunmOfBlock += _withdraw(tokenIds[i]);
        }
    }

    function estimatedIncome(uint256[] memory tokenIds)
        public
        view
        whenNotPaused
        returns (uint256 _nunmOfBlock)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (block.number > blockNumber[tokenIds[i]]) {
                _nunmOfBlock += _estimatedIncome(tokenIds[i]);
            }
        }
    }

    function _estimatedIncome(uint256 tokenId) private view returns (uint256) {
        require(block.number > blockNumber[tokenId], "error blocknumber");
        uint256 _nunmOfBlock = block.number.sub(blockNumber[tokenId]);
        _nunmOfBlock = _nunmOfBlock > _longestBlockNumber
            ? _longestBlockNumber
            : _nunmOfBlock;
        return
            _sire.knighthood(tokenId) > 2
                ? _nunmOfBlock.mul(_numPerBlockNumber).mul(10)
                : _nunmOfBlock.mul(_numPerBlockNumber);
    }

    //
    //pausable
    //
    function pause() public whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() public whenPaused onlyOwner {
        _unpause();
    }

    function withdraw() public whenPaused onlyOwner {
        _gameFiToken.transfer(
            msg.sender,
            _gameFiToken.balanceOf(address(this))
        );
    }
}
