// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./AuthenticatedProxy.sol";

contract  ProxyRegistry is Ownable{
    //Proxy Contract의 함수를 호출할수 있는 제어권을 가진 컨트렉드들
    mapping (address => bool) public contracts;
    //유저가 등록한 Proxy Contract 
    mapping (address => address) public proxies;

    //특정 컨트랙트에 Proxy Contract에 대한 제어권 부여
    //Contract Owner만 호출 가능
    function grantAuthentication (address addr)external onlyOwner{
        //제어권 부여 되였는지 체크
        require(!contracts[addr],"already registerd");
        //제어권 없을 시 제어권 부여된 함수로 등록
        contracts[addr] = true;
    }

    //특정 컨트랙트의 Proxy Contract에 대한 제어권 등록된것을 삭제
    //Contract Owner만 호출 가능
    function revokeAuthentication (address addr) external onlyOwner {
        //제어권 부여 되였는지 체크
        require(contracts[addr],"didn't registerd");
        //제어권 있을 시 삭제
        delete contracts[addr];
    }

    //유저는 이 함수를 통해 각 지갑마다 하나의 Proxy Contract 생성
    //Contract Owner가 grantAuthentication으로 등록한 컨트랙트는(즉 contracts) 유저가 생성한 Proxy Contract의 모든 권한을(어떤 바이트 코드, 명령어를 실행할 수 있는 권한) 가진다. 
    function registerProxy () external returns (AuthenticatedProxy){
        //해당 지갑으로 Proxy Contract를 생성 한적 있는지 체크 
        require (proxies[msg.sender]==address(0),"already registered proxy contract");

        //새로은 proxy 컨트랙트 생성
        AuthenticatedProxy proxy = new AuthenticatedProxy(msg.sender);
        proxies[msg.sender] = address(proxy);

        return proxy;
    }
}