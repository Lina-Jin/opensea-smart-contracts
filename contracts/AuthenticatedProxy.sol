// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IProxyRegistry.sol";

contract  AuthenticatedProxy {
    address public userAddress;
    address proxyRegistryAddress;
    bool public revoked;

    constructor(address userAddress_){
        userAddress = userAddress_; //유저 주소
        proxyRegistryAddress = msg.sender;//ProxyRegistry컨트랙트 주소: ProxyRegistry컨트랙트에서 registerProxy 함수를 호출 하여 생성 되므로 msg.sender가 ProxyRegistry컨트랙트 주소임
    }

    //유저 지갑에서만 함수를 호출 할수 있도록 제한
    modifier onlyUser() {
        require(msg.sender == userAddress);
        _;
    }

    //AuthenticatedProxy 컨트렉트 무효화하기, 유저만
    function setRevoke ()external onlyUser{
        require(!revoked);
        revoked = true;
    }

    //proxy 함수: 어떤 컨트렉트에서 어떤 데이터를 실행할지 인자로 받아 실행
    function proxy (address dest, bytes calldata calldata_) external returns (bool result){
        //함수 호출 가능 한 주소
        //1. 컨트렉트를 생성한 유저 본인
        //2. ProxyRegistry에 등록된 contracts: revoked 되여있지 않아야 함
        require(
            msg.sender == userAddress || 
                ((!revoked) && IProxyRegistry(proxyRegistryAddress).contracts(msg.sender))
        );

        //result: 성공시 true, 실패 false
        (result, ) = dest.call(calldata_);
        return result;
    }
}
