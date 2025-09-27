// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Simple ERC-721 with ERC-4907-like rentable extension (user + expires).
 * Owner (contract owner) can mint tokens.
 *
 * Note: For compatibility across different OpenZeppelin versions, this
 * version does NOT override transfer hooks. Instead it exposes `clearUser`
 * which can be called by the token owner or approved operators to clear rental state.
 */
contract RentableNFT is ERC721URIStorage, Ownable {
    uint256 private _tokenIdCounter;

    // ERC4907-like storage
    mapping(uint256 => mapping(address => bool)) private _users;
    mapping(uint256 => mapping(address => uint64)) private _userExpires;
    mapping(uint256 => bool) public listed;
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    constructor(string memory name_, string memory symbol_,address __owner) ERC721(name_, symbol_) Ownable(__owner) {}

    function mint(address to, string calldata tokenURI) external returns (uint256) {
        _tokenIdCounter += 1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        return tokenId;
    }

    

    /// Set the listing — only owner or approved can call
    function setListed(uint256 tokenId, bool _listed) external {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender),
            "RentableNFT: caller not owner nor approved"
        );
        listed[tokenId] = _listed ;
    }

    /// Set the user and expires — only owner or approved can call
    function setUser(uint256 tokenId, address user, uint64 expires) public {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender),
            "RentableNFT: caller not owner nor approved"
        );
        _users[tokenId][user] = true ;
        _userExpires[tokenId][user] = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    /// returns the current user if not expired
    function hasRent(uint256 tokenId,address user) public view returns (bool) {
        if (uint64(block.timestamp) <= _userExpires[tokenId][user]) {
            return true;
        } else {
            return false;
        }
    }

    function userExpires(uint256 tokenId,address user) public view returns (uint64) {
        return _userExpires[tokenId][user];
    }

    function totalMinted() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /// Clear user data and emit event. Can be called by token owner or approved operator.
    function clearUser(uint256 tokenId,address user) public {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender),
            "RentableNFT: caller not owner nor approved"
        );
        if (_userExpires[tokenId][user] != 0 || _users[tokenId][user] != false) {
            _users[tokenId][user] = false;
            _userExpires[tokenId][user] = 0;
            emit UpdateUser(tokenId, address(0), 0);
        }
    }
}
