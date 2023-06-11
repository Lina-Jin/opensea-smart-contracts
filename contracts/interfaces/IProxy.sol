// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProxy {
    //AuthenticatedProxy 등록된 proxy 함수에 접근
    function proxy(
        address dest,
        bytes calldata calldata_
    ) external returns (bool result);
}
