const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  return await contractFactory.deploy("TEST", "Test token", 5_000_000, 250_000);
}

async function _deployERC20() {
  const owner = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, 100_000, "COIN1", "COIN1", 18);
}

async function _deployERC20_6() {
  const owner = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("ERC677Allocatable");
  return await contractFactory.deploy(owner[0].address, 50_000, "COIN2", "COIN2", 6);
}

describe('Test exchangeable token functions', function () {
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
      const oAvailable = await token.availableTokens();
      expect(oAvailable).to.equal(initCap - (250_000n + 500n) * BigInt(10 ** 18));

      // There is no exchange rate yet
      await expect(token.getExchangeInfoForToken(approvedTokenAddress)).to.be.revertedWith("Err4");
      await expect(token.connect(spender).sellBackAgainst(150n * BigInt(10 ** 18), approvedTokenAddress)).to.be.rejectedWith("Err3");

      // We add an approved token for exchange
      // OnlyOwner can do it
      await expect(token.connect(spender).addApprovedToken(approvedTokenAddress, 18)).to.be.rejectedWith("Err0");
      await expect(token.addApprovedToken(approvedTokenAddress, 19)).to.be.rejectedWith("Err10");
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

      const newAvailable = await token.availableTokens();
      expect(newAvailable).to.equal(newCap - (250_000n + 350n) * BigInt(10 ** 18));

      // We make sure that we can remove exchange auth.
      // OnlyOwner can do it
      await expect(token.connect(spender).removeExchangeAuthorizationForToken(approvedTokenAddress)).to.be.rejectedWith("Err0");
      await expect(token.removeExchangeAuthorizationForToken("0x1234567890123456789012345678901234500002")).to.be.rejectedWith("Err4");
      await token.removeExchangeAuthorizationForToken(approvedTokenAddress);
      [ exchangeIsAllowed, exchangeRate ] = await token.getExchangeInfoForToken(approvedTokenAddress);
      expect(exchangeIsAllowed).to.be.false;
    });

    it('Exchanges only max amount of Coin available', async function() {
      const token = await loadFixture(_deploy);
      const tokenAddress = await token.getAddress()
      const [ owner, spender ] = await ethers.getSigners();

      const approvedToken = await loadFixture(_deployERC20);
      const approvedTokenAddress = await approvedToken.getAddress();

      const initCap = await token.cap();
      await token.addApprovedToken(approvedTokenAddress, 18);

      // We allocate some ERC20 to spender
      await token.allocate(spender, 2_500n * BigInt(10 ** 18))

      // We allocate some ERC20 to token
      await approvedToken.allocate(tokenAddress, 150n * BigInt(10 ** 18));
      expect(await approvedToken.balanceOf(tokenAddress)).to.equal(150n * BigInt(10 ** 18));
      
      await token.updateTokenExchangeRate(approvedTokenAddress, 10n * ratePrecision);
      
      // IF spender changes 2,000 tokens, the available amount of approved token will be reached
      // Spender will receive only 150 approved tokens and spender's balance will be 1,000 tokens
      expect(await token.connect(spender).sellBackAgainst(2_000n * BigInt(10 ** 18), approvedTokenAddress)).to.emit("Burnt").to.emit("Withdrawn");
      const newBalance = await token.balanceOf(spender);
      
      expect(newBalance).to.equal(1_000n * BigInt(10 ** 18));

      // Then we test if the exchange authorization can be removed
      // OnlyOwner can do it
      await expect(token.connect(spender).removeExchangeAuthorizationForToken(approvedTokenAddress)).to.be.rejectedWith("Err0");
      await token.removeExchangeAuthorizationForToken(approvedTokenAddress);
      const tokenInfo = await token.getExchangeInfoForToken(approvedTokenAddress);
      expect(tokenInfo[0]).to.equal(false);
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
      await expect(token.connect(spender).updateTokenExchangeRate(approvedTokenAddress, 150n * ratePrecision)).to.be.rejectedWith("Err0");
      await expect(token.updateTokenExchangeRate("0x1234567890123456789012345678901234500002", 150n * ratePrecision)).to.be.rejectedWith("Err4");
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

    it('Can sell back against ETH', async function() {
      const token  = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("2")
      });

      const ethBalance = await ethers.provider.getBalance(await token.getAddress());
      expect(ethBalance).to.equal(ethers.parseEther("2"));

      await expect(token.connect(spender).sellBack(150n * BigInt(10 ** 18))).to.be.revertedWith("Err2");

      var ethExchangeRate = await token.EthExchangeRate();
      expect(ethExchangeRate).to.equal(0);

      // We update the exchange
      // OnlyOwner can do it
      await expect(token.connect(spender).updateETHExchangeRate(3_000n * ratePrecision)).to.be.rejectedWith("Err0");
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
      
      const estimatedBalance = 1000005n * BigInt(10 ** 16) - (10n * receipt.gasUsed * receipt.gasPrice);
      expect(await ethers.provider.getBalance(spender.address)).to.above(estimatedBalance);
      expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal(totalSupply - 150n * BigInt(10 ** 18));

      const newCap = await token.cap();
      expect(newCap).to.equal(initCap - 150n * BigInt(10 ** 18));
      expect(await token.availableTokens()).to.equal(newCap - await token.totalSupply());

      // Then we test if the exchange authorization can be removed
      // OnlyOwner can do it
      await expect(token.connect(spender).removeETHExchangeAuthorization()).to.be.rejectedWith("Err0");
      await token.removeETHExchangeAuthorization();
      expect(await token.ETHExchangeIsAllowed()).to.equal(false);
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
      await expect(token.buyBack("0x0000000000000000000000000000000000000000", 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.be.revertedWithCustomError(token, "ERC20InvalidReceiver");
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

      // Should error: no ETH on the Token contract
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.revertedWith("BBack err");

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("0.5")
      });

      const spenderInitETHBal = await ethers.provider.getBalance(spender);

      // Should error: no allowance provided to the owner
      await expect(token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      await token.connect(spender).approve(owner, 6_000n * BigInt(10 ** 18));

      // Now we are ok
      const tx = await token.buyBack(spender, 1_000n * BigInt(10 ** 18), 1_000n * ratePrecision);
      expect(tx).to.emit("ChangedBack");
      expect(tx).to.emit("Withdrawn");
      const receipt = await tx.wait();

      expect(await token.balanceOf(spender)).to.equal(1_000n * BigInt(10 ** 18));
      expect(await ethers.provider.getBalance(spender)).to.be.above(spenderInitETHBal + 5n * BigInt(10 ** 17) - receipt.gasUsed * receipt.gasPrice);
    });

    it('Can sell back tokens with limited ETH', async function () {
      const token  = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      await owner.sendTransaction({
        to: await token.getAddress(),
        value: ethers.parseEther("2")
      });
      
      const amt = 1_000n * BigInt(10 ** 18);
      await token.allocate(spender, amt);

      await token.updateETHExchangeRate(200n * ratePrecision);

      expect(await token.connect(spender).sellBack(amt)).to.emit("ChangedBack").to.emit("Burnt");
      expect(await token.balanceOf(spender)).to.equal(600n * BigInt(10 ** 18));
      expect(await token.totalSupply()).to.equal((250_000n + 600n) * BigInt(10 ** 18));
    });

    it('Can set ETH deposit rate and auth', async function () {
      const token  = await loadFixture(_deploy);
      const [ owner, spender ] = await ethers.getSigners();

      expect(await token.ETHDepositIsAllowed()).to.equal(false);
      await expect(token.connect(spender).setETHDepositExchangeRate(150 * 10_000)).to.revertedWith("Err0");

      await token.setETHDepositExchangeRate(150 * 10_000);
      expect(await token.ETHDepositIsAllowed()).to.equal(true);
      expect(await token.EthExchangeRate()).to.equal(150 * 10_000);

      await expect(token.connect(spender).removeETHDepositAuthorization()).to.revertedWith("Err0");
      await token.removeETHDepositAuthorization();
      expect(await token.ETHDepositIsAllowed()).to.equal(false);
    });
  });