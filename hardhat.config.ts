require("dotenv").config();

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.9",
    settings: {
      //배포 시 가스 수수료를 절약 가능
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    hardhat: {},
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/jgQ3zdkAU9QznJYJR1Z7QgPO-lREcd6Q`,
      accounts: [`${process.env.PRIVATE_KEY}`],
    },
  },
};

export default config;
