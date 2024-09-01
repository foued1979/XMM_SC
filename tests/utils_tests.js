const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { expect } = require('chai');

const { ethers, waffle } = require('hardhat');

const {deployContract} = waffle;
const LibArtifact = require('../artifacts/contracts/libraries/utils.sol/Utils.json');

describe('Test utils', function () {
    async function deployOnceFixture() {
        const [owner, ...otherAccounts] = await ethers.getSigners();
        lib = (await deployContract(owner, LibArtifact));
    
        return { lib, owner, otherAccounts };
    }

    it('Term ', async function() {
        const { lib } = await loadFixture(deployOnceFixture);
    });
});