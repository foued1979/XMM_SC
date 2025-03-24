const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const ratePrecision = 10_000n;

async function _deploy() {
  const [owner, spender, ccipAdmin] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("OneXMM");
  // Initial supply is 5 mios
  // Allocation to owner is 250k
  const token = await contractFactory.deploy("TEST", "Test token", 5_000_000, 250_000);

  return [owner, token, spender, ccipAdmin];
}

function findEventArgs(logs, eventName) {
    let _event = null;
  
    for (const event of logs) {
      if (event.fragment && event.fragment.name === eventName) {
        _event = event.args;
      }
    }
    return _event
}

  describe('Test bridge functions', function () {
    it('can bridge as expected', async function () {
        const [ owner, token, spender, ccipAdmin ] = await loadFixture(_deploy);
        await token.setCCIPAdmin(ccipAdmin);

        expect (await token.getCCIPAdmin()).to.equal(ccipAdmin);
        await expect(token.connect(spender).allowlistDestinationChain(151, true)).to.be.rejectedWith("Err0");

        await token.allowlistDestinationChain(151, true);
        expect (await token.connect(spender).isChainIdAllowed(151)).to.equal(true);
        expect (await token.connect(spender).isChainIdAllowed(150)).to.equal(false);

        await token.allowlistDestinationChain(151, false);
        expect (await token.connect(spender).isChainIdAllowed(151)).to.equal(false);
    });

    it('CCIPAdmin can mint and burn as expected', async function() {
      const [ owner, token, spender, ccipAdmin ] = await loadFixture(_deploy);
      const burnMint = 250_000n * BigInt(10 ** 18);
      const initCap = await token.cap();

      await expect(token.connect(ccipAdmin).mint(spender, burnMint)).to.be.revertedWith("Denied");
      // At this stage, ccipAdmin is not set
      await expect(token.connect(ccipAdmin).burn(burnMint)).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");

      // Now we sent ccipAdmin
      await token.setCCIPAdmin(ccipAdmin);
      await expect(token.connect(ccipAdmin).burn(burnMint)).to.emit(token, 'Burnt');
      await expect(token.mint(spender, burnMint)).to.be.revertedWith("Denied");
      await expect(token.connect(ccipAdmin).mint(spender, burnMint)).to.emit(token, 'Minted');

      const totalSupply = await token.totalSupply();
      expect(totalSupply).to.equal(2n * burnMint);
      expect(await token.balanceOf(spender)).to.equal(burnMint);
      expect(await token.cap()).to.equal(initCap);
    });

    it('CCIPAdmin can burnFrom and mint as expected', async function() {
      const [ owner, token, spender, ccipAdmin ] = await loadFixture(_deploy);
      const burnMint = 250_000n * BigInt(10 ** 18);
      const initCap = await token.cap();

      await token.setCCIPAdmin(ccipAdmin);

      // First we test the allowance
      await expect(token.connect(ccipAdmin).burnFrom(spender, burnMint)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      await token.connect(spender).approve(ccipAdmin, burnMint); // spender approves, but he has no balance

      await expect(token.connect(ccipAdmin).burnFrom(spender, burnMint)).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");

      await token.allocate(spender, burnMint);
      await expect(token.connect(ccipAdmin).burnFrom(spender, burnMint)).to.emit(token, 'Burnt');
      expect(await token.cap()).to.equal(initCap - burnMint);
      expect(await token.balanceOf(spender)).to.equal(0n);

      await expect(token.connect(ccipAdmin).mint(spender, burnMint)).to.emit(token, 'Minted');

      const totalSupply = await token.totalSupply();
      expect(totalSupply).to.equal(2n * burnMint);
      expect(await token.balanceOf(spender)).to.equal(burnMint);
      expect(await token.cap()).to.equal(initCap);
    });
});