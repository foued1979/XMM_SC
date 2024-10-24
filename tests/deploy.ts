const { ethers } = require('hardhat');

async function main() {
  const [owner ] = await ethers.getSigners();
  console.log(`Signer is ${owner.address}`);

  const token = await ethers.deployContract("Token");
  await token.waitForDeployment();

  console.log(`LibTest contract has been deployed to ${token.target}`);
  console.log(`Owner is ${await token.Owner()}\n`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
