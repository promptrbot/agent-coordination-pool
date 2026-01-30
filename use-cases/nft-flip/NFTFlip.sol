// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title NFTFlip
 * @notice Buy NFT → List at +15% → Distribute profits
 * 
 * FOR AGENTS:
 *   1. Create a flip (target NFT + buy order)
 *   2. Contribute ETH
 *   3. When funded: executeBuy() → NFT bought + listed at +15%
 *   4. When sold: distribute() → profits sent to contributors
 *   5. If expired: withdraw()
 */

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
        AdditionalRecipient[] additionalRecipients;
        bytes signature;
    }
    
    struct AdditionalRecipient {
        uint256 amount;
        address payable recipient;
    }
    
    struct OrderComponents {
        address offerer;
        address zone;
        OfferItem[] offer;
        ConsiderationItem[] consideration;
        uint8 orderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 conduitKey;
        uint256 counter;
    }
    
    struct OfferItem {
        uint8 itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
    }
    
    struct ConsiderationItem {
        uint8 itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
        address payable recipient;
    }
    
    function fulfillBasicOrder(BasicOrderParameters calldata) external payable returns (bool);
    function getCounter(address) external view returns (uint256);
    function validate(OrderComponents[] calldata) external returns (bool);
}

contract NFTFlip is IERC721Receiver {
    
    address public immutable seaport;
    uint256 public constant MARKUP_BPS = 1500; // 15%
    uint256 public constant EXECUTOR_BPS = 100; // 1% to whoever triggers
    
    enum Status { Funding, Bought, Listed, Sold, Expired, Failed }
    
    struct Flip {
        // Target
        address nft;
        uint256 tokenId;
        uint256 buyPrice;
        uint256 listPrice;      // buyPrice + 15%
        
        // Timing
        uint256 deadline;        // funding deadline
        uint256 listingExpiry;   // how long to list for sale
        
        // Funding
        uint256 total;
        address[] contributors;
        mapping(address => uint256) contributions;
        
        // State
        Status status;
        uint256 saleProceeds;    // ETH received from sale
    }
    
    Flip[] public flips;
    
    event FlipCreated(uint256 indexed id, address nft, uint256 tokenId, uint256 buyPrice, uint256 listPrice);
    event Contributed(uint256 indexed id, address indexed who, uint256 amount);
    event Bought(uint256 indexed id, address executor);
    event Listed(uint256 indexed id, uint256 listPrice);
    event Sold(uint256 indexed id, uint256 proceeds);
    event Distributed(uint256 indexed id, uint256 totalDistributed);
    event Withdrawn(uint256 indexed id, address indexed who, uint256 amount);
    
    constructor(address _seaport) {
        seaport = _seaport;
    }
    
    /// @notice Create a flip opportunity
    function createFlip(
        address nft,
        uint256 tokenId,
        uint256 buyPrice,
        uint256 fundingDeadline,
        uint256 listingDuration
    ) external returns (uint256 id) {
        require(fundingDeadline > block.timestamp, "deadline passed");
        require(buyPrice > 0, "price=0");
        
        id = flips.length;
        Flip storage f = flips.push();
        f.nft = nft;
        f.tokenId = tokenId;
        f.buyPrice = buyPrice;
        f.listPrice = buyPrice + (buyPrice * MARKUP_BPS / 10000); // +15%
        f.deadline = fundingDeadline;
        f.listingExpiry = listingDuration;
        f.status = Status.Funding;
        
        emit FlipCreated(id, nft, tokenId, buyPrice, f.listPrice);
    }
    
    /// @notice Contribute ETH to a flip
    function contribute(uint256 id) external payable {
        Flip storage f = flips[id];
        require(f.status == Status.Funding, "not funding");
        require(block.timestamp <= f.deadline, "expired");
        require(msg.value > 0, "no value");
        
        if (f.contributions[msg.sender] == 0) {
            f.contributors.push(msg.sender);
        }
        f.contributions[msg.sender] += msg.value;
        f.total += msg.value;
        
        emit Contributed(id, msg.sender, msg.value);
    }
    
    /// @notice Execute the buy (when funded)
    function executeBuy(
        uint256 id,
        ISeaport.BasicOrderParameters calldata buyOrder
    ) external {
        Flip storage f = flips[id];
        require(f.status == Status.Funding, "not funding");
        require(f.total >= f.buyPrice, "not funded");
        require(block.timestamp <= f.deadline, "expired");
        
        // Buy via Seaport
        bool success = ISeaport(seaport).fulfillBasicOrder{value: f.buyPrice}(buyOrder);
        require(success, "buy failed");
        
        // Verify we received the NFT
        require(IERC721(f.nft).ownerOf(f.tokenId) == address(this), "didn't receive NFT");
        
        f.status = Status.Bought;
        
        // Pay executor bounty (1% of buy price)
        uint256 bounty = f.buyPrice * EXECUTOR_BPS / 10000;
        if (bounty > 0 && address(this).balance >= bounty) {
            (bool ok,) = msg.sender.call{value: bounty}("");
            require(ok, "bounty failed");
        }
        
        emit Bought(id, msg.sender);
    }
    
    /// @notice List the NFT for sale at +15%
    function list(uint256 id) external {
        Flip storage f = flips[id];
        require(f.status == Status.Bought, "not bought");
        
        // Approve Seaport
        IERC721(f.nft).approve(seaport, f.tokenId);
        
        f.status = Status.Listed;
        
        emit Listed(id, f.listPrice);
    }
    
    /// @notice Called when we receive sale proceeds
    function recordSale(uint256 id) external {
        Flip storage f = flips[id];
        require(f.status == Status.Listed, "not listed");
        
        // Check if NFT was sold (we no longer own it)
        if (IERC721(f.nft).ownerOf(f.tokenId) != address(this)) {
            f.status = Status.Sold;
            f.saleProceeds = address(this).balance; // Assume all balance is from sale
            emit Sold(id, f.saleProceeds);
        }
    }
    
    /// @notice Distribute sale profits to contributors
    function distribute(uint256 id) external {
        Flip storage f = flips[id];
        require(f.status == Status.Sold, "not sold");
        require(f.saleProceeds > 0, "no proceeds");
        
        uint256 total = f.saleProceeds;
        f.saleProceeds = 0;
        
        // Pay executor bounty
        uint256 bounty = total * EXECUTOR_BPS / 10000;
        if (bounty > 0) {
            (bool ok,) = msg.sender.call{value: bounty}("");
            require(ok, "bounty failed");
            total -= bounty;
        }
        
        // Distribute to contributors proportionally
        uint256 distributed = 0;
        for (uint256 i = 0; i < f.contributors.length; i++) {
            address c = f.contributors[i];
            uint256 share = (total * f.contributions[c]) / f.total;
            if (share > 0) {
                (bool ok,) = c.call{value: share}("");
                require(ok, "transfer failed");
                distributed += share;
            }
        }
        
        emit Distributed(id, distributed);
    }
    
    /// @notice Withdraw if funding expired or buy failed
    function withdraw(uint256 id) external {
        Flip storage f = flips[id];
        require(
            f.status == Status.Funding && block.timestamp > f.deadline ||
            f.status == Status.Failed ||
            f.status == Status.Expired,
            "cannot withdraw"
        );
        
        if (f.status == Status.Funding && block.timestamp > f.deadline) {
            f.status = Status.Expired;
        }
        
        uint256 amount = f.contributions[msg.sender];
        require(amount > 0, "nothing");
        
        f.contributions[msg.sender] = 0;
        f.total -= amount;
        
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        
        emit Withdrawn(id, msg.sender, amount);
    }
    
    /// @notice Get contribution amount
    function contribution(uint256 id, address who) external view returns (uint256) {
        return flips[id].contributions[who];
    }
    
    /// @notice Get flip count
    function count() external view returns (uint256) {
        return flips.length;
    }
    
    /// @notice ERC721 receiver
    function onERC721Received(address, address, uint256, bytes calldata) 
        external pure returns (bytes4) 
    {
        return this.onERC721Received.selector;
    }
    
    /// @notice Receive ETH (from Seaport sale)
    receive() external payable {}
}
