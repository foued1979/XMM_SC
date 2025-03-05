const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  return await contractFactory.deploy("TEST", "0x1234567890123456789012345678901234500000", "0x1234567890123456789012345678901234500001", "Test token", 5_000_000, 250_000);
}

async function _deployERC20() {
  const owner = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, "0x1234567890123456789012345678901234500002", "0x1234567890123456789012345678901234500003", 100_000, "COIN1", "COIN1", 18);
}

async function _deployERC20_6() {
  const owner = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, "0x1234567890123456789012345678901234500002", "0x1234567890123456789012345678901234500003", 50_000, "COIN2", "COIN2", 6);
}

describe('Test 1XMM specific token functions', function () {
    it('', async function() {
    });
});