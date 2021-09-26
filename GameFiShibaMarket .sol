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

contract GameFiShibaMarket is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    /**
     * Event emitted when a trade is executed.
     */
    event Trade(
        bytes32 indexed hash,
        address indexed maker,
        address taker,
        uint256 makerWei,
        uint256[] makerIds,
        uint256 takerWei,
        uint256[] takerIds
    );

    /**
     * Event emitted when a trade offer is cancelled.
     */
    event OfferCancelled(bytes32 hash);

    /**
     * Event emitted when the public sale begins.
     */
    event SaleBegins();

    /**
     * Event emitted when the UnLock state change .
     */
    event UnLockChange(address,bool);

    struct Offer {
        address maker;
        address taker;
        uint256 makerWei;
        uint256[] makerIds;
        uint256 takerWei;
        uint256[] takerIds;
        uint256 expiry;
        uint256 salt;
    }

    bool public marketPaused;

    bool public salesPaused;
    
    bool public lockPaused;

    IGameFiShiba public immutable _gamefishiba;

    IERC20 public immutable WETH;
    IERC20 public immutable _gamefi;
    address public immutable _receptor;

    mapping(bytes32 => bool) public cancelledOffers;

    uint256 public marketFee = 30;
    //Accumulated fee
    uint256 public totalTradeFee;
    //Accumulated fee
    uint public totalUnlockFee;
    
    //Accumulated sales
    uint256 public totalSales;
    //Gene pool
    mapping(uint256 => mapping(uint256 => DogsMetaData)) mintPool;
    //Gene pool size
    mapping(uint256 => uint256) mintPoolSize;
    //selling price
    uint256[] private _grantSalesPrices;
    //unlock fee
    uint256 public unlockFee;

    uint256 nonce;

    //Empty meta data
    bytes32 private _emptyMetaData;
    //Event of sales status change
    event MintStateChange(address, bool);
    //Event of market transaction status change
    event MarketStateChange(address, bool);

    modifier whenMintEable() {
        require(!salesPaused, "mint close");
        _;
    }

    modifier whenNotPaused() {
        require(!marketPaused, "market paused");
        _;
    }

    modifier whenUnlockEable() {
        require(!lockPaused,'unlock close');
        _;
    }

    //0xc778417E063141139Fce010982780140Aa0cD5Ab
    constructor(
        address cryptoshiba_,
        address weth_,
        address mintpool_,
        address gamefi_
    ) {
        _gamefishiba = IGameFiShiba(cryptoshiba_);
        WETH = IERC20(weth_);
        _receptor = mintpool_;
        _gamefi = IERC20(gamefi_);
        _emptyMetaData = hashMetaData(DogsMetaData( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ));
        salesPaused = true;
    }

    function hashMetaData(DogsMetaData memory metaData)
        internal pure
        returns (bytes32)
    {
        return keccak256(GameFiShibaLib.encodePack(metaData)) ;
    }

    function hashOffer(Offer memory offer) private pure returns (bytes32) {
        return keccak256( abi.encode( offer.maker, offer.taker, offer.makerWei, keccak256(abi.encodePacked(offer.makerIds)), offer.takerWei, keccak256(abi.encodePacked(offer.takerIds)), offer.expiry, offer.salt ) );
    }

    function hashToSign( address maker, address taker, uint256 makerWei, uint256[] memory makerIds, uint256 takerWei, uint256[] memory takerIds, uint256 expiry, uint256 salt ) public pure returns (bytes32) {
        Offer memory offer = Offer( maker, taker, makerWei, makerIds, takerWei, takerIds, expiry, salt );
        return hashOffer(offer);
    }

    function hashToVerify(Offer memory offer) private pure returns (bytes32) {
        return keccak256( abi.encodePacked( "\x19Ethereum Signed Message:\n32", hashOffer(offer) ) );
    }

    function verify( address signer, bytes32 hash, bytes memory signature ) internal pure returns (bool) {
        require(signer != address(0));
        require(signature.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28);

        return signer == ecrecover(hash, v, r, s);
    }

    function tradeValid( address maker, address taker, uint256 makerWei, uint256[] memory makerIds, uint256 takerWei, uint256[] memory takerIds, uint256 expiry, uint256 salt, bytes memory signature ) public view returns (bool) {
        Offer memory offer = Offer( maker, taker, makerWei, makerIds, takerWei, takerIds, expiry, salt );
        // Check for cancellation
        bytes32 hash = hashOffer(offer);
        require(cancelledOffers[hash] == false, "Trade offer was cancelled.");
        // Verify signature
        bytes32 verifyHash = hashToVerify(offer);
        require( verify(offer.maker, verifyHash, signature), "Signature not valid." );
        // Check for expiry
        require(block.timestamp < offer.expiry, "Trade offer expired.");
        // Only one side should ever have to pay, not both
        require( makerWei == 0 || takerWei == 0, "Only one side of trade must pay." );
        // At least one side should offer tokens
        require( makerIds.length > 0 || takerIds.length > 0, "One side must offer tokens." );
        // Make sure the maker has funded the trade
        require( WETH.balanceOf(offer.maker) >= offer.makerWei, "Maker does not have sufficient balance." );
        // Ensure the maker owns the maker tokens
        for (uint256 i = 0; i < offer.makerIds.length; i++) {
            require( _gamefishiba.ownerOf(offer.makerIds[i]) == offer.maker, "At least one maker token doesn't belong to maker." );
            require( !_gamefishiba.isMonitoring(offer.makerIds[i]), "At least one maker token doesn't free" );
        }
        // If the taker can be anybody, then there can be no taker tokens
        if (offer.taker == address(0)) {
            // If taker not specified, then can't specify IDs
            require( offer.takerIds.length == 0, "If trade is offered to anybody, cannot specify tokens from taker." );
        } else {
            // Ensure the taker owns the taker tokens
            for (uint256 i = 0; i < offer.takerIds.length; i++) {
                require( _gamefishiba.ownerOf(offer.takerIds[i]) == offer.taker, "At least one taker token doesn't belong to taker." );
                require( !_gamefishiba.isMonitoring(offer.takerIds[i]), "At least one maker token doesn't free" );
            }
        }
        return true;
    }

    function cancelOffer( address maker, address taker, uint256 makerWei, uint256[] memory makerIds, uint256 takerWei, uint256[] memory takerIds, uint256 expiry, uint256 salt ) external {
        require(maker == msg.sender, "Only the maker can cancel this offer.");
        Offer memory offer = Offer( maker, taker, makerWei, makerIds, takerWei, takerIds, expiry, salt );
        bytes32 hash = hashOffer(offer);
        cancelledOffers[hash] = true;
        emit OfferCancelled(hash);
    }

    function gratuity( address from, address to, uint256 amount ) internal {
        if (amount == 0) {
            return;
        }
        uint256 fee = amount.mul(marketFee).div(1000);
        WETH.transferFrom(from, to, amount.sub(fee));
        if (fee > 0) {
            totalTradeFee = totalTradeFee.add(fee);
            WETH.transferFrom(from, _receptor, fee);
        }
    }

    function acceptTrade( address maker, address taker, uint256 makerWei, uint256[] memory makerIds, uint256 takerWei, uint256[] memory takerIds, uint256 expiry, uint256 salt, bytes memory signature ) external nonReentrant whenNotPaused {
        require(!marketPaused, "Market is paused.");
        require(msg.sender != maker, "Can't accept ones own trade.");
        Offer memory offer = Offer( maker, taker, makerWei, makerIds, takerWei, takerIds, expiry, salt );

        require( offer.taker == address(0) || offer.taker == msg.sender, "Not the recipient of this offer." );
        require( tradeValid( maker, taker, makerWei, makerIds, takerWei, takerIds, expiry, salt, signature ), "Trade not valid." );
        require( WETH.balanceOf(msg.sender) >= offer.takerWei, "Insufficient funds to execute trade." );

        // Transfer ETH
        gratuity(maker, msg.sender, offer.makerWei);
        gratuity(msg.sender, maker, offer.takerWei);

        // Transfer maker ids to taker (msg.sender)
        for (uint256 i = 0; i < makerIds.length; i++) {
            _gamefishiba.safeTransferFrom(maker, msg.sender, makerIds[i]);
        }
        // Transfer taker ids to maker
        for (uint256 i = 0; i < takerIds.length; i++) {
            _gamefishiba.safeTransferFrom(msg.sender, maker, takerIds[i]);
        }
        // Prevent a replay attack on this offer   
        bytes32 hash = hashOffer(offer);
        cancelledOffers[hash] = true;
        emit Trade( hash, offer.maker, msg.sender, offer.makerWei, offer.makerIds, offer.takerWei, offer.takerIds );
    }

    //update transaction fee
    function setMarketFee(uint256 marketFee_) public onlyOwner {
        marketFee = marketFee_;
    }

    //Get the sale price
    function grantSalesPrices(uint256 grant) public view returns (uint256) {
        return _grantSalesPrices[grant];
    }

    //Update sale price
    function setGrantSalesPrices(uint256 grant, uint256 price)
        public
        onlyOwner
    {
        if (grant >= _grantSalesPrices.length) _grantSalesPrices.push(price);
        else _grantSalesPrices[grant] = price;
    }

    //Get an nft
    function mint(address to, uint256 grant) public nonReentrant whenMintEable returns (uint256 _tokenId) {
        uint256 len = mintPoolSize[grant];
        require(len > 0, "Sold out");
        WETH.transferFrom(msg.sender, _receptor, grantSalesPrices(grant));
        nonce = nonce.add(1);
        uint256 random = GameFiShibaLib._randomSpeed(nonce) % len;
        _tokenId = _gamefishiba.mint(to, mintPool[grant][random]);
        if (random != len - 1) {
            mintPool[grant][random] = mintPool[grant][len - 1];
        }
        delete mintPool[grant][len - 1];
        mintPoolSize[grant]--;
    }

    //Put genetic data into the pool
    function pushMetaData(uint256 grant, DogsMetaData[] memory meta) public nonReentrant onlyOwner {
        for (uint256 i = 0; i < meta.length; i++) {
            require(hashMetaData(meta[i]) != _emptyMetaData);
            mintPool[grant][mintPoolSize[grant]++] = meta[i];
        }
    }

    //peek the elements in the pool
    function peek(uint256 grant, uint256 index) public view onlyOwner returns (DogsMetaData memory _meta) {
        return mintPool[grant][index];
    }

    //Get the pool size
    function sizeOf(uint256 grant) public view returns (uint256 _size) {
        return mintPoolSize[grant];
    }

    //Go back to the corresponding genetic data
    function revertMetaData( uint256 grant, uint256 index, DogsMetaData memory meta ) public nonReentrant onlyOwner {
        require(mintPoolSize[grant] > index, "index out of bound");
        require(
            keccak256(abi.encode(meta)) !=
                keccak256(abi.encode(mintPool[grant][index])),
            "revert fail"
        );
        uint256 len = mintPoolSize[grant];
        if (index != len - 1) {
            mintPool[grant][index] = mintPool[grant][len - 1];
        }
        mintPoolSize[grant]--;
    }

    function selfUnlocking(uint tokenId) external whenUnlockEable  returns(bool) {
        require(_gamefishiba.ownerOf(tokenId) == msg.sender,'Not owner');
        _gamefi.transferFrom(msg.sender, address(_gamefishiba), unlockFee);
        totalUnlockFee = totalUnlockFee.add(unlockFee);
        return _gamefishiba.unlockShiba(tokenId);
    }

    function setUnlockFee(uint fee) public onlyOwner{
        unlockFee = fee;
    }

    //pause mint , Default off
    function pauseMint() public onlyOwner {
        salesPaused = true;
        emit MintStateChange(msg.sender, true);
    }

    //unpause mint
    function unpauseMint() public onlyOwner {
        salesPaused = false;
        emit MintStateChange(msg.sender, false);
    }

    //Close free trade
    function pause() public onlyOwner {
        marketPaused = true;
        emit MarketStateChange(msg.sender, true);
    }

    //Open free trade
    function unpause() public onlyOwner {
        marketPaused = false;
        emit MarketStateChange(msg.sender, false);
    }

    //Close Unlock
    function pauseUnLock() public onlyOwner{
        lockPaused = true;
        emit UnLockChange(msg.sender,true);
    }
    //Open Unlock
    function unPauseUnLock() public onlyOwner{
        lockPaused = false;
        emit UnLockChange(msg.sender,true);
    }
}
