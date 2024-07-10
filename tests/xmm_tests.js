const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

async function getXmmPool() {
  const [owner] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("Manager");
  const manager = await contractFactory.deploy(owner.address);
  const managerAddress = await manager.getAddress();

  const firstFixing = {
    "timestamp": 1_720_504_800,
    "spot": 180_388_626_432_000,
    "strike": 179_529_632_972_800,
    "volatility": 1_868_310_774,
    "premium": 4_294_967_296
  };

  await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing);
  const pools = await manager.getXMMPools('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
  
  const poolAddress = pools[0];
  const xmmPool = await ethers.getContractAt("XMMPool", poolAddress);
  
  return [ managerAddress, xmmPool ];
}

describe('Test pool', function () {
    it('Should deploy, have right owner', async function () {
      const [ owner, xmmPool ] = await loadFixture(getXmmPool);
      
      expect(await xmmPool.Owner()).to.equal(owner);
    });

    it('Should deploy, have right term', async function () {
        const [ owner, xmmPool ] = await loadFixture(getXmmPool);
        
        expect(await xmmPool.getTerm()).to.equal(0);
      });

      it('Should deploy, have right token', async function () {
        const [ owner, xmmPool ] = await loadFixture(getXmmPool);
        
        expect((await xmmPool.Token()).toLowerCase()).to.be.equal('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
      });

      it('Should deploy, have right fixing', async function () {
        const [ owner, xmmPool ] = await loadFixture(getXmmPool);
        
        expect((await xmmPool.getFixings())[0].timestamp).to.equal(1_720_504_800);
      });
  });

  async function getXmmPools() {
    const [owner] = await ethers.getSigners();
  
    const contractFactory = await ethers.getContractFactory("Manager");
    const manager = await contractFactory.deploy(owner.address);
  
    const firstFixing = {
      "timestamp": 1_720_504_800,
      "spot": 180_388_626_432_000,
      "strike": 179_529_632_972_800,
      "volatility": 1_868_310_774,
      "premium": 4_294_967_296
    };
  
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 2, 2 ** 32, firstFixing);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 4, 2 ** 32, firstFixing);
    const pools = await manager.getXMMPools('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
    
    var poolAddress = pools[0];
    const xmmPool1 = await ethers.getContractAt("XMMPool", poolAddress);

    poolAddress = pools[2];
    const xmmPool2 = await ethers.getContractAt("XMMPool", poolAddress);

    poolAddress = pools[4];
    const xmmPool3 = await ethers.getContractAt("XMMPool", poolAddress);
    
    return [ xmmPool1, xmmPool2, xmmPool3 ];
  }

  describe('Test adding fixing', function () {
    it('ON Pool should have additional fixing with proper timestamp', async function () {
      const [ xmmPool1, xmmPool2, xmmPool3 ] = await loadFixture(getXmmPools);

      const firstFixing = {
        "timestamp": 1_720_504_800,
        "spot": 180_388_626_432_000,
        "strike": 179_529_632_972_800,
        "volatility": 1_868_310_774,
        "premium": 4_294_967_296
      };

      await xmmPool1.setFixing('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000',  181_462_368_256_000, 179_529_632_972_800, 1_868_310_774);
      const fixings = await xmmPool1.getFixings();

      console.log(fixings);
    });
  });