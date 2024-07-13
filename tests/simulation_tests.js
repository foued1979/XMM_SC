const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const minDeposit = 100 * (2 ** 32);

const firstFixing = {
    "timestamp": 1_720_504_800,
    "spot": 180_388_626_432_000,
    "strikes": [ 179_529_632_972_800, 0, 0, 0, 0, 0, 0 ],
    "volatilities": [ 1_868_310_774, 0, 0, 0, 0, 0, 0]
  };

async function createFakeERC20() {
    const contractFactory = await ethers.getContractFactory("Token");
    const token = await contractFactory.deploy("TST", "Test", 10_000_000, 250_000);
  
    return token;
};

async function createRef() {
    const [owner, spender] = await ethers.getSigners();
    const contractFactory = await ethers.getContractFactory("Manager");
    const manager = await contractFactory.deploy(owner.address);

    const token = await createFakeERC20();
    
    await manager.createXMMPool(token.getAddress(), (await token.Decimals()), 0, minDeposit);
    const poolsAddress = await manager.getXMMPools(token.getAddress())
    
    const pool = await ethers.getContractAt("XMMPool", poolsAddress[0]);

    return { owner, spender, manager, token, pool };
};
  
describe("Simulation tests", function() {
    it('Spender can deposit into XMMPool', async function() {
        const { owner, spender, manager, token, pool } = await loadFixture(createRef);
    
        await manager.setFirstFixings(token.getAddress(), firstFixing.spot, firstFixing.strikes, firstFixing.volatilities);
        const firstFix = (await pool.getFixings())[0];

        await token.allocate(spender.address, 1_500_000_000_000_000_000_000n);

        await expect(pool.connect(spender).deposit(0, 90_000_000_000_000_000_000n)).to.be.revertedWith("Min deposit");
        
        var tokenBalance = await token.balanceOf(spender.address);
        expect(tokenBalance).to.equal(1_500_000_000_000_000_000_000n);
        
        await expect(pool.connect(spender).deposit(0, 500_000_000_000_000_000_000n)).to.be.revertedWith('Insufficient allowance');
        
        const poolAddress = await pool.getAddress();
        await token.connect(spender).approve(poolAddress, 1_500_000_000_000_000_000_000n);

        await pool.connect(spender).deposit(0, 500_000_000_000_000_000_000n);
        var tokenBalance = await token.balanceOf(spender.address);
        const positions = await pool.connect(spender).getPositions();

        expect(tokenBalance).to.equal(1_000_000_000_000_000_000_000n);
        expect(positions[0].amount).to.equal(500_000_000_000_000_000_000n);
        expect(positions[0].startDate).to.equal(firstFix.timestamp);
        expect(positions[0].expiry).to.equal(firstFix.timestamp + 86_400n);
    });
  });