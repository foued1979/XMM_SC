const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { boolean } = require('hardhat/internal/core/params/argumentTypes');

const decimalAdjustment = BigInt(10 ** 18);

async function _deploy() {
  const [owner] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("Token");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  const token = await contractFactory.deploy("TEST", "Test token", 1, 5_000_000, 250_000);

  return [ owner, token ];
}