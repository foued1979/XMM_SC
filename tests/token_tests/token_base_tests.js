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

describe('Test base token functions', function () {
    it('Allocation is done properly and is reflected in AllocatedAmount', async function () {
      const token = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 100n * BigInt(10 ** 18);
      await expect(token.allocate("0x1234567890123456789012345678901234567890", amount1)).to.emit(token, 'Allocated');

      const amount2 = 50n * BigInt(10 ** 18);
      await token.allocate("0x1234567890123456789012345678901233458793", amount2);

      expect(await token.balanceOf("0x1234567890123456789012345678901234567890")).to.equal(amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678901233458793")).to.equal(amount2);
      expect(await token.totalSupply()).to.equal(ownerAmount + amount1 + amount2);
      expect(await token.availableTokens()).to.equal(5_000_000n * BigInt(10 ** 18) - (ownerAmount + amount1 + amount2));
    });

    it('Can allocate to different users', async function() {
      const token = await loadFixture(_deploy);
      const amount1 = 200n * BigInt(10 ** 18);

      await token.allocate("0x1234567890123456789012345678901111111111", amount1);
      await token.allocate("0x1234567890123456789012345678902222222222", 2n * amount1);
      await token.allocate("0x1234567890123456789012345678903333333333", 3n * amount1);

      expect(await token.balanceOf("0x1234567890123456789012345678901111111111")).to.equal(amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678902222222222")).to.equal(2n * amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678903333333333")).to.equal(3n * amount1);
    });

    it('Owner cannot transfer to himself', async function() {
      const token = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      const ownerAmount = 250_000n * BigInt(10 ** 18);

      const transfer = 20n * BigInt(10 ** 18);
      expect(await token.transfer(owner.address, transfer)).to.be.revertedWith('No no');
    });

    it('Cannot allocate more than available', async function() {
      const token = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      const cap = await token.cap();
      const ownerBalance = await token.balanceOf(owner.address);

      await expect(token.allocate("0x1234567890123456789012345678901234567890", cap)).to.be.revertedWithCustomError(token, "ERC20ExceededCap");
      await expect(token.allocate("0x1234567890123456789012345678901234567890", cap -  ownerBalance + 1n)).to.be.revertedWithCustomError(token, "ERC20ExceededCap");

      await token.allocate("0x1234567890123456789012345678901234567890", cap -  ownerBalance);
      const newBalance = await token.balanceOf("0x1234567890123456789012345678901234567890");

      expect(newBalance + ownerBalance).to.equal(cap);
      await expect(token.allocate("0x1234567890123456789012345678901234567890", 1n)).to.be.revertedWithCustomError(token, "ERC20ExceededCap");
    });

    it('Approve and Allowance work as expeced', async function() {
      const token = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();
  
      const newBalance = 2_500n * BigInt(10 ** 18);
      await token.allocate(spender.address, newBalance);
  
      await token.connect(spender).approve(owner, newBalance / 2n);
      const allowance = await token.allowance(spender, owner);
  
      expect(allowance).to.equal(newBalance / 2n);
      await token.connect(owner).transferFrom(spender, "0x1234567890123456789012345678901234567890", newBalance / 4n);
      const balance90 = await token.balanceOf("0x1234567890123456789012345678901234567890");
  
      expect(balance90).to.equal(newBalance / 4n);
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", newBalance)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", newBalance / 2n)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
  
      await token.connect(spender).approve(owner, newBalance);
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", 3n * newBalance / 4n + 1n)).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
    });
  });