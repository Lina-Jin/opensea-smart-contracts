// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TokenIdentifiers.sol";

contract AssetShared is ERC721 {
    using TokenIdentifiers for uint256;
    mapping (uint256 => string) _tokenURI;//tokenid=> tokenURI

    constructor (string memory name_, string memory symbol_)ERC721(name_, symbol_)    {    }

    //minter가 민팅 가능한지 체크하는 함수
    function _requireMintable(address minter, uint256 tokenId) internal pure {
        require (tokenId.tokenCreator() == minter, "only creator can mint token" );
    }

    function _mint(address to, uint256 tokenId) internal override {
        _requireMintable(msg.sender, tokenId);
        super._mint(to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        //erc721 기본함수: 토큰 존재여부 체크하여 민팅혹은 transferfrom
        bool exists = _exists(tokenId);
        if(exists){
            super.safeTransferFrom(from, to, tokenId, data);
        }else{
            _mint(to, tokenId);
            _setTokenURI(tokenId, string(data));
        }
    }

    function _setTokenURI(uint256 tokenId, string memory uri) internal {
        _tokenURI[tokenId]  =uri;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory){
        _requireMinted(tokenId);
        return _tokenURI[tokenId] ;
    }

}