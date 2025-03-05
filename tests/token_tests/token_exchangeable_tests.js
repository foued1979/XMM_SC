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

describe('Test base token functions', function () {
    it('Exchange functions work properly for Coin', async function() {
      const token = await loadFixture(_deploy);
      const tokenAddress = await token.getAddress()
      const [ owner, spender ] = await ethers.getSigners();

      const approvedToken = await loadFixture(_deployERC20);
      const approvedTokenAddress = await approvedToken.getAddress();

      const initCap = await token.cap();

      // We allocate some ERC20 to token
      await approvedToken.allocate(tokenAddress, 1_500n * BigInt(10 ** 18));
      var balanceOfERC20 = await approvedToken.balanceOf(tokenAddress);
      expect(balanceOfERC20).to.equal(1_500n * BigInt(10 ** 18));

      // We allocate some tokens to spender
      const allocatedAmount = 500n * BigInt(10 ** 18);
      expect (await token.allocate(spender, allocatedAmount)).to.emit(token, "transfer");
      expect(await token.availableTokens()).to.equal(initCap - (250_000n + 500n) * BigInt(10 ** 18));

      // There is no exchange rate yet
      await expect(token.getExchangeInfoForToken(approvedTokenAddress)).to.be.revertedWith("Err4");

      // We add an approved token for exchange
      await token.addApprovedToken(approvedTokenAddress, 18);

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
      await expect(token.connect(spender).sellBackAgainst(150n * BigInt(10 ** 18), approvedTokenAddress)).to.emit(token, "Burnt");
      var balanceOfSpenderForApprovedToken = await approvedToken.balanceOf(spender);

      expect(balanceOfSpenderForApprovedToken).to.equal(1n * BigInt(10 ** 18));
      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal(allocatedAmount + (250_000n - 150n) * BigInt(10 ** 18));
      
      const newCap = await token.cap();
      expect(newCap).to.equal(initCap - 150n * BigInt(10 ** 18));
      expect(await token.availableTokens()).to.equal(newCap - (250_000n + 350n) * BigInt(10 ** 18));

      // We make sure that we can remove exchange auth.
      await token.removeExchangeAuthorizationForToken(approvedTokenAddress);
      [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);
      expect(exchangeIsAllowed).to.be.false;
    });

    it('Add approved token with 6 decimals is working', async function() {
      const decimals = 6;
      const token = await loadFixture(_deploy);
      const tokenAddress = await token.getAddress()
      const [ owner, spender ] = await ethers.getSigners();

      const approvedToken = await loadFixture(_deployERC20_6);
      const approvedTokenAddress = await approvedToken.getAddress();

      // We allocate some ERC20 to token
      await approvedToken.allocate(tokenAddress, 1_500n * BigInt(10 ** decimals));

      var balanceOfERC20 = await approvedToken.balanceOf(tokenAddress);
      expect(balanceOfERC20).to.equal(1_500n * BigInt(10 ** decimals));

      // We allocate some tokens to spender
      const allocatedAmount = 500n * BigInt(10 ** 18);
      await token.allocate(spender, allocatedAmount);

      const availableTokens = await token.availableTokens();
      const initCap = await token.cap();
      expect(availableTokens).to.equal(initCap - (250_000n + 500n) * BigInt(10 ** 18));

      // We add an approved token for exchange
      await token.addApprovedToken(approvedTokenAddress, decimals);

      // We update the exchange rate, which enables change
      await token.updateTokenExchangeRate(approvedTokenAddress, 150n * ratePrecision);
      [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);

      // We test the sellBack function
      const tx = await token.connect(spender).sellBackAgainst(150n * BigInt(10 ** 18), approvedTokenAddress);
      expect(tx).to.emit("ChangedBackFor");
      expect(tx).to.emit("Withdrawn");
      var balanceOfSpender = await approvedToken.balanceOf(spender);

      expect(balanceOfSpender).to.equal(1n * BigInt(10 ** decimals));
      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal((250_000n + 350n) * BigInt(10 ** 18));

      const newCap = await token.cap();
      expect(newCap).to.equal(initCap - 150n * BigInt(10 ** 18));
      expect(await token.availableTokens()).to.equal(newCap - (250_000n + 350n) * BigInt(10 ** 18));
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
      const availableTokens = await token.availableTokens();
      const initCap = await token.cap();
      const totalSupply = await token.totalSupply();

      // We test the sellBack function
      const tx = await token.connect(spender).sellBack(150n * BigInt(10 ** 18));
      expect(tx).to.emit("ChangedBack");
      expect(tx).to.emit("Withdrawn");
      var receipt = await tx.wait();

      expect(await ethers.provider.getBalance(spender.address)).to.equal(1000005n * BigInt(10 ** 16) - receipt.gasUsed * receipt.gasPrice);
      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal(totalSupply - 150n * BigInt(10 ** 18));

      const newCap = await token.cap();
      expect(newCap).to.equal(initCap - 150n * BigInt(10 ** 18));
      expect(await token.availableTokens()).to.equal(newCap - await token.totalSupply());
    });

    it('Can buy back tokens from user', async function () {
        const token  = await loadFixture(_deploy);
        const [ owner, spender ] = await ethers.getSigners();

        // We allocate some ERC20 to token
      await token.allocate(spender, 1_500n * BigInt(10 ** 18));

      const initSupply = await token.totalSupply();

      // Should error: no ETH on the Token contract
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.revertedWith("BBack err");

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("2")
      });

      const spenderInitETHBal = await ethers.provider.getBalance(spender);

      // Should error: no allowance provided to the owner
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      token.connect(spender).approve(owner, 1_000n * BigInt(10 ** 18));

      // Now we are ok
      const tx = await token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision);
      expect(tx).to.emit("ChangedBack");
      expect(tx).to.emit("Withdrawn");
      const receipt = await tx.wait();

      expect(await token.balanceOf(spender)).to.equal(500n * BigInt(10 ** 18));
      expect(await ethers.provider.getBalance(spender)).to.be.above(spenderInitETHBal + 1n * BigInt(10 ** 18) - receipt.gasUsed * receipt.gasPrice);
    });

    it('Can buy back tokens from user with limited ETH', async function () {
        const token  = await loadFixture(_deploy);
        const [ owner, spender ] = await ethers.getSigners();

        // We allocate some ERC20 to token
      await token.allocate(spender, 1_500n * BigInt(10 ** 18));

      const initSupply = await token.totalSupply();

      // Should error: no ETH on the Token contract
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.revertedWith("BBack err");

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("0.5")
      });

      const spenderInitETHBal = await ethers.provider.getBalance(spender);

      // Should error: no allowance provided to the owner
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      token.connect(spender).approve(owner, 1_000n * BigInt(10 ** 18));

      // Now we are ok
      const tx = await token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision);
      expect(tx).to.emit("ChangedBack");
      expect(tx).to.emit("Withdrawn");
      const receipt = await tx.wait();

      expect(await token.balanceOf(spender)).to.equal(1_000n * BigInt(10 ** 18));
      expect(await ethers.provider.getBalance(spender)).to.be.above(spenderInitETHBal + 5n * BigInt(10 ** 17) - receipt.gasUsed * receipt.gasPrice);
    });
  });