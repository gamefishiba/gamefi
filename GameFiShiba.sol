//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./GameFiShibaCommon.sol";

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
contract GameFiShiba is
    IGameFiShiba,
    ERC721Holder,
    ERC721Enumerable,
    AccessControl,
    Pausable
{
    using SafeMath for uint;
    //Genetic rules
    IGameFiShibaSire public _gamefishibasire;

    //Metadata storage area
    mapping(uint => DogsMetaData) metaDataMap;
    mapping(uint => MonitorInfos) monitoringArea;
    //Gamefi token
    IERC20 public immutable gameFiToken;

    //Accesss roles
    bytes32 public constant CEO = keccak256("CEO");
    bytes32 public constant CTO = keccak256("CTO");
    bytes32 public constant COO = keccak256("COO");

    string public baseURI;
    //Number of generated dogs, including births and sales
    uint internal numTokens = 0;
    //The maximum number of dogs mint out in the market
    uint public constant BORN_LIMIT = 36000;
    uint public numBorn = 0;

    bytes24 public constant BIRTH_LOCK = "BIRTH_LOCK";
    //Birth lock
    uint64 public constant SIRE_LOCK_TIME = 86400;
    //Maximum number of births
    uint public constant MAX_BEAR_TIME = 7;
    //Relational mapping of all children
    mapping(uint => uint[]) internal _posterity;

    //Random number increment iterator
    uint internal nonce = 0;

    uint private _status;
    //The number of tokens currently consumed
    uint public bonusToken = 0;
    //Whether to allow free trading
    bool public tradeEnable;
    //trade state change
    event TradeEnableChange(address);

    event ShibaUnLock(uint tokenId,address sender);
    
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != 1, "ReentrancyGuard: reentrant call");
        // Any calls to nonReentrant after this point will fail
        _status = 1;
        _;
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = 0;
    }

    constructor(
        string memory name,
        string memory symbol,
        address admin,
        address _priceToken
    ) ERC721(name, symbol) {
        require(admin != address(0), "INVALID CEO ADDRESS");
        _setupRole(CEO, admin);
        _setRoleAdmin(CEO, CEO);
        _setRoleAdmin(CTO, CEO);
        _setRoleAdmin(COO, CEO);

        gameFiToken = IERC20(_priceToken);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    ) internal override whenNotPaused {
        require(!isMonitoring(tokenId), "Currently locked");
        //tradable ? except for the market contract
        if (!tradeEnable && from != address(0)) {
            require(hasRole(COO, msg.sender), "Trans Fail");
        }
        super._beforeTokenTransfer(from, to, tokenId);
    }


    //Allow market contracts to transfer nft
    function isApprovedForAll(address owner, address operator) public view override(ERC721,IERC721) returns (bool) {
        if(hasRole(COO,operator)){
            return true;
        }
        return super.isApprovedForAll(owner,operator);
    }

    function metaData(uint tokenId)
        public override
        view
        returns (DogsMetaData memory)
    {
        require(_exists(tokenId), "Invalid TokenId");
        //If still in birth lock,not allowed to return data
        if (monitoringArea[tokenId].message == BIRTH_LOCK) require( monitoringArea[tokenId].lefttime <= block.timestamp, "BIRTH_LOCK" );
        return metaDataMap[tokenId];
    }

    function setBaseUri(string memory baseURIStr) public {
        require(hasRole(CEO,msg.sender) || hasRole(CTO,msg.sender));
        baseURI = baseURIStr;
    }

    //ovveride _baseUri in Erc721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev See {IERC721Enumerable-supportsInterface,IERC721-supportsInterface,IAccessControl-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, AccessControl,IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function mint(address to, DogsMetaData memory meta)
        public override
        whenNotPaused onlyRole(COO)
        returns (uint _tokenId)
    {
        require(numBorn <= BORN_LIMIT, "MINT LIMIT");
        _tokenId = ++numTokens;
        numBorn++;
        _mint(to, _tokenId);
        meta.birth = uint64(block.timestamp);
        metaDataMap[_tokenId] = meta;
    }

    ///
    /// lock
    ///

    function isMonitoring(uint tokenId) public view override returns (bool) {
        return monitoringArea[tokenId].lefttime != 0 && monitoringArea[tokenId].lefttime >= block.timestamp;
    }

    function monitorInfos(uint tokenId)
        public
        view
        override
        returns (MonitorInfos memory)
    {
        return monitoringArea[tokenId];
    }

    function _monitor(uint tokenId, MonitorInfos memory monitorInfo)
        internal
    {
        require(!isMonitoring(tokenId), "Currently locked");
        require(
            monitorInfo.lefttime > block.timestamp,
            "Invalid Lock timestamp"
        );
        monitoringArea[tokenId] = monitorInfo;
    }

    function unlockShiba(uint tokenId) public override onlyRole(COO) returns(bool){
        require(isMonitoring(tokenId),'No lock');
        delete monitoringArea[tokenId];
        emit ShibaUnLock(tokenId,msg.sender);
        return true;
    }

    function posterity(uint tokenId) public view returns (uint[] memory) {
        return _posterity[tokenId];
    }

    function kinshipFilter(uint father, uint mother) public view returns(bool){
        require(father != mother,'The id of both parents cannot be the same');
        (father,mother) = father < mother? (father,mother):(mother,father);
        if ( metaDataMap[father].father != 0 && metaDataMap[mother].father != 0 ) { 
            require( metaDataMap[father].father != metaDataMap[mother].father && metaDataMap[father].mother != metaDataMap[father].mother, "Close relatives" );
            require( metaDataMap[father].father != metaDataMap[mother].mother && metaDataMap[father].mother != metaDataMap[father].father, "Close relatives" ); 
        }
        for (uint i = 0; i < _posterity[father].length; i++) {
            require(_posterity[father][i] != mother, "Close relatives");
            for ( uint j = 0; j < _posterity[_posterity[father][i]].length; j++ ) {
                require( _posterity[_posterity[father][i]][j] != mother, "Close relatives" );
            }
        }
        return true;
    }

    function setGameFiShibaSire(address _sireAddress)
        public
        nonReentrant
    {
        require(hasRole(CEO,msg.sender) || hasRole(CTO,msg.sender));
        require(_sireAddress != address(0), "Invalid sire address");
        _gamefishibasire = IGameFiShibaSire(_sireAddress);
    }

    function calculateSirefee(uint father,uint mother) public view returns(uint _fee){
        _fee = _gamefishibasire.sireFee(_posterity[father].length).add(_gamefishibasire.sireFee(_posterity[mother].length));
    }

    function sire(uint father, uint mother)
        public override
        nonReentrant
        whenNotPaused
        returns (uint)
    {
        require(_exists(father) && _exists(mother) && father != mother,"Invalid TokenIds");
        require(!isMonitoring(father) && !isMonitoring(mother),"Invalid TokenIds");
        require(ownerOf(father) == msg.sender && ownerOf(mother) == msg.sender,"No right to operate");
        require(_posterity[father].length <= MAX_BEAR_TIME &&_posterity[mother].length <= MAX_BEAR_TIME,"Too many births");
        kinshipFilter(father, mother);

        uint fee = calculateSirefee(father,mother);
        gameFiToken.transferFrom(msg.sender, address(this), fee);
        bonusToken = bonusToken.add(fee);
    
        uint tokenId = ++numTokens;
        _mint(msg.sender, tokenId);

        uint64 locktime = uint64(block.timestamp.add(SIRE_LOCK_TIME));
        // _monitor(father, MonitorInfos(locktime, SIRE_LOCK));
        // _monitor(mother, MonitorInfos(locktime, SIRE_LOCK));

        DogsMetaData memory childDog = _gamefishibasire.sire(metaDataMap[father],metaDataMap[mother]);
        childDog.father = uint32(father);
        childDog.mother = uint32(mother);
        childDog.birth = uint64(block.timestamp);
        metaDataMap[tokenId] = childDog;

        _monitor(tokenId, MonitorInfos(locktime, BIRTH_LOCK));
        _posterity[father].push(tokenId);
        _posterity[mother].push(tokenId);
        return tokenId;
    }

    function exists(uint tokenId) public override view returns(bool){
        return _exists(tokenId);
    }

    //
    //pausable
    //
    function pause() public {
        require(hasRole(CEO,msg.sender) || hasRole(CTO,msg.sender));
        _pause();
    }

    function unpause() public  {
        require(hasRole(CEO,msg.sender) || hasRole(CTO,msg.sender));
        _unpause();
    }

    function setTradeEnable(bool _enable) public {
        require(hasRole(CEO,msg.sender) || hasRole(CTO,msg.sender));
        tradeEnable = _enable;
        emit TradeEnableChange(msg.sender);
    }

    function withdraw(address token,address to,uint number) public onlyRole(CEO){
        require(address(0)!=to,'Invalid address');
        IERC20(token).transferFrom(address(this), to, number);
    }
}
