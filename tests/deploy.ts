const { ethers } = require('hardhat');
const { config } = require('hardhat');

async function main() {
  const accounts = config.networks.hardhat.accounts;
  const wallet = ethers.Wallet.fromPhrase(accounts.mnemonic, accounts.path + `/${0}`);

  console.log(`Private key: `, wallet.privateKey);

  const [owner ] = await ethers.getSigners();
  console.log(`Signer is ${owner.address}`);

  const token = await ethers.deployContract("Token", ["1XMM", "OneXMM", 31337, 65000000, 1500000]);
  await token.waitForDeployment();

  console.log(`Token contract has been deployed to ${token.target}`);
  console.log(`Owner is ${await token.Owner()}\n`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
