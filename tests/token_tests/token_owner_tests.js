const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { boolean } = require('hardhat/internal/core/params/argumentTypes');

const decimalAdjustment = BigInt(10 ** 18);

async function _deploy() {
  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  return await contractFactory.deploy("TEST", "0x1234567890123456789012345678901234500000", "0x1234567890123456789012345678901234500001", "Test token", 5_000_000, 250_000);
}

describe("Test owner functions", function() {
  it('Can burn tokens', async function() {
    const token = await loadFixture(_deploy);

    await token.burn(500_000n * BigInt(10 ** 18));
    expect(await token.TotalSupply()).to.equal((5_000_000n - 500_000n) * BigInt(10 ** 18));
    expect(await token.AvailableTokens()).to.equal((5_000_000n - 250_000n - 500_000n) * BigInt(10 ** 18));

    await expect(token.burn((5_000_000n - 500_000n) * BigInt(10 ** 18))).to.be.revertedWith("Burn failed");
  });
});