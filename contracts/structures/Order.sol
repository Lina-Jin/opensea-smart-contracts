// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

enum SaleSide {
    BUY,
    SELL
}

//판매 방식
enum SaleKind {
    FIXED_PRICE,
    AUCTION
}

struct Order {
    //거래소 컨트렉트 주소: 주문이 어떤 거래소에 사용하는 주문인지 나타냄
    address exchange;
    //거래를 생성한 사람
    address maker;
    //누구와 거래 할 것인지, taker 없을 시 null
    address taker;
    SaleSide saleSide;
    SaleKind saleKind;
    //거래할 nft 주소
    address target;
    //거래시 사용되는 erc20토큰 주소, null일시 이더리움 의미
    address paymentToken;
    //거래 성사 시 실행될 코드
    bytes calldata_;
    bytes replacementPattern;
    //주문검증 시 사용될 주소
    address staticTarget;
    //extraCalldata
    bytes staticExtra;
    //거래 가격
    uint256 basePrice;
    //종료 가격, 고정가 판매시 필요 없음
    uint256 endPrice;
    //주문 유효시간
    uint256 listingTime;
    uint256 expirationTime;
    //랜덤 값
    uint256 salt;
}
