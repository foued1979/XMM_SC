const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const digits = "0123456789ABCDEF";
const max32 = 2**32 - 1;

async function main() {
  const factory = await ethers.getContractFactory("LibTest");
  const lib = await factory.deploy();

  var b = await lib.put(dtoi(99), dtoi(0.50), dtoi(1.0/12));

  console.log(`Power test: ${itod(b)}`)
}

function dtoi(x) {
  return BigInt(Math.floor(x * 0xFFFFFFFF));
}

function itod(x)
{
  return Number(x) / 0xFFFFFFFF;
}

function decimalToInt64(x) {
  var intx = Math.floor(x);
  var dec = (x - intx) * max32;

  return BigInt(intx) * BigInt(0xFFFFFFFF) + BigInt(Math.floor(dec));
}

function int64ToDec(x) {
  var int = Number(x / BigInt(0xFFFFFFFF));
  var dec = Number(x & BigInt(0x00000000FFFFFFFF)) / max32;

  return int + dec;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});