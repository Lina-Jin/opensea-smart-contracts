// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProxyRegistry {
    //ProxyRegistry에 등록된 contracts에 접근
    function contracts(address addr_) external view returns (bool);

    //ProxyRegistry에 등록된 proxies에 접근
    function proxies(address addr_) external view returns (address);
}
