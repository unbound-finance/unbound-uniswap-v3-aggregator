require("@nomiclabs/hardhat-waffle");
require('dotenv').config()

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    kovan: {
      url: "https://kovan.infura.io/v3/fbfa8c28d58f4837a199d6d16f7f43f9", //`https://kovan.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: ["134b81495b60d02d1326e1892dbae2705004649f42cf1ee786eabb38de0b2101"], //[process.env.PRIVATE_KEY],
      gasPrice: 50000000000,
    }
  },
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1_000_000,
      },
      metadata: {
        bytecodeHash: 'none',
      },
    },
  },
};

