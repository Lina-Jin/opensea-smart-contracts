// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./structures/Order.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IProxy.sol";
import "./interfaces/IProxyRegistry.sol";

//서명값
struct Sig {
    bytes32 r;
    bytes32 s;
    uint8 v;
}

contract NFTExchange is Ownable, ReentrancyGuard {
    //Order 구조체 keccak-256 해싱값 (eip-712 표준),띄어쓰기 없음 주의
    bytes32 private constant ORDER_TYPEHASH =
        0x7d2606b3242cc6e6d31de9a58f343eed0d0647bd06fe84c19441d47d44316877;

    //서명 검증을 위해서 컨트랙트 내부에서 DOMAIN_SEPERATOR값을 계산
    bytes32 private DOMAIN_SEPERATOR =
        keccak256(
            abi.encode(
                keccak256(
                    //eip712 도메인 타입에 대한 해시값(띄어쓰기 없어야 함)
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                //변수
                keccak256("Wyvern Clone Coding Exchange"), //도메인 name
                keccak256("1"), //도메인 version
                5, //사용할 chainId
                address(this) //verifyingContract, 즉 이 컨트랙트 주소
            )
        );

    //수수료 납부 주소
    address public feeAddress;

    //완료 혹은 취소된 주문 저장: 주문 해시값 => bool
    mapping(bytes32 => bool) public cancelledOrFinalized;

    //인터페이스로 proxyRegistry 컨트렉트에 접근
    IProxyRegistry proxyRegistry;

    //atomicMatch 종료 후
    event OrdersMatched(
        bytes32 buyHash,
        bytes32 sellHash,
        address indexed maker,
        address indexed taker,
        uint256 price
    );

    constructor(address feeAddress_, address proxyRegistry_) {
        feeAddress = feeAddress_;
        proxyRegistry = IProxyRegistry(proxyRegistry_);
    }

    //수수료 납부 주소 변경: only owner
    function setFeeAddress(address feeAddress_) external onlyOwner {
        feeAddress = feeAddress_;
    }

    //주문 매칭 및 실행
    function atomicMatch(
        Order memory buy,
        Sig memory buySig,
        Order memory sell,
        Sig memory sellSig
    ) external payable nonReentrant {
        //sell과 buy 두 주문의 파라미터 값이 올바른지 검증하고 주문 해시값 받기
        bytes32 buyHash = validateOrder(buy, buySig);
        bytes32 sellHash = validateOrder(sell, sellSig);

        //buy, sell이 완료된 주문인지 체크
        require(
            !cancelledOrFinalized[buyHash] && !cancelledOrFinalized[sellHash],
            "finalized order"
        );

        // buy order와 sell order이 서로 매칭되는지 검증
        require(ordersCanMatch(buy, sell), "order not matched");

        //target 주소가 컨트렉트인지 체크
        uint size;
        address target = sell.target;
        assembly {
            size := extcodesize(target)
        }
        require(size > 0, "not a contract"); //컨트렉트일시 코드가 존재하므로 사이즈는 0보다 큼

        //buy와 sell에 replacementpattern이(미완성된 부분) 존재 시 마스크 부분 치환하기
        if (buy.replacementPattern.length > 0) {
            guardedArrayReplace(
                buy.calldata_,
                sell.calldata_,
                buy.replacementPattern
            );
        }
        if (sell.replacementPattern.length > 0) {
            guardedArrayReplace(
                sell.calldata_,
                buy.calldata_,
                sell.replacementPattern
            );
        }

        //치환후 buy와 sell의 calldata가 일치 하는지 확인
        require(
            keccak256(buy.calldata_) == keccak256(sell.calldata_),
            "calldata not matched"
        );

        //완료 된 주문으로 등록
        if (msg.sender != buy.maker) {
            cancelledOrFinalized[buyHash] = true;
        }

        if (msg.sender != sell.maker) {
            cancelledOrFinalized[sellHash] = true;
        }

        //buyer가 seller에게 토큰 전송 및 수수료 납부
        uint256 price = executeFundsTransfer(buy, sell);

        //seller의 proxy컨트렉트에 접근
        IProxy proxy = IProxy(proxyRegistry.proxies(sell.maker));

        //seller의 proxy컨트렉트에서 proxy함수를 호출하여 주문을 실행하고 성공 여부를 체크
        require(proxy.proxy(sell.target, sell.calldata_), "proxy call failure");

        //거래 완료 후 주문 최종 검증(옵션), staticTarget주소가 명시된 경우만 진행
        //성공여부를 반환
        if (buy.staticTarget != address(0)) {
            require(
                staticCall(buy.target, buy.calldata_, buy.staticExtra),
                "buyer static call failure"
            );
        }
        if (sell.staticTarget != address(0)) {
            require(
                staticCall(sell.target, sell.calldata_, sell.staticExtra),
                "seller static call failure"
            );
        }

        emit OrdersMatched(
            buyHash,
            sellHash,
            msg.sender == sell.maker ? sell.maker : buy.maker,
            msg.sender == sell.maker ? buy.maker : sell.maker,
            price
        );
    }

    // buy와 sell 을 받아 최종가격을 결정
    function calculateMatchPrice(
        Order memory buy,
        Order memory sell
    ) internal view returns (uint256) {
        uint256 buyPrice = getOrderPrice(buy);
        uint256 sellPrice = getOrderPrice(sell);

        require(buyPrice >= sellPrice, "sell price is higher");

        return buyPrice;
    }

    //주문 가격 계산
    function getOrderPrice(Order memory order) internal view returns (uint256) {
        if (order.saleKind == SaleKind.FIXED_PRICE) {
            //고정가의 경우 그대로 리턴
            return order.basePrice;
        } else {
            //경매일 경우
            if (order.basePrice > order.endPrice) {
                //sell with declining price 방식
                //시간이 지나면서 linear하게 가격이 endprice까지 하락
                return
                    order.basePrice -
                    (((block.timestamp - order.listingTime) *
                        (order.basePrice - order.endPrice)) /
                        (order.expirationTime - order.listingTime));
            } else {
                //sell to highest bidder방식
                if (order.saleSide == SaleSide.SELL) {
                    //sell 주문 시 시작가 리턴
                    return order.basePrice;
                } else {
                    //buy 주문일 시 마지막 가격 리턴
                    return order.endPrice;
                }
            }
        }
    }

    //수수료 계산
    function getFeePrice(uint256 price) internal pure returns (uint256) {
        return price / 40;
    }

    //buyer가 seller에게 토큰 전송 및 수수료 납부
    function executeFundsTransfer(
        Order memory buy,
        Order memory sell
    ) internal returns (uint256 price) {
        //paymentToken 주소가 erc20일시 이더 전송 못하도록 막기
        if (sell.paymentToken != address(0)) {
            require(
                msg.value == 0,
                "cannot send ether when payment token is not ether"
            );
        }

        //가격 계산
        price = calculateMatchPrice(buy, sell);
        //수수료 계산
        uint256 fee = getFeePrice(price);

        if (price <= 0) {
            return 0;
        }

        //buyer가 seller에게 토큰 전송
        if (sell.paymentToken != address(0)) {
            // ERC-20 토큰을 전송해야 하는 경우
            // 토큰 전송
            IERC20(sell.paymentToken).transferFrom(
                buy.maker,
                sell.maker,
                price
            );
            //수수료 지불
            IERC20(sell.paymentToken).transferFrom(buy.maker, feeAddress, fee);
        } else {
            // 이더를 전송해야 하는 경우
            // 거래소개 전송할수 없으므로 buyer가 트잭 발생 시 이더를 전송해야함, 그러므로 seller는 트잭 전송 불가
            require(msg.sender == buy.maker, "not a buyer");

            // 토큰 전송
            (bool result, ) = sell.maker.call{value: price}("");
            require(result, "failed to send to seller");
            //수수료 지불
            (result, ) = feeAddress.call{value: fee}("");
            require(result, "failed to send to fee");

            // 남은 이더가 있을 경우 다시 buyer에거 반환
            uint256 remain = msg.value - price - fee;
            if (remain > 0) {
                (result, ) = msg.sender.call{value: remain}("");
                require(result, "remain sent failure");
            }
        }
    }

    // buy order와 sell order이 서로 매칭되는지 검증
    function ordersCanMatch(
        Order memory buy,
        Order memory sell
    ) internal view returns (bool) {
        // Sell to highest bidder 방식일 경우에는 seller 만 트랜잭션 호출 가능
        // 누군가가 최고가보다 낮은 가격에 주문을 생성하고, 트랜잭션을 보내는 것을 방지하기 위함.
        if (
            sell.saleKind == SaleKind.AUCTION && sell.basePrice <= sell.endPrice
        ) {
            require(
                msg.sender == sell.maker,
                "only seller can send for sell to highest bidder"
            );
        }
        return
            //taker와 maker 일치한지 체크
            (buy.taker == address(0) || buy.taker == sell.maker) &&
            (sell.taker == address(0) || buy.maker == sell.taker) &&
            //saleside 체크
            (buy.saleSide == SaleSide.BUY && sell.saleSide == SaleSide.SELL) &&
            //salekind가 동일한지 체크
            (buy.saleKind == sell.saleKind) &&
            //nft 컨트렉트 주소가 동일한지 체크
            (buy.target == sell.target) &&
            //거래시 사용되는 재화가 동일한지 체크
            (buy.paymentToken == sell.paymentToken) &&
            //거래 가격이 동일한지 체크
            (buy.basePrice == sell.basePrice) &&
            //종료 가격이 동일한지 체크
            (//고정가 판매시 endprice 필요없으므로 비교 안하고 통과
            sell.saleKind == SaleKind.FIXED_PRICE ||
                // Sell to highest bidder 방식 시는 buy와 sell의 endprice는 다를 수 있음
                sell.basePrice <= sell.endPrice ||
                // basePrice > endPrice 의 경우 sell with declining price 방식으로 endPrice 가 동일해야 함.
                buy.endPrice == sell.endPrice) &&
            //주문 유효시간 만료 여부 체크
            (canSettleOrder(buy) && canSettleOrder(sell));
    }

    //주문 유효시간 만료 여부 체크
    function canSettleOrder(Order memory order) internal view returns (bool) {
        return (order.listingTime <= block.timestamp &&
            (order.expirationTime == 0 ||
                order.expirationTime >= block.timestamp));
    }

    //주문의 파라미터 값이 올바른지 검증하고 주문 해시값 리턴
    function validateOrder(
        Order memory order,
        Sig memory sig
    ) public view returns (bytes32 orderHash) {
        //다른 사람이 생성한 주문일 시, 주문 생성자의 서명인지 검증
        //내가 생성한 주문은 서명 검증 없이 주문 자체 만 검증
        if (msg.sender != order.maker) {
            orderHash = validateOrderSig(order, sig);
        } else {
            orderHash = hashOrder(order);
        }

        //order 거래소 주소 확인
        require(order.exchange == address(this), "wrong exchange");

        //auction 거래일 때 expiration time이 필수므로, 이에 대한 체크
        if (order.saleKind == SaleKind.AUCTION) {
            require(
                order.expirationTime > order.listingTime,
                "wrong timestamp"
            );
        }
    }

    //주문 해시값에 대한 서명 받고, 서명이 주문 생성자가 맞는지 검증
    function validateOrderSig(
        Order memory order,
        Sig memory sig
    ) internal view returns (bytes32 orderHash) {
        //주문에대한 해시값과 서명 메서지를 구함
        bytes32 sigMessage;
        (orderHash, sigMessage) = orderSigMessage(order);

        // 주문 생성자가 서명을 생성 하였는지 검증
        // 서명 검증할 때 주문에 대한 해시값(orderHash)이 아닌 EIP-712 표준에 따른
        // 서명 메시지(sigMessage)로 검증합니다.
        require(ecrecover(sigMessage, sig.v, sig.r, sig.s) == order.maker);
    }

    //주문을 해싱하기 (eip-712 표준)
    function hashOrder(Order memory order) public pure returns (bytes32 hash) {
        return
            keccak256(
                //파라미터가 너무 많아 두개로 분리해서 넣음, 한번에 넣을시 Stack too deep 에러 발생
                //순서가 구조체와 일치 해야함
                //bytes 등 크기가 고정이 아닌 변수는 keccak256으로 해싱 값을 넣어야 함
                abi.encodePacked(
                    abi.encode(
                        ORDER_TYPEHASH,
                        order.exchange,
                        order.maker,
                        order.taker,
                        order.saleSide,
                        order.saleKind,
                        order.target,
                        order.paymentToken,
                        keccak256(order.calldata_),
                        keccak256(order.replacementPattern),
                        order.staticTarget,
                        keccak256(order.staticExtra)
                    ),
                    abi.encode(
                        order.basePrice,
                        order.endPrice,
                        order.listingTime,
                        order.expirationTime,
                        order.salt
                    )
                )
            );
    }

    //현재 바이트 코드에서 상대방의 바이트코드를 마스크한 부분만 복사하는 함수
    function guardedArrayReplace(
        bytes memory array,
        bytes memory desired,
        bytes memory mask
    ) internal pure {
        require(array.length == desired.length, "not the same length");
        require(array.length == mask.length, "not the same length");

        uint words = array.length / 0x20;
        uint index = words * 0x20;
        assert(index / 0x20 == words);
        uint i;

        for (i = 0; i < words; i++) {
            /* Conceptually: array[i] = (!mask[i] && array[i]) || (mask[i] && desired[i]), bitwise in word chunks. */
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        }

        /* Deal with the last section of the byte array. */
        if (words > 0) {
            /* This overlaps with bytes already set but is still more efficient than iterating through each of the remaining bytes individually. */
            i = words;
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        } else {
            /* If the byte array is shorter than a word, we must unfortunately do the whole thing bytewise.
               (bounds checks could still probably be optimized away in assembly, but this is a rare case) */
            for (i = index; i < array.length; i++) {
                array[i] =
                    ((mask[i] ^ 0xff) & array[i]) |
                    (mask[i] & desired[i]);
            }
        }
    }

    //staticcall로 주문 검증: 성공 여부 리턴
    function staticCall(
        address target, //검증할 주소
        bytes memory calldata_,
        bytes memory extraCalldata
    ) internal view returns (bool result) {
        bytes memory combined = bytes.concat(extraCalldata, calldata_);
        uint256 combinedSize = combined.length;

        assembly {
            result := staticcall(
                gas(), //현재 남은 가스량
                target, //타겟 주소(콜할 컨트렉트)
                combined, //실행할 코드
                combinedSize, //실행할 코드 사이즈
                mload(0x40), //결과 값을 쓸 주소 (결과값을 쓰지 않으므로 임의로 작성 하여도 무방)
                0 //결과 값 사이즈(결과 값을 받지 않으므로 0)
            )
        }
    }

    //order 주문객체에 대한 서명 값과 해시값을 구함
    function orderSigMessage(
        Order memory order
    ) internal view returns (bytes32 orderHash, bytes32 sigMessage) {
        orderHash = hashOrder(order);
        sigMessage = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPERATOR, orderHash)
        );
    }
}
