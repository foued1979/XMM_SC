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

describe('Test base token functions', function () {
    it('Allocation is done properly and is reflected in AllocatedAmount', async function () {
      const [ owner, token ] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 100n * BigInt(10 ** 18);
      await expect(token.allocate("0x1234567890123456789012345678901234567890", amount1)).to.emit(token, 'Allocated');

      const amount2 = 50n * BigInt(10 ** 18);
      await token.allocate("0x1234567890123456789012345678901233458793", amount2);

      expect(await token.balanceOf("0x1234567890123456789012345678901234567890")).to.equal(amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678901233458793")).to.equal(amount2);
      expect(await token.AllocatedAmount()).to.equal(ownerAmount + amount1 + amount2);
    });

    it('Owner cannot transfer to himself', async function() {
      const [ owner, token ] = await loadFixture(_deploy);

      const ownerAmount = 250_000n * BigInt(10 ** 18);

      const transfer = 20n * BigInt(10 ** 18);
      expect(await token.transfer(owner.address, transfer)).to.be.revertedWith('No no');
    });

    it('Cannot allocate more than available', async function() {

      const [ owner, token ] = await loadFixture(_deploy);

      const totalSupply = await token.totalSupply();
      const ownerBalance = await token.balanceOf(owner.address);

      await expect(token.allocate("0x1234567890123456789012345678901234567890", totalSupply)).to.be.revertedWith("Insufficient supply");
      await expect(token.allocate("0x1234567890123456789012345678901234567890", totalSupply -  ownerBalance + 1n)).to.be.revertedWith("Insufficient supply");

      await token.allocate("0x1234567890123456789012345678901234567890", totalSupply -  ownerBalance);
      const newBalance = await token.balanceOf("0x1234567890123456789012345678901234567890");

      expect(newBalance + ownerBalance).to.equal(totalSupply);
      await expect(token.allocate("0x1234567890123456789012345678901234567890", 1n)).to.be.revertedWith("Insufficient supply");
    });

    it('Burn is working properly', async function() {
      const [ owner, token ] = await loadFixture(_deploy);
      const totalSupply = await token.totalSupply();

      await expect(token.burn(totalSupply)).to.be.revertedWith("Burn failed");
      const burntAmt = 250_000n * BigInt(10 ** 18);
      await expect(token.burn(burntAmt)).to.emit(token, 'Burnt');

      const newTotalSupply = await token.totalSupply();
      expect(newTotalSupply).to.equal(totalSupply - burntAmt);

      await token.allocate("0x1234567890123456789012345678901234567890", burntAmt);
      await expect(token.burn(newTotalSupply - burntAmt)).to.be.revertedWith("Burn failed");
    });

    it('Approve and Allowance work as expeced', async function() {
        const [ owner, token ] = await loadFixture(_deploy);
        const [ owner1, spender1 ] = await ethers.getSigners();
  
        const newBalance = 2_500n * BigInt(10 ** 18);
        await token.allocate(spender1.address, newBalance);
  
        await token.connect(spender1).approve(owner, newBalance / 2n);
        const allowance = await token.allowance(spender1, owner1);
  
        expect(allowance).to.equal(newBalance / 2n);
        await token.connect(owner).transferFrom(spender1, "0x1234567890123456789012345678901234567890", newBalance / 4n);
        const balance90 = await token.balanceOf("0x1234567890123456789012345678901234567890");
  
        expect(balance90).to.equal(newBalance / 4n);
        await expect(token.transferFrom(spender1, "0x1234567890123456789012345678901234567890", newBalance)).to.be.revertedWith("Insufficient allowance");
        await expect(token.transferFrom(spender1, "0x1234567890123456789012345678901234567890", newBalance / 2n)).to.be.revertedWith("Insufficient allowance");
  
        await token.connect(spender1).approve(owner, newBalance);
        await expect(token.transferFrom(spender1, "0x1234567890123456789012345678901234567890", 3n * newBalance / 4n + 1n)).to.be.revertedWith("Insufficient funds");
    });

    it('Exchange functions work properly for Coin', async function() {
        const [ owner, token ] = await loadFixture(_deploy);

        await expect(token.getExchangeRate("0x1234567890123456789012345678901234567890")).to.be.revertedWith("Not approved");

        await token.addApprovedToken("0x1234567890123456789012345678901234567890");
        var [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeRate("0x1234567890123456789012345678901234567890");

        expect(exchangeIsAllowed).to.equal(false);
        expect(exchangeRate).to.equal(0);

        var approvedTokens = await token.getApprovedTokens();
        expect(approvedTokens.length).to.equal(1);
        expect(approvedTokens[0]).to.equal("0x1234567890123456789012345678901234567890");

        await token.updateTokenExchangeRate("0x1234567890123456789012345678901234567890", 1_500_000);
        [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeRate("0x1234567890123456789012345678901234567890");

        expect(exchangeIsAllowed).to.equal(true);
        expect(exchangeRate).to.equal(1_500_000);

        await token.removeExchangeAuthorization("0x1234567890123456789012345678901234567890");

        [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeRate("0x1234567890123456789012345678901234567890");

        expect(exchangeIsAllowed).to.equal(false);
    });
  });