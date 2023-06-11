import { ethers } from "hardhat";

//Proxy Registry Address : 0x54378434e3a96f0FdC79D60B2C2264E769E159Be
//NFT Exchange : 0x10820ADdfD1E0e02fB3C682b8c1BEd5201BD004c, 0x26746E54AF3ed2C2d8e9cA7261EF65aA99B87dB0(오류)
async function main() {
  //프록시 레지스트리 컨트랙트 먼저 배포
  // const ProxyRegistry = await ethers.getContractFactory("ProxyRegistry");
  // const proxyRegistry = await ProxyRegistry.deploy();

  // await proxyRegistry.deployed();

  // console.log("Proxy Registry Address :", proxyRegistry.address);

  //거래소(거래) 컨트랙트 비포
  const Exchange = await ethers.getContractFactory("NFTExchange");
  const exchange = await Exchange.deploy(
    "0x72637AcAb18E95EAE9DE4dcb31cd5A991f574ceD",
    "0x54378434e3a96f0FdC79D60B2C2264E769E159Be"
  );

  await exchange.deployed();

  console.log("NFT Exchange :", exchange.address);

  //거래소(거래) 컨트랙트가 proxy contract를 사용할 수 있도록, proxy registry에 거래소(거래) 컨트랙트 등록
  //await proxyRegistry.functions.grantAuthentication(exchange.address);
  //console.log("Allow exchange to use proxy contracts successfully!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
