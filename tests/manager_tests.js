const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

async function _deploy() {
  const [owner] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("Manager");
  const manager = await contractFactory.deploy(owner.address);

  return { owner, manager };
}

describe('Test pools creation', function () {
  it('Should deploy, have right owner and 1 pool for 2 tokens', async function () {
    const { owner, manager } = await loadFixture(_deploy);

    const firstFixing = {
      "timestamp": 1_720_504_800,
      "spot": 180_388_626_432_000,
      "strike": 179_529_632_972_800,
      "volatility": 1_868_310_774,
      "premium": 4_294_967_296
    };
  
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000bbbbbbbbbb0000000000', 18, 1, 2 ** 32, firstFixing);
  
    const poolsToken1 = await manager.getXMMPools('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
    const poolsToken2 = await manager.getXMMPools('0xaaaaaaaaaa0000000000bbbbbbbbbb0000000000');
    const registeredTokens = await manager.getRegisteredTokens();

    expect(await manager.Owner()).to.equal(owner.address);
    expect(registeredTokens.length).to.equal(2);
    expect(poolsToken1[0]).to.not.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken2[0]).to.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken2[1]).to.not.equal('0x0000000000000000000000000000000000000000');
  });

  it('Should deploy, have 4 pools for 1 tokens', async function () {
    const { owner, manager } = await loadFixture(_deploy);

    const firstFixing = {
      "timestamp": 1_720_504_800,
      "spot": 180_388_626_432_000,
      "strike": 179_529_632_972_800,
      "volatility": 1_868_310_774,
      "premium": 4_294_967_296
    };
  
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 1, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 2, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 3, 2 ** 32, firstFixing);
  
    const poolsToken1 = await manager.getXMMPools('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
    const registeredTokens = await manager.getRegisteredTokens();

    expect(await manager.Owner()).to.equal(owner.address);
    expect(registeredTokens.length).to.equal(1);
    expect(poolsToken1[0]).to.not.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken1[1]).to.not.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken1[2]).to.not.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken1[3]).to.not.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken1[4]).to.equal('0x0000000000000000000000000000000000000000');
    expect(poolsToken1[5]).to.equal('0x0000000000000000000000000000000000000000');
  });

  it('Should deploy, and throw an error if 2 identical pools are created', async function () {
    const { owner, manager } = await loadFixture(_deploy);

    const firstFixing = {
      "timestamp": 1_720_504_800,
      "spot": 180_388_626_432_000,
      "strike": 179_529_632_972_800,
      "volatility": 1_868_310_774,
      "premium": 4_294_967_296
    };
  
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing);
    await expect(manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing)).to.be.revertedWith('xmm pool already exists');
  });
});