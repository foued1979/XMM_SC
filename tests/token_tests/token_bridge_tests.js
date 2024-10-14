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

describe("Test bridge functions", function() {
  it('Can add valid chainId for bridge', async function() {
    const token = await loadFixture(_deploy);
    await token.addValidChainId(31337);

    expect((await token.getValidChainIds())[0]).to.equal(31337);
  });

  it('Can add pending bridge Out', async function() {
    const token = await loadFixture(_deploy);
    const [ owner, spender ] = await ethers.getSigners();

    await expect(token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.be.revertedWith("Chain err");
    await token.addValidChainId(31337);
    await expect(token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.be.revertedWith("Insufficient balance");

    token.connect(owner).allocate(spender, 500n * BigInt(10 ** 18));
    var spenderBalance = await token.balanceOf(spender);

    expect(await token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.emit("BridgeOutRequested");
    expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));

    var bridgeOut = await token.getPendingBridgesOut();
    expect(bridgeOut.length).to.equal(1);

    var pendingBridgeOut = await token.getPendingBridgesOutForUser(spender.address);
    expect(pendingBridgeOut[0][0]).to.equal(31337);
    expect(pendingBridgeOut[0][1]).to.equal(150n * BigInt(10 ** 18));

    await token.connect(spender).requestBridgeOut(31337, 200n * BigInt(10 ** 18))
    expect(await token.balanceOf(spender)).to.equal(150n * BigInt(10 ** 18));

    pendingBridgeOut = await token.getPendingBridgesOutForUser(spender.address);
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0][0]).to.equal(31337);
    expect(pendingBridgeOut[0][1]).to.equal(350n * BigInt(10 ** 18));
  });
});