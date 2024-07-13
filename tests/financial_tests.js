const {loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const {expect} = require('chai');
const {ethers} = require('hardhat');

async function deployOnceFixture() {
    const [ owner ] = await ethers.getSigners();
    const libFactory = await ethers.getContractFactory("FinancialLib");
    const lib = await libFactory.deploy();

    return { lib };
}

describe("FinancialLib tests", function () {
    it("Put pricing test", async function () {
        const { lib } = await loadFixture(deployOnceFixture);

        // Assumptions
        var forward = 5000 * (2 ** 32);
        const strike = 4950 * (2 ** 32);
        var vol = Math.round(0.435 * (2 ** 23));
        // 90 days option
        const expiry = 1_059_033_032;

        var putPrice = await lib.putPremium(forward, strike, vol, expiry);
        console.log(putPrice);
      });
    });