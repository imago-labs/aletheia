const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  const USDC = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  const ORACLE = deployer.address;

  const Pool = await hre.ethers.getContractFactory("AletheiaPool");
  const pool = await Pool.deploy(USDC, ORACLE);
  await pool.waitForDeployment();

  const address = await pool.getAddress();
  console.log("AletheiaPool deployed to:", address);

  fs.writeFileSync(
    "deployments.json",
    JSON.stringify({ address, usdc: USDC, oracle: ORACLE }, null, 2)
  );
  console.log("Saved to deployments.json");
}

main().catch((e) => { console.error(e); process.exit(1); });
