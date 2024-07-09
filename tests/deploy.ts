import { ethers } from "hardhat";

async function main() {
  const [owner, addr1, addr2] = await ethers.getSigners();
  console.log(`Signer is ${owner.address}`);

  const libtest = await ethers.deployContract("LibTest");
  await libtest.waitForDeployment();

  console.log(`LibTest contract has been deployed to ${libtest.target}`);
  console.log(`Owner is ${await libtest.Owner()}\n`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
