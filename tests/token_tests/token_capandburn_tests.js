const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const [owner, spender] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  const token = await contractFactory.deploy("TEST", "Test token", 5_000_000, 250_000);

  return [owner, token, spender];
}

describe('Test cap and burn token functions', function () {
    it('Can manage cap properly', async function () {
      const [owner, token] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const cap = 5_000_000n * BigInt(10 ** 18);
      const amount1 = 100n * BigInt(10 ** 18);

      await expect(token.allocate("0x1234567890123456789012345678901234567890", amount1)).to.emit(token, 'Allocated');

      expect(await token.totalSupply()).to.equal(ownerAmount + amount1);
      expect(await token.cap()).to.equal(cap);

      await token.transfer("0x1234567890123456789012345678901234567893", amount1);

      expect(await token.balanceOf("0x1234567890123456789012345678901234567890")).to.equal(amount1);
      expect(await token.balanceOf("0x1234567890123456789012345678901234567893")).to.equal(amount1);
      expect(await token.balanceOf(owner)).to.equal(ownerAmount - amount1);

      // supply and cap have not changed
      expect(await token.totalSupply()).to.equal(ownerAmount + amount1);
      expect(await token.cap()).to.equal(cap);

      await expect(token.allocate("0x1234567890123456789012345678901234567893", await token.availableTokens() + 1n)).to.revertedWithCustomError(token, "ERC20ExceededCap");
    });

    it('Can burn user\'s tokens properly', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 10_000n * BigInt(10 ** 18);
      const burnAmount = 1_000n * BigInt(10 ** 18);

      await token.allocate(spender, amount1);
      
      expect(await token.totalSupply()).to.equal(ownerAmount + amount1);
      expect(await token.connect(spender).burn(burnAmount)).to.emit(token, "Burnt");

      expect(await token.balanceOf(spender)).to.equal(amount1 - burnAmount);
      expect(await token.totalSupply()).to.equal(ownerAmount + amount1 - burnAmount);
      expect(await token.cap()).to.equal(5_000_000n * BigInt(10 ** 18) - burnAmount);

      await expect(token.connect(spender).burn(amount1)).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
    });

    it('Can burn non-allocated tokens properly', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const initialCap = await token.cap();
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 10_000n * BigInt(10 ** 18);
      const burnAmount = 10_000n * BigInt(10 ** 18);

      await token.allocate(spender, amount1);
      expect(await token.burn(burnAmount)).to.emit(token, "Burnt");

      expect(await token.cap()).to.equal(initialCap - burnAmount);
      expect(await token.totalSupply()).to.equal(ownerAmount + amount1);
      expect(await token.availableTokens()).to.equal(initialCap - (burnAmount + ownerAmount + amount1));

      await expect(token.burn(await token.availableTokens() + 1n)).to.be.revertedWith("Burn err");
    });

  it('Can burn and allocate', async function() {
    const [owner, token, spender] = await loadFixture(_deploy);

    const burntAmt = 250_000n * BigInt(10 ** 18);
    const initCap = await token.cap();
    expect (initCap).to.equal(5_000_000n * BigInt(10 ** 18));

    await expect(token.burn(burntAmt)).to.emit(token, 'Burnt');

    const newCap = await token.cap(); // new cap is 4.75mios
    expect(newCap).to.equal(initCap - burntAmt);

    const totalSupply = await token.totalSupply();
    expect (totalSupply).to.equal(250_000n * BigInt(10 ** 18));

    await expect(token.allocate(spender, newCap - totalSupply + 1n)).to.be.revertedWithCustomError(token, 'ERC20ExceededCap');
    await expect(token.allocate(spender, initCap - totalSupply)).to.be.revertedWithCustomError(token, 'ERC20ExceededCap');
    await expect(token.allocate(spender, newCap - totalSupply)).to.emit(token, 'Allocated');

    expect(await token.totalSupply()).to.equal(initCap - burntAmt);
  });

  it('Cannot burn more than available tokens', async function() {
    const [owner, token] = await loadFixture(_deploy);
          
    const initCap = await token.cap();
    const ownerAmount = 250_000n * BigInt(10 ** 18);
    
    await expect(token.burn(initCap)).to.be.revertedWith("Burn err");
    const burntAmt = 250_000n * BigInt(10 ** 18);
    await expect(token.burn(burntAmt)).to.emit(token, 'Burnt');
    
    const newCap = await token.cap();
    expect(newCap).to.equal(initCap - burntAmt);
    
    await token.allocate("0x1234567890123456789012345678901234567890", burntAmt);
    expect(await token.totalSupply()).to.equal(ownerAmount + burntAmt);
    await expect(token.burn(newCap - burntAmt)).to.be.revertedWith("Burn err");
  });

  it ('Can burn from another account', async function() {
    const [owner, token, spender] = await loadFixture(_deploy);

    const amt1 = 2_000n * BigInt(10 ** 18);
    await token.allocate(spender, amt1);
    const initCap = await token.cap();

    await expect(token.burnFrom(spender, amt1 / 2n)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
    expect(await token.cap()).to.equal(initCap);
    await token.connect(spender).approve(owner, amt1);

    expect(await token.burnFrom(spender, amt1 / 2n)).to.emit("Burnt");
    expect(await token.balanceOf(spender)).to.equal(amt1 / 2n);
  })

  it ('Can burn from ourselves', async function() {
    const [owner, token, spender] = await loadFixture(_deploy);

    const amt1 = 2_000n * BigInt(10 ** 18);
    await token.allocate(spender, amt1);

    await expect(token.connect(spender).getFunction("burn(address,uint256)")(spender, amt1)).to.emit(token, "Burnt");
    expect(await token.balanceOf(spender)).to.equal(0n);
  });
});