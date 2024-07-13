const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time } =  require("@nomicfoundation/hardhat-network-helpers");

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
  
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 0, 2 ** 32);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 2, 2 ** 32);
    await manager.createXMMPool('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', 18, 4, 2 ** 32);
    const pools = await manager.getXMMPools('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000');
    
    var poolAddress = pools[0];
    const xmmPool1 = await ethers.getContractAt("XMMPool", poolAddress);

    poolAddress = pools[2];
    const xmmPool2 = await ethers.getContractAt("XMMPool", poolAddress);

    poolAddress = pools[4];
    const xmmPool3 = await ethers.getContractAt("XMMPool", poolAddress);
    
    return [ manager, xmmPool1, xmmPool2, xmmPool3 ];
  }

  describe('Test adding fixing', function () {
    it('First fixings should activate only the created pools', async function() {
      const [ manager, xmmPool1, xmmPool2, xmmPool3 ] = await loadFixture(getXmmPools);

      const firstFixings = {
        "timestamp": 1_720_504_800,
        "spot": 180_388_626_432_000,
        "strikes": [179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800 ],
        "volatilities": [ 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774 ],
        "premia": [ 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296 ]
      };

      await manager.setFirstFixings('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', firstFixings.spot, firstFixings.strikes, firstFixings.volatilities, firstFixings.premia);

      expect((await xmmPool1.getFixings()).length).to.equal(1);
      expect(await xmmPool1.IsActivated()).to.equal(true);
    });

    it('ON Pool should have additional fixing with proper timestamp', async function () {
      const [ manager, xmmPool1, xmmPool2, xmmPool3 ] = await loadFixture(getXmmPools);

      const firstFixings = {
        "timestamp": 1_720_504_800,
        "spot": 180_388_626_432_000,
        "strikes": [179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800 ],
        "volatilities": [ 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774 ],
        "premia": [ 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296 ]
      };

      await manager.setFirstFixings('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000', firstFixings.spot, firstFixings.strikes, firstFixings.volatilities, firstFixings.premia);

      const strikes = [ 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800, 179_529_632_972_800 ];
      const vols = [ 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774, 1_868_310_774 ];
      const premia = [ 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296, 4_294_967_296 ];

      await time.increase(3601);
      await manager.setFixings('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000',  181_462_368_256_000, strikes, vols, premia);
      
      await time.increase(3600);
      await manager.setFixings('0xaaaaaaaaaa0000000000aaaaaaaaaa0000000000',  181_422_368_256_000, strikes, vols, premia);

      const fixingsPool1 = await xmmPool1.getFixings();
      const fixingsPool2 = await xmmPool2.getFixings();

      expect(fixingsPool1.length).to.equal(3);
      expect(fixingsPool2.length).to.equal(2);

      expect(fixingsPool1[1].spot).to.equal(181_462_368_256_000);
      expect(fixingsPool2[1].spot).to.equal(181_422_368_256_000);
      expect(fixingsPool1[2].timestamp).to.equal(fixingsPool1[1].timestamp + 3_600n);
      expect(fixingsPool1[2].timestamp).to.equal(fixingsPool1[0].timestamp + 7_200n);
      expect(fixingsPool2[1].timestamp).to.equal(fixingsPool2[0].timestamp + 7_200n);
    });
  });