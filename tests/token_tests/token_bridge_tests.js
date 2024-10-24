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

    // User tries to request a bridge out -> error because chain id not validated
    await expect(token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.be.revertedWith("Chain err");
    await token.addValidChainId(31337);
    // User tries to request a bridge out -> error because uer doesn't have tokens
    await expect(token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.be.revertedWith("Insufficient balance");

    // We allocate tokens to user
    await token.connect(owner).allocate(spender, 500n * BigInt(10 ** 18));
    const allocatedAmt = await token.AllocatedAmount();

    // User requests a bridge out
    expect(await token.connect(spender).requestBridgeOut(31337, 150n * BigInt(10 ** 18))).to.emit("BridgeOutRequested");
    expect(await token.balanceOf(spender)).to.equal(350n * BigInt(10 ** 18));
    expect(await token.AllocatedAmount()).to.equal(allocatedAmt);

    // We check bridging info
    var pendingBridgeOut = await token.getPendingBridgesOut();
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0]).to.equal(spender.address);

    var bridgeOut = await token.getPendingBridgesOut();
    expect(bridgeOut.length).to.equal(1);

    var pendingBridgeOut = await token.getPendingBridgesOutForUser(spender.address);
    expect(pendingBridgeOut[0][0]).to.equal(31337);
    expect(pendingBridgeOut[0][1]).to.equal(150n * BigInt(10 ** 18));

    // We had 1 bridge out request to make sure that amount is properly added
    await token.connect(spender).requestBridgeOut(31337, 200n * BigInt(10 ** 18))
    expect(await token.balanceOf(spender)).to.equal(150n * BigInt(10 ** 18));

    // The spender address should not be added to the list of pending bridges out
    pendingBridgeOut = await token.getPendingBridgesOut();
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0]).to.equal(spender.address);

    pendingBridgeOut = await token.getPendingBridgesOutForUser(pendingBridgeOut[0]);
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0][0]).to.equal(31337);
    expect(pendingBridgeOut[0][1]).to.equal(350n * BigInt(10 ** 18));

    // We get the available amount of tokens
    const availableTokenBeforeBridge = await token.AvailableTokens();

    // We validate the bridge out
    expect(await token.validateBridgeOut(spender.address, 31337)).to.emit("BridgeOutValidated");
    expect(await token.AllocatedAmount()).to.equal(allocatedAmt - 350n * BigInt(10 ** 18));

    pendingBridgeOut = await token.getPendingBridgesOutForUser(spender.address);
    expect(pendingBridgeOut.length).to.equal(0);
    expect(await token.AvailableTokens()).to.equal(availableTokenBeforeBridge + 350n * BigInt(10 ** 18));
  });

  it('Can manage bridge requests from different users', async function() {
    const token = await loadFixture(_deploy);
    const [ owner, spender1, spender2 ] = await ethers.getSigners();

    await token.addValidChainId(31337);
    await token.allocate(spender1, 500n * BigInt(10 ** 18));
    await token.allocate(spender2, 500n * BigInt(10 ** 18));

    const availableTokens = await token.AvailableTokens();
    const allocatedAmt = await token.AllocatedAmount();

    await token.connect(spender1).requestBridgeOut(31337, 200n * BigInt(10 ** 18));
    await token.connect(spender2).requestBridgeOut(31337, 200n * BigInt(10 ** 18));
    expect(await token.balanceOf(spender2)).to.equal(300n * BigInt(10 ** 18));

    var pendingBridgeOut = await token.getPendingBridgesOut();
    expect(pendingBridgeOut.length).to.equal(2);
    expect(pendingBridgeOut[1]).to.equal(spender2.address);

    await token.validateBridgeOut(spender2.address, 31337);
    expect(await token.balanceOf(spender2.address)).to.equal(300n * BigInt(10 ** 18));
    expect(await token.AvailableTokens()).to.equal(availableTokens + 200n * BigInt(10 ** 18));
    expect(await token.AllocatedAmount()).to.equal(allocatedAmt - 200n * BigInt(10 ** 18));

    pendingBridgeOut = await token.getPendingBridgesOut();
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0]).to.equal(spender1.address);
  });

  it('Can revert bridge out request', async function() {
    const token = await loadFixture(_deploy);
    const [ owner, spender1, spender2 ] = await ethers.getSigners();

    await token.addValidChainId(31337);
    await token.allocate(spender1, 500n * BigInt(10 ** 18));
    await token.allocate(spender2, 500n * BigInt(10 ** 18));

    const availableTokens = await token.AvailableTokens();
    const allocatedAmt = await token.AllocatedAmount();

    await token.connect(spender1).requestBridgeOut(31337, 200n * BigInt(10 ** 18));
    await token.connect(spender2).requestBridgeOut(31337, 200n * BigInt(10 ** 18));

    expect(await token.revertBridgeOutRequestForUser(spender1.address, 31337)).to.emit("BridgeOutCancelled");
    expect(await token.balanceOf(spender1.address)).to.equal(500n * BigInt(10 ** 18));

    pendingBridgeOut = await token.getPendingBridgesOut();
    expect(pendingBridgeOut.length).to.equal(1);
    expect(pendingBridgeOut[0]).to.equal(spender2.address);
  });

  it('Can add bridge in requests', async function() {
    throw console.error();
  });
});