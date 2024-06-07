
import { ethers } from "hardhat";
import hre from "hardhat";

import * as dotenv from "dotenv";

dotenv.config();

async function main() {


  const Bridge2 = await ethers.getContractFactory("Bridge2");

  console.log("Deploying Bridge2...");

  const hotAddresses = [];

  const coldAddresses = [];

  const powers = [];

  const addressUsdc = "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e";

  const disputePeriodSeconds = 0;

  const blockDurationMills = 0;

  const lockerThreshold = 0;

  const bridge2 = await Bridge2.deploy(
    hotAddresses,
    coldAddresses,
    powers,
    addressUsdc,
    disputePeriodSeconds,
    blockDurationMills,
    lockerThreshold
  );

  console.log("Bridge2 deployed to:", bridge2.address);

  console.log("Trying to verify the contract...");

    try {
      await hre.run("verify:verify", {
        address: bridge2.address,
        constructorArguments: [
          hotAddresses,
          coldAddresses,
          powers,
          addressUsdc,
          disputePeriodSeconds,
          blockDurationMills,
          lockerThreshold,
        ],
      });

      console.log("Contract verified!");
    } catch (err: any) {
      console.error("Error verifying contract:", err);
    }

  console.log("Deployment complete");
}

main().catch((error) => {
  console.error(error);

  process.exitCode = 1;
});
