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
  const token = await contractFactory.deploy("TEST", "0x1234567890123456789012345678901234500000", "0x1234567890123456789012345678901234500001", "Test token", 5_000_000, 250_000);

  return [owner, token, spender];
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
    it('Can bridge as expected', async function () {
        const [ owner, token, spender ] = await loadFixture(_deploy);

        expect (await token.getCCIPAdmin()).to.equal(owner);
        await expect(token.connect(spender).allowlistDestinationChain(151, true)).to.be.rejectedWith("Err0");

        await token.allowlistDestinationChain(151, true);
        expect (await token.connect(spender).isChainIdAllowed(151)).to.equal(true);
        expect (await token.connect(spender).isChainIdAllowed(150)).to.equal(false);

        await token.allowlistDestinationChain(151, false);
        expect (await token.connect(spender).isChainIdAllowed(151)).to.equal(false);
    });
});