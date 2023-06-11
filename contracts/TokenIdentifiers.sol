// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library  TokenIdentifiers{
    //상속값을 정의
    uint8 constant ADDRESS_BITS = 160;
    uint8 constant INDEX_BITS = 96 ;

    uint256 constant INDEX_MASK = 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    
    //엔드비트 연산으로 토큰 인덱스 반환
    function tokenIndex(uint256 _id) public pure returns (uint256) {
        return _id & INDEX_MASK;
    }

    //시프트 연산으로 주소 반환
    function tokenCreator(uint256 _id) public pure returns (address) {
        return address (uint160(_id >> INDEX_BITS));
    }
}