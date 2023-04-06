const hre = require("hardhat")
const ethers = hre.ethers
const network = hre.hardhatArguments.network;

async function main() {

   [admin] =  await ethers.getSigners();

   const DAI_TOKEN = "0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60";
   const DAI_PRICE_FEED = "0x0d79df66BE487753B02D015Fb622DED7f0E9798d"
  
   const LENDINGPOOL_FACTORY = await ethers.getContractFactory("LendingPool");
   const lendingPool = await LENDINGPOOL_FACTORY.deploy();
   await lendingPool.deployed();
 
   await lendingPool.connect(admin).addSupportedToken(DAI_TOKEN, DAI_PRICE_FEED);
 
   console.log("Lending Pool Deployed", lendingPool.address);
   
   //Use following code when need verification as well

   // if(network === "goerli") {
      
   //    //verify contract
   //    await hre.run("verify:verify", {
   //        address: lendingPool.address,
   //        constructorArguments: [],
   //    });
    
   // }


  
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })