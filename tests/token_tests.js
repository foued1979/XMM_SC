const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

async function _deploy() {
  const [owner] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("Token");
  const token = await contractFactory.deploy("TEST", "Test token", 5_000_000, 18, 250_000);

  return [ owner, token ];
}

describe('Test token', function () {
    it('Should deploy, have right parameters', async function () {
      const [ owner, token ] = await loadFixture(_deploy);
      
      expect(await token.Owner()).to.equal(owner);
      expect(await token.Symbol()).to.equal("TEST");
      expect(await token.ChangeIsAllowed()).to.equal(false);
      expect(await token.balanceOf(owner)).to.equal(250_000n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal(5_000_000n * BigInt(10 ** 18));
    });

    it('Allocation is done properly and is reflected in AllocatedAmount', async function () {
      const [ owner, token ] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 100n * BigInt(10 ** 18);
      await token.allocate("0x1234567890123456789012345678901234567890", amount1);

      const amount2 = 50n * BigInt(10 ** 18);
      await token.allocate("0x1234567890123456789012345678901233458793", amount2);

      expect(await token.balanceOf("0x1234567890123456789012345678901234567890")).to.equal(amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678901233458793")).to.equal(amount2);
      expect(await token.AllocatedAmount()).to.equal(ownerAmount + amount1 + amount2);
    });

    it('Transfer is ok', async function () {
      const [ owner, token ] = await loadFixture(_deploy);

      const ownerAmount = 250_000n * BigInt(10 ** 18);

      const transfer = 20n * BigInt(10 ** 18);
      await token.transfer("0x1234567890123456789012345678901234567890", transfer)

      expect(await token.balanceOf("0x1234567890123456789012345678901234567890")).to.equal(transfer);
      expect(await token.balanceOf(owner)).to.equal(ownerAmount - transfer);
      expect(await token.AllocatedAmount()).to.equal(ownerAmount);
    });
  });