const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('Test XMM manager and 1 pool creation', function () {
  async function _deploy() {
    const [owner] = await ethers.getSigners();

    const contractFactory = await ethers.getContractFactory("Manager");
    const manager = await contractFactory.deploy(owner);

    const firstFixing = {
      "timestamp": 1_720_504_800,
      "spot": 180_388_626_432_000,
      "strike": 179_529_632_972_800,
      "volatility": 1_868_310_774,
      "premium": 4_294_967_296
    };

    await manager.createXMMPool("0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000", 18, 0, 2 ** 32, firstFixing);
    const poolAddress = await manager.getXMMPools("0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000");
    return { owner, manager, poolAddress };
  }

  it('Should deploy, have right owner and 1 pool', async function () {
    const { owner, manager, poolAddress } = await loadFixture(_deploy);

    console.log(poolAddress);
    expect(await manager.Owner()).to.equal(owner.address);
  });
});