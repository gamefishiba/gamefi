//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "./GameFiShibaCommon.sol";
import "./GameFiShibaLib.sol";

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

/// @title GameFi Shiba
/// @author GameFi Shiba team

interface IGameFiShibaChildMarket{
    function grantSalesPrices(address erc20,uint256 grant) external view returns (uint256) ;
    function setGrantSalesPrices(uint256 grant,address erc20, uint256 amount_) external;
    function mint(address to,address erc20, uint256 grant) external    returns (uint256 _tokenId) ;
    function pushMetaData(address erc20,uint256 grant, DogsMetaData[] memory meta) external;
    function peek(address erc20,uint256 grant, uint256 index) external view  returns (DogsMetaData memory _meta);
    function sizeOf(address erc20,uint256 grant) external view returns (uint256 _size);
    function revertMetaData(address erc20, uint256 grant, uint256 index, DogsMetaData memory meta ) external;
    function pause() external ;
    //unpause mint
    function unpause() external ;
}

contract GameFiShibaChildMarket is ReentrancyGuard,IGameFiShibaChildMarket, Ownable ,Pausable {
    using SafeMath for uint256;

    bool public marketPaused;

    IGameFiShiba public immutable _gamefishiba;

    address public immutable _receptor;

    //Gene pool
    mapping(address => mapping(uint256 => mapping(uint256 => DogsMetaData))) mintPool;
    //Gene pool size
    mapping(address => mapping(uint256 => uint256)) mintPoolSize;
    //selling price
    mapping(address => uint256[]) private _grantSalesPrices;
    //unlock fee
    uint256 public unlockFee;

    uint256 nonce;

    //Empty meta data
    bytes32 private _emptyMetaData;
    //Event of sales status change
    event MintStateChange(address, bool);
    //Event of market transaction status change
    event MarketStateChange(address, bool);


    //0xc778417E063141139Fce010982780140Aa0cD5Ab
    constructor(
        address cryptoshiba_,
        address mintpool_
    ) {
        _gamefishiba = IGameFiShiba(cryptoshiba_);
        _receptor = mintpool_;
        _emptyMetaData = hashMetaData(DogsMetaData( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ));
    }


    function hashMetaData(DogsMetaData memory metaData)
        internal pure
        returns (bytes32)
    {
        return keccak256(GameFiShibaLib.encodePack(metaData)) ;
    }


    //Get the sale price
    function grantSalesPrices(address erc20,uint256 grant) public override view returns (uint256) {
        return _grantSalesPrices[erc20][grant];
    }

    //Update sale price
    function setGrantSalesPrices(uint256 grant,address erc20, uint256 amount_)
        public override
        onlyOwner
    {
        if (grant >= _grantSalesPrices[erc20].length) _grantSalesPrices[erc20].push(amount_);
        else _grantSalesPrices[erc20][grant] = amount_;
    }

    //Get an nft
    function mint(address to,address erc20, uint256 grant) public nonReentrant  whenNotPaused  override returns (uint256 _tokenId) {
        uint256 len = sizeOf(erc20,grant);
        require(len > 0, "Sold out");
        IERC20(erc20).transferFrom(msg.sender, _receptor, grantSalesPrices(erc20,grant));
        nonce = nonce.add(1);
        uint256 random = GameFiShibaLib._randomSpeed(nonce) % len;
        _tokenId = _gamefishiba.mint(to, mintPool[erc20][grant][random]);
        if (random != len - 1) {
            mintPool[erc20][grant][random] = mintPool[erc20][grant][len - 1];
        }
        delete mintPool[erc20][grant][len - 1];
        mintPoolSize[erc20][grant] = mintPoolSize[erc20][grant].sub(1);
    }

    //Put genetic data into the pool
    function pushMetaData(address erc20,uint256 grant, DogsMetaData[] memory meta) public override nonReentrant onlyOwner {
        for (uint256 i = 0; i < meta.length; i++) {
            require(hashMetaData(meta[i]) != _emptyMetaData);
            mintPool[erc20][grant][mintPoolSize[erc20][grant]++] = meta[i];
        }
    }

    //peek the elements in the pool
    function peek(address erc20,uint256 grant, uint256 index) public override view onlyOwner returns (DogsMetaData memory _meta) {
        return mintPool[erc20][grant][index];
    }

    //Get the pool size
    function sizeOf(address erc20,uint256 grant) public override view returns (uint256 _size) {
        return mintPoolSize[erc20][grant];
    }

    //Go back to the corresponding genetic data
    function revertMetaData(address erc20, uint256 grant, uint256 index, DogsMetaData memory meta ) public override nonReentrant onlyOwner {
        require(mintPoolSize[erc20][grant] > index, "index out of bound");
        require(
            keccak256(abi.encode(meta)) !=
                keccak256(abi.encode(mintPool[erc20][grant][index])),
            "revert fail"
        );
        uint256 len = mintPoolSize[erc20][grant];
        if (index != len - 1) {
            mintPool[erc20][grant][index] = mintPool[erc20][grant][len - 1];
        }
        mintPoolSize[erc20][grant]--;
    }


    //pause mint , Default off
    function pause() public override onlyOwner {
        _pause();
    }

    //unpause mint
    function unpause() public override onlyOwner {
        _unpause();
    }

}
