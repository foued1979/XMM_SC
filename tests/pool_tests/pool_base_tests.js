const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const ratePrecision = 10_000n;

async function _deploy1XMM() {
  const contractFactory = await ethers.getContractFactory("Token");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  return await contractFactory.deploy("1XMM", "OneXMM", 1, 5_000_000, 250_000);
}

async function _deployERC20() {
  const contractFactory = await ethers.getContractFactory("Allocatable");
  return await contractFactory.deploy("COIN", 100_000_000, 18);
}

async function _deploy1DPool() {
  const [owner] = await ethers.getSigners();
  const token = await loadFixture(_deployERC20);
  const onexmm = await loadFixture(_deploy1XMM);
  
  const contractFactory = await ethers.getContractFactory("CoinPool");
  const pool = await contractFactory.deploy(await token.getAddress(), owner.address, 18, await onexmm.getAddress(), 18, 600, 25, 10, 500, 50);

  return [pool, token, onexmm];
}

describe('Pool deployment works as expected', function() {
    it('Public Properties are as expected at inception', async function() {
        const [pool, token, onexmm] = await loadFixture(_deploy1DPool);
        const [ owner, spender ] = await ethers.getSigners();

        await token.allocate(spender, 120 * 10 **18);

        await pool.connect(spender).deposit();
    });
});

