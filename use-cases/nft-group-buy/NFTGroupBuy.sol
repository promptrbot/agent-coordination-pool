// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTGroupBuy
 * @notice Create ACP pools for NFT purchases. That's it.
 * 
 * FOR AGENTS:
 *   1. createBuy(nft, tokenId, price, deadline, seaportOrder)
 *   2. Share the pool ID with other agents
 *   3. Everyone contributes via ACP.contribute(poolId)
 *   4. When funded, anyone calls ACP.execute(poolId)
 */

interface IACP {
    function create(
        address target,
        bytes calldata callData,
        uint256 value,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256);
}

interface ISeaport {
    struct BasicOrderParameters {
        address considerationToken;
        uint256 considerationIdentifier;
        uint256 considerationAmount;
        address payable offerer;
        address zone;
        address offerToken;
        uint256 offerIdentifier;
        uint256 offerAmount;
        uint8 basicOrderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 offererConduitKey;
        bytes32 fulfillerConduitKey;
        uint256 totalOriginalAdditionalRecipients;
        address payable[] additionalRecipients;
        bytes signature;
    }
    
    function fulfillBasicOrder(BasicOrderParameters calldata) external payable returns (bool);
}

contract NFTGroupBuy {
    
    IACP public immutable acp;
    address public immutable seaport;
    
    // Track NFT buys (poolId => NFT info)
    struct Buy {
        address nft;
        uint256 tokenId;
        uint256 price;
    }
    mapping(uint256 => Buy) public buys;
    uint256[] public buyIds;
    
    event BuyCreated(uint256 indexed poolId, address nft, uint256 tokenId, uint256 price);
    
    constructor(address _acp, address _seaport) {
        acp = IACP(_acp);
        seaport = _seaport;
    }
    
    /// @notice Create a group buy for an NFT
    function createBuy(
        address nft,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        ISeaport.BasicOrderParameters calldata order
    ) external returns (uint256 poolId) {
        
        // Encode Seaport call
        bytes memory callData = abi.encodeCall(ISeaport.fulfillBasicOrder, (order));
        
        // Create ACP pool
        poolId = acp.create(seaport, callData, price, price, deadline);
        
        // Track it
        buys[poolId] = Buy(nft, tokenId, price);
        buyIds.push(poolId);
        
        emit BuyCreated(poolId, nft, tokenId, price);
    }
    
    /// @notice Get all buy pool IDs
    function getAllBuys() external view returns (uint256[] memory) {
        return buyIds;
    }
}
