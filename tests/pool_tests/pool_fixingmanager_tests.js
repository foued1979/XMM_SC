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
  const pool = await contractFactory.deploy(await token.getAddress(), owner.address, await onexmm.getAddress(), 18, 18, 0, 25, 10, 500, 50);

  return [pool, token, onexmm];
}

async function _deploy1WPool() {
    const [owner] = await ethers.getSigners();
    const token = await loadFixture(_deployERC20);
    const onexmm = await loadFixture(_deploy1XMM);
    
    const contractFactory = await ethers.getContractFactory("CoinPool");
    const pool = await contractFactory.deploy(await token.getAddress(), owner.address, await onexmm.getAddress(), 18, 18, 1, 25, 10, 500, 50);
  
    return [pool, token, onexmm];
  }

describe('Fixings are working as expected', function() {
    it('Init settings are as expected', async function() {
        const [pool, token, onexmm] = await loadFixture(_deploy1DPool);

        const fixings = await pool.getFixings();
        expect(fixings.length).to.equal(0);
    });
});