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

describe('Test ERC20 methods', function () {
  it('Should deploy, have right parameters', async function () {
    const [ owner, token ] = await loadFixture(_deploy);

    expect(await token.Owner()).to.equal(owner);
    expect(await token.Symbol()).to.equal("TEST");
    expect(await token.balanceOf(owner)).to.equal(250_000n * decimalAdjustment);
    expect(await token.totalSupply()).to.equal(5_000_000n * decimalAdjustment);
  });

  it('Should properly transfer tokens', async function() {
    const [ owner, token ] = await loadFixture(_deploy);

    var success = await token.transfer("0x1234567890123456789012345678901234567890", 100n * decimalAdjustment);
    expect(await token.balanceOf(owner)).to.equal(249_900n * decimalAdjustment);
  });

  it('Should not allow transfer if amount exceeds balance', async function() {
    const [ owner, token ] = await loadFixture(_deploy);

    expect(await token.transfer("0x1234567890123456789012345678901234567890", 250_000n * decimalAdjustment + 1n)).to.be.revertedWith("Transfer err");
  });

  it('Should properly manage allowance', async function() {
    const [ owner, token ] = await loadFixture(_deploy);
    // We need to use spender address so that Hardhat can manage signature
    const [ o, spender ] = await ethers.getSigners();

    await token.approve(spender, 1_000n * BigInt(10 ** 18));
    expect(await token.allowance(owner, spender)).to.equal(1_000n * decimalAdjustment);

    await token.connect(spender).transferFrom(owner, spender, 550n * decimalAdjustment);

    expect(await token.balanceOf(owner)).to.equal((250_000n - 550n) * decimalAdjustment);
    expect(await token.balanceOf(spender)).to.equal(550n * decimalAdjustment);
    expect(await token.allowance(owner, spender)).to.equal(450n * decimalAdjustment);
  });

  it('Should properly reject transferFrom if above allowance', async function() {
    const [ owner, token ] = await loadFixture(_deploy);
    // We need to use spender address so that Hardhat can manage signature
    const [ o, spender ] = await ethers.getSigners();

    await token.approve(spender, 500n * decimalAdjustment);
    await expect(token.connect(spender).transferFrom(owner, spender, 501n * decimalAdjustment)).to.be.revertedWith("Insufficient allowance");
  });
});

describe('Test token', function () {
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
      await token.burn(burntAmt);

      const newTotalSupply = await token.totalSupply();
      expect(newTotalSupply).to.equal(totalSupply - burntAmt);

      await token.allocate("0x1234567890123456789012345678901234567890", burntAmt);
      await expect(token.burn(newTotalSupply - burntAmt)).to.be.revertedWith("Burn failed");
    });
  });

  describe('Test allowances', function() {
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
  });

  describe('Test payable functions', function() {
    function abs(x) {
      return x < 0 ? -x : x;
    }

    it('Deposit is working properly', async function() {
      const [ owner, token ] = await loadFixture(_deploy);
      const [ owner1, spender1 ] = await ethers.getSigners();

      var eth = ethers.parseEther("0.5");
      const prevETHBalance = await ethers.provider.getBalance(spender1.address);

      await expect(token.connect(spender1).depositEther({ value: eth })).to.be.revertedWith('Not allowed');
      await token.setETHDepositExchangeRate(30_000_000);

      // Now we can transfer
      await token.connect(spender1).depositEther({ value: eth })
      expect(await token.getAvailableQuantityOfETH()).to.equal(500_000_000_000_000_000n);
      expect(await token.balanceOf(spender1)).to.equal(1_500_000_000_000_000_000_000n);

      const newETHBalance = await ethers.provider.getBalance(spender1.address);
      const estimatedETHBalance = prevETHBalance - eth;
      expect(abs((newETHBalance - estimatedETHBalance) * 1000n / estimatedETHBalance)).to.be.lessThanOrEqual(10);
    });

    it ('Sell-back is working properly', async function() {
      const [ owner, token ] = await loadFixture(_deploy);
      const [ owner1, spender1 ] = await ethers.getSigners();

      var eth = ethers.parseEther("0.5");
      await token.setETHDepositExchangeRate(30_000_000);
      const prevETHBalance = await ethers.provider.getBalance(spender1.address);

      await token.connect(spender1).depositEther({ value: eth });
      
      await expect(token.sellBack(1_500_000_000_000_000_000_001n)).to.be.revertedWith("Not allowed");
      await token.connect(owner).updateETHExchangeRate(30_000_000);
      await expect(token.connect(spender1).sellBack(1_500_000_000_000_000_000_001n)).to.be.revertedWith("Insufficient balance");

      await token.connect(spender1).sellBack(750_000_000_000_000_000_000n);
      expect(await token.balanceOf(spender1)).to.equal(750_000_000_000_000_000_000n);
      expect(await token.getAvailableQuantityOfETH()).to.equal(250_000_000_000_000_000n);

      const newETHBalance = await ethers.provider.getBalance(spender1.address);
      eth = ethers.parseEther("0.25");

      const estimatedETHBalance = prevETHBalance - eth;
      expect(abs((newETHBalance - estimatedETHBalance) * 1000n / estimatedETHBalance)).to.be.lessThanOrEqual(10);
    });

    it ('Deposit is limited to available tokens', async function() {
      const [ owner, token ] = await loadFixture(_deploy);
      const [ owner1, spender1 ] = await ethers.getSigners();

      var eth = ethers.parseEther("2500");
      await token.setETHDepositExchangeRate(30_000_000);
      const prevETHBalance = await ethers.provider.getBalance(spender1.address);

      await token.connect(spender1).depositEther({ value: eth });

      var spenderBalance = await token.balanceOf(spender1);
      expect(spenderBalance).to.equal(await token.totalSupply() - await token.balanceOf(owner.address));

      const newETHBalance = await ethers.provider.getBalance(spender1.address);
      const estimatedETHBalance = prevETHBalance - spenderBalance / 3000n;
      
      expect(abs((estimatedETHBalance - newETHBalance) * 1000n / newETHBalance)).to.be.lessThanOrEqual(10);
    });

    it ('Cannot sell back more than available', async function() {
      const [ owner, token ] = await loadFixture(_deploy);
      const [ owner1, spender1 ] = await ethers.getSigners();

      var eth = ethers.parseEther("0.5");
      await token.setETHDepositExchangeRate(30_000_000);
      await token.updateETHExchangeRate(30_000_000);
      const prevETHBalance = await ethers.provider.getBalance(spender1.address);

      await token.connect(spender1).depositEther({ value: eth });
      await token.allocate(spender1.address, 1_500_000_000_000_000_000_000n);

      await token.connect(spender1).sellBack(1_750_000_000_000_000_000_000n);

      expect(await token.balanceOf(spender1)).to.equal(1_500_000_000_000_000_000_000n);
      expect(await token.getAvailableQuantityOfETH()).to.equal(0n);

      const newETHBalance = await ethers.provider.getBalance(spender1.address);
      expect(abs((newETHBalance - prevETHBalance) * 1000n / prevETHBalance)).to.be.lessThanOrEqual(10);
    });
  });