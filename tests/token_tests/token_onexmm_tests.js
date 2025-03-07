const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const [owner] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  const token = await contractFactory.deploy("TEST", "0x1234567890123456789012345678901234500000", "0x1234567890123456789012345678901234500001", "Test token", 5_000_000, 250_000);

  return [ owner, token ];
}

async function _deployERC20() {
  const [owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, "0x1234567890123456789012345678901234500002", "0x1234567890123456789012345678901234500003", 100_000, "COIN1", "COIN1", 18);
}

async function _deployERC20_6() {
  const [owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, "0x1234567890123456789012345678901234500002", "0x1234567890123456789012345678901234500003", 50_000, "COIN2", "COIN2", 6);
}

describe('Test 1XMM specific token functions', function () {
    it('Owner can transfer back', async function() {
      const [owner, token] = await loadFixture(_deploy);
      
      await expect(token.ownerTransfersBack(250_001n * BigInt(10 ** 18))).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
      expect(await token.ownerTransfersBack(150_000n * BigInt(10 ** 18))).to.emit("Transfer");

      expect(await token.balanceOf(owner)).to.equal(100_000n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal(100_000n * BigInt(10 ** 18));
      expect(await token.cap()).to.equal(5_000_000n * BigInt(10 ** 18));
    });
});