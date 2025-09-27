// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * Very small RentalManager:
 * - Owners list NFTs (owner must own token)
 * - Owner must approve this contract (approve(tokenId, mgr) or setApprovalForAll)
 * - Renters pay price => contract forwards funds to owner and sets user on the NFT (via ERC-4907 setUser)
 */
interface IERC4907 {
    function setUser(uint256 tokenId, address user, uint64 expires) external;
    function setListed(uint256 tokenId, bool listed) external;
    
}

contract RentalManager is ReentrancyGuard {
    struct Listing {
        address owner;
        address nft;
        uint256 tokenId;
        uint256 numberOfRents;
        uint256 price;      // in wei
        bool active;
    }

    // nftAddress => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => uint256)) public rentUsed; // how many times rented
    Listing[] public allListings; // optional, for easy enumeration

    event Listed(address indexed nft, uint256 indexed tokenId, address owner, uint256 price);
    event Cancelled(address indexed nft, uint256 indexed tokenId);
    event Rented(address indexed nft, uint256 indexed tokenId, address owner, address renter, uint256 price, uint64 expires);

    function listItem(address nft, uint256 tokenId, uint256 price, uint256 numberOfRents) external {
        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "Not token owner");
          bool approvedForToken = (IERC721(nft).getApproved(tokenId) == address(this));
        bool approvedForAll = IERC721(nft).isApprovedForAll(msg.sender, address(this));
        require(approvedForToken || approvedForAll, "Manager not approved. owner must approve");

        listings[nft][tokenId] = Listing({ owner: msg.sender, nft: nft,tokenId: tokenId, numberOfRents: numberOfRents,  price: price, active: true });
        allListings.push(listings[nft][tokenId]);
        // allListings[allListings.length] = listings[nft][tokenId];
        IERC4907(nft).setListed(tokenId, true);

        emit Listed(nft, tokenId, msg.sender, price);
    }

    function cancelListing(address nft, uint256 tokenId) external {
        Listing storage l = listings[nft][tokenId];
        require(l.owner == msg.sender, "Not listing owner");
        l.active = false;
        IERC4907(nft).setListed(tokenId, false);
        emit Cancelled(nft, tokenId);
    }

    /// Rent: renter sends exactly price; owner must previously approve this contract
    function rent(address nft, uint256 tokenId, uint64 duration) external payable nonReentrant {
        Listing storage l = listings[nft][tokenId];
        require(l.active, "Not active");
        require(msg.value >= l.price, "Incorrect payment");
        require(l.numberOfRents == 0 || l.numberOfRents > rentUsed[nft][tokenId], "No rents left");
        // ensure manager is approved to manage token's user (owner must approve this contract)
        bool approvedForToken = (IERC721(nft).getApproved(tokenId) == address(this));
        bool approvedForAll = IERC721(nft).isApprovedForAll(l.owner, address(this));
        require(approvedForToken || approvedForAll, "Manager not approved. owner must approve");

        // forward funds to owner
        (bool sent, ) = payable(l.owner).call{ value: msg.value }("");
        require(sent, "Payment transfer failed");

        // set user until now + duration
        uint64 expires = uint64(block.timestamp + (duration*86400)); // 14400 = 24*60*60/15 (15s blocks)
        IERC4907(nft).setUser(tokenId, msg.sender, expires);
        rentUsed[nft][tokenId] += 1;
        emit Rented(nft, tokenId, l.owner, msg.sender, l.price, expires);
    }

    // helper view
    function getListing(address nft, uint256 tokenId) external view returns (Listing memory) {
        return listings[nft][tokenId];
    }

    function getAllListing() external view returns (Listing[] memory) {
        return allListings;
    }

    
}
