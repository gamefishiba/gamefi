//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
//Shiba data structure
struct DogsMetaData {
    uint8 ethnicity;
    uint8 profession;
    uint8 head; //2 
    uint8 mouse; 
    uint8 eyes; 
    uint8 body; 
    uint8 collar; 
    uint8 tail; 
    uint8 ear; 
    uint8 cap; 
    uint8 clothing; 
    uint8 ornaments; //11 gen
    uint64 attack;
    uint64 defense;
    uint64 speed;
    uint32 father;
    uint32 mother;
    uint64 birth;
}

//Growth attributes
struct GrowthValue { uint8 attack; uint8 defense; uint8 speed; }

//Monitor lock
struct MonitorInfos {
    uint64 lefttime;
    bytes24 message;
}

//Fertility allocation
struct SireAttrConfig {
    uint8 ethnicity_option;
    //Occupational gene range
    uint8 profession_option;
    //Head gene range
    uint8 head_option;
    //Mouth gene range
    uint8 mouse_option;
    //Eye gene range
    uint8 eyes_option;
    //Body gene range
    uint8 body_option;
    //Collar gene range
    uint8 collar_option;
    //Tail gene range
    uint8 tail_option;
    //Clothing gene range
    uint8 clothing_option;
    //Ear gene range
    uint8 ear_option;
    //Hat gene range
    uint8 cap_option;
    //Accessories gene range
    uint8 ornaments_option;
}

interface IGameFiShibaSire {
    function sire( DogsMetaData memory _father, DogsMetaData memory _mother ) external returns (DogsMetaData memory);
    function sireFee(uint time) external view returns (uint256);
    function growingInfos() external view  returns(GrowthValue[] memory);
    function knighthood(uint tokenId) external view returns(uint);
    function identity() external view returns (uint[] memory);
    function genRarity(uint gen) external view returns(bool);
}

interface IGameFiShibaMonitor{
    function isMonitoring(uint256 tokenId) external view returns (bool) ;
    function monitorInfos(uint256 tokenId) external view returns (MonitorInfos memory);
}

interface IGameFiShiba is IERC721,IERC721Receiver,IERC721Enumerable,IGameFiShibaMonitor{
    function mint(address to, DogsMetaData memory meta) external returns (uint256 _tokenId);
    function sire(uint father,uint mother) external returns(uint _tokenId);
    function metaData(uint tokenId) external view returns (DogsMetaData memory);
    function exists(uint tokenId) external view returns (bool);
    function unlockShiba(uint tokenId) external returns(bool);
}


