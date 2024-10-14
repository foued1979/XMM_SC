const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { boolean } = require('hardhat/internal/core/params/argumentTypes');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const contractFactory = await ethers.getContractFactory("Token");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  return await contractFactory.deploy("TEST", "Test token", 1, 5_000_000, 250_000);
}

async function _deployERC20() {
  const contractFactory = await ethers.getContractFactory("Allocatable");
  return await contractFactory.deploy("COIN", 10_000, 18);
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
      expect(await token.AllocatedAmount()).to.equal(ownerAmount + amount1 + amount2);
      expect(await token.AvailableTokens()).to.equal(5_000_000n * BigInt(10 ** 18) - (ownerAmount + amount1 + amount2));
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
      const token = await loadFixture(_deploy);
      
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
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", newBalance)).to.be.revertedWith("Insufficient allowance");
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", newBalance / 2n)).to.be.revertedWith("Insufficient allowance");
  
      await token.connect(spender).approve(owner, newBalance);
      await expect(token.transferFrom(spender, "0x1234567890123456789012345678901234567890", 3n * newBalance / 4n + 1n)).to.be.revertedWith("Insufficient funds");
    });

    it('Exchange functions work properly for Coin', async function() {
      const token = await loadFixture(_deploy);
      const tokenAddress = await token.getAddress()
      const [ owner, spender ] = await ethers.getSigners();

      const approvedToken = await loadFixture(_deployERC20);
      const approvedTokenAddress = await approvedToken.getAddress();

      // We allocate some ERC20 to token
      await approvedToken.allocate(tokenAddress, 1_500n * BigInt(10 ** 18));
      var balanceOfERC20 = await approvedToken.balanceOf(tokenAddress);
      expect(balanceOfERC20).to.equal(1_500n * BigInt(10 ** 18));

      // We allocate some tokens to spender
      await token.allocate(spender, 500n * BigInt(10 ** 18));
      const allocatedAmt = await token.AllocatedAmount();
      var availableTokens = await token.AvailableTokens();

      // There is no exchange rate yet
      await expect(token.getExchangeInfoForToken(approvedTokenAddress)).to.be.revertedWith("Not approved");

      // We add an approved token for exchange
      await token.addApprovedToken(approvedTokenAddress);

      // We cannot change yet
      var [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);
      expect(exchangeIsAllowed).to.be.false;
      expect(exchangeRate).to.equal(0);

      // Though the token is approved
      var approvedTokens = await token.getApprovedTokens();
      expect(approvedTokens.length).to.equal(1);
      expect(approvedTokens[0]).to.equal(approvedTokenAddress);

      // We update the exchange rate, which enables change
      await token.updateTokenExchangeRate(approvedTokenAddress, 150n * ratePrecision);
      [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);

      expect(exchangeIsAllowed).to.be.true;
      expect(exchangeRate).to.equal(1_500_000n);

      // We test the sellBack function
      await token.connect(spender).sellBackAgainst(150n * BigInt(10 ** 18), approvedTokenAddress);
      var balanceOfSpender = await approvedToken.balanceOf(spender);
      expect(balanceOfSpender).to.equal(1n * BigInt(10 ** 18));
      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.AllocatedAmount()).to.equal(allocatedAmt - 150n * BigInt(10 ** 18));
      expect(await token.AvailableTokens()).to.equal(availableTokens + 150n * BigInt(10 ** 18));

      // We make sure that we can remove exchange auth.
      await token.removeExchangeAuthorizationForToken(approvedTokenAddress);
      [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);
      expect(exchangeIsAllowed).to.be.false;
    });

    it('Exchange functions work properly for ETH', async function() {
      const token  = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("2")
      });

      const ethBalance = await ethers.provider.getBalance(await token.getAddress());
      expect(ethBalance).to.equal(ethers.parseEther("2"));

      var ethExchangeRate = await token.EthExchangeRate();
      expect(ethExchangeRate).to.equal(0);

      // We update the exchange
      await token.updateETHExchangeRate(3_000n * ratePrecision);
      ethExchangeRate = await token.EthExchangeRate();

      expect(ethExchangeRate).to.equal(30_000_000n)
      expect(await token.ETHExchangeIsAllowed()).to.be.true;

      // We allocate some tokens to spender
      await token.allocate(spender, 500n * BigInt(10 ** 18));
      expect(await token.balanceOf(spender)).to.equal(500n * BigInt(10 ** 18));
      const allocatedAmt = await token.AllocatedAmount();
      var availableTokens = await token.AvailableTokens();

      // We test the sellBack function
      await token.connect(spender).sellBack(150n * BigInt(10 ** 18));

      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.AllocatedAmount()).to.equal(allocatedAmt - 150n * BigInt(10 ** 18));
      expect(await token.AvailableTokens()).to.equal(availableTokens + 150n * BigInt(10 ** 18));
    });
  });