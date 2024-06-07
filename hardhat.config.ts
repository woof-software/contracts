import * as dotenv from "dotenv";
import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers";
import "hardhat-contract-sizer";
import "solidity-coverage";
import "solidity-docgen";
import { glob } from "glob";

dotenv.config();

task("run-test", "Runs tests on a directory")
  .addParam("directory", "The directory to run the tests on")
  .setAction(async (taskArgs, hre) => {
    const testFiles = glob.sync(`${taskArgs.directory}/**/*.ts`);
    for (const file of testFiles) {
      await hre.run("test", {
        testFiles: [file],
      });
    }
  });

task("run-cov", "Runs coverage on a directory")
  .addParam("directory", "The directory to run the tests on")
  .setAction(async (taskArgs, hre) => {
    await hre.run("coverage", {
      testfiles: `${taskArgs.directory}/**/*.ts`,
      network: "hardhat",
    });
  });

const config = {
  docgen: {
    exclude: [],
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1337,
      accounts: [{ privateKey: process.env.PRIVATE_KEY || "", balance: "10000000000000000000000" }],
    },
    avax: {
      url: process.env.AVAX_RPC_URL || "",
      chainId: 43114,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    fuji: {
      url: process.env.FUJI_RPC_URL || "",
      chainId: 43113,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: process.env.AVAX_API_KEY || "",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000,
          },
          viaIR: false,
        },
      },
    ],
  },
  mocha: {
    timeout: 100000000,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
