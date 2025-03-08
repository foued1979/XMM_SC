const { time, loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers, network } = require('hardhat');
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

describe('Test vesting functions', function () {
    it('Can allocate without vesting', async function () {
        const [owner, token, spender] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 100n * BigInt(10 ** 18);

      expect(await token.allocate(spender, amount1)).to.emit(token, 'Allocated');
      var spenderConnect = await token.connect(spender);
      expect(await spenderConnect.getReleasableAmount()).to.equal(0n);
    });

    it('Can allocate with vesting', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 10_000n * BigInt(10 ** 18);
      
      await expect(token.allocateWithVesting(spender, amount1, 3, 0, 0, 1, 2)).to.emit(token, 'Allocated').to.emit(token, "VestingScheduleCreated");

      var spenderConnect = await token.connect(spender);
      await expect(spenderConnect.transfer(owner, 100n * BigInt(10 ** 18))).to.be.revertedWith("Vest err");

      await time.increase(2*3*24*3600);
      expect(await spenderConnect.getReleasableAmount()).to.be.above(1_000n * BigInt(10 ** 18));
      await expect(spenderConnect.transfer(owner, 1_000n * BigInt(10 ** 18))).to.emit(token, "Transfer");
      await expect(spenderConnect.transfer(owner, 1n * BigInt(10 ** 18))).to.be.revertedWith("Vest err");

      expect(await token.balanceOf(spender)).to.equal(9_000n * BigInt(10 ** 18));

      await expect(token.allocateWithVesting(spender, amount1, 3, 0, 0, 1, 2)).to.emit(token, 'Allocated').to.emit(token, "TokensAddedToVestingSchedule");
    });

    it('Can transfer all after vesting', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const ownerAmount = 250_000n * BigInt(10 ** 18);
      const amount1 = 10_000n * BigInt(10 ** 18);
      
      var spenderConnect = await token.connect(spender);
      await expect(token.allocateWithVesting(spender, amount1, 3, 0, 0, 1, 2)).to.emit(token, 'Allocated').to.emit(token, "VestingScheduleCreated");

      await time.increase(33*24*3600);
      expect(await spenderConnect.getReleasableAmount()).to.be.equal(amount1);
      await expect(spenderConnect.transfer(owner, amount1)).to.emit(token, "Transfer");
      expect(await token.balanceOf(spender)).to.equal(0n);
    });

    it('Can manage upftont at cliff', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const amount1 = 10_000n * BigInt(10 ** 18);
      
      var spenderConnect = await token.connect(spender);
      await expect(token.allocateWithVesting(spender, amount1, 3, 0, 20, 1, 2)).to.emit(token, 'Allocated').to.emit(token, "VestingScheduleCreated");

      await time.increase(3*24*3600 - 10);
      expect(await spenderConnect.getReleasableAmount()).to.be.equal(0n);
      await time.increase(11);
      expect(await spenderConnect.getReleasableAmount()).to.be.above(2_000n * BigInt(10 ** 18));
      await time.increase(30*24*3600 + 1);
      expect(await spenderConnect.getReleasableAmount()).to.be.equal(amount1);
    });

    it('Can get allocate with no cliff', async function () {
      const [owner, token, spender] = await loadFixture(_deploy);
      
      const amount1 = 10_000n * BigInt(10 ** 18);
      
      var spenderConnect = await token.connect(spender);
      expect(await token.allocateWithVesting(spender, amount1, 0, 0, 20, 1, 2)).to.emit("VestingScheduleCreated");

      const releasable = await spenderConnect.getReleasableAmount();
      expect(releasable).to.equal(2_000n * BigInt(10 ** 18));

      const initAmt = await spenderConnect.getRemainingVestedAmount();
      expect(initAmt).to.equal(10_000n * BigInt(10 ** 18));

      await spenderConnect.transfer("0x1234567890123456789012345678901234500005", 1_000n * BigInt(10 ** 18));
      expect(await spenderConnect.getRemainingVestedAmount()).to.equal(9_000n * BigInt(10 ** 18));

      expect(await token.getRemainingVestedAmount()).to.equal(0n);
    });
  });