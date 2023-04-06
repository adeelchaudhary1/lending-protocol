const { expect } = require('chai')
const ethers = hre.ethers;

const {
    getAmountInWei,
    deployERC20Mock,
    mintERC20,
    approveERC20,
    deployAggregatorMock,
} = require('../utils/helpers')

describe.only('Lending Pool Contract', function () {
    before(async () => {
        [manager, user1, user2, user3, randomUser] = await ethers.getSigners()

        // Deploy Lending Pool contract
        const LendingPool = await ethers.getContractFactory('LendingPool')
        pool = await LendingPool.deploy()

        // Deploy ERC20 mock contract for testing
        erc20Token = await deployERC20Mock()
        erc20Token1 = await deployERC20Mock()

        tokenPriceFeed = await deployAggregatorMock(getAmountInWei(100), 18)

        await mintERC20(
            user1,
            erc20Token.address,
            ethers.utils.parseUnits('1000', 18),
        )
    })

    it('should check if manager is valid manager', async function () {
        expect(await pool.manager()).to.equal(manager.address)
    })

    it('should not lend token that is not allowed', async function () {
        await expect(
            pool.supply(erc20Token.address, getAmountInWei(100)),
        ).to.be.revertedWith('TokenNotSupported')
            
        await expect(pool.connect(user1).addSupportedToken(erc20Token.address, tokenPriceFeed.address)).to.be.revertedWith("OnlyManager")
        await pool.addSupportedToken(erc20Token.address, tokenPriceFeed.address)
        await expect(pool.addSupportedToken(erc20Token.address, tokenPriceFeed.address)).to.be.revertedWith("AlreadySupported")
    })

    it('should not lend token when paused', async function () {

        await pool.setPaused(3)
        await pool.setPaused(1)

        await expect(pool.connect(user1).setPaused(1)).to.be.revertedWith("OnlyManager");

        await expect(
            pool.supply(erc20Token.address, getAmountInWei(100)),
        ).to.be.revertedWith('PoolIsPaused')

        await pool.setPaused(2)

    })

    it('should not lend token when token is not approved to pool contract', async function () {


        await expect(pool.connect(user1).supply(erc20Token.address, getAmountInWei(100))).to.be.revertedWith("ERC20: transfer amount exceeds allowance");


    })

    it('should lend token', async function () {

        await approveERC20(
            user1,
            erc20Token.address,
            getAmountInWei(100000),
            pool.address,
        )

        await pool.connect(user1).supply(erc20Token.address, getAmountInWei(100))

        expect(await erc20Token.balanceOf(pool.address)).to.equal(getAmountInWei(100))

        let getUserTotalCollateral = await pool.getUserTotalCollateral(user1.address)

        // get user share in DAI 
        expect(getUserTotalCollateral).to.equal(getAmountInWei(10000))


    })

    it('should not borrow token when paused', async function () {

        await pool.setPaused(1)

        await expect(
            pool.borrow(erc20Token.address, getAmountInWei(100)),
        ).to.be.revertedWith('PoolIsPaused')

        await pool.setPaused(2)


    })

    it('should not borrow token when token is not allowed', async function () {

        await expect(
            pool.borrow(erc20Token1.address, getAmountInWei(100)),
        ).to.be.revertedWith('TokenNotSupported')

    })

    it('should not borrow token when collateral is not enough', async function () {

        await expect(
            pool.borrow(erc20Token.address, getAmountInWei(1000)),
        ).to.be.revertedWith('InsufficientBalance')

    })

    it('should not borrow token, when user health factor is greater then minimum health factor', async function () {

        await expect(pool.borrow(erc20Token.address, getAmountInWei(100))).to.be.revertedWith("BorrowNotAllowed")

    })

    it('should borrow token', async function () {

        let getUserHealthFactor = await pool.healthFactor(user1.address)
        expect(getUserHealthFactor).to.equal(ethers.utils.parseUnits('100', 18))

        await pool.connect(user1).borrow(erc20Token.address, getAmountInWei(20))

        expect(await erc20Token.balanceOf(pool.address)).to.equal(getAmountInWei(80))

        let getUserTotalCollateral = await pool.getUserTotalCollateral(user1.address)
        expect(getUserTotalCollateral).to.equal(getAmountInWei(10000)) // 100 DAI price is 10000 USD

        let getUserTotalBorrow = await pool.getUserTotalBorrow(user1.address)
        expect(getUserTotalBorrow).to.equal(getAmountInWei(2000)) // 20 DAI price is 2000 USD

        getUserHealthFactor = await pool.healthFactor(user1.address)
        expect(getUserHealthFactor).to.equal(ethers.utils.parseUnits('4', 18))


    })

    it("should repay token", async function () {

        await approveERC20(
            user1,
            erc20Token.address,
            getAmountInWei(20000),
            pool.address,
        )

        await pool.connect(user1).repay(erc20Token.address, getAmountInWei(10))

        expect(await erc20Token.balanceOf(pool.address)).to.equal(getAmountInWei(90))

        await pool.getUserTotalCollateral(user1.address)
        await pool.getUserTotalBorrow(user1.address)
        await pool.healthFactor(user1.address)

        await pool.connect(user1).repay(erc20Token.address, getAmountInWei(10))



    })

    it("should borrow token and repay after some time passed to check interest value", async function () {

        await pool.connect(user1).borrow(erc20Token.address, getAmountInWei(20))

        //increase time by 1 day
        await ethers.provider.send("evm_increaseTime", [86400])
        await ethers.provider.send("evm_mine")

        await approveERC20(
            user1,
            erc20Token.address,
            getAmountInWei(200000),
            pool.address,
        );

        await pool.connect(user1).repay(erc20Token.address, getAmountInWei(20))


    })

    it("should get user total collateral and borrowed", async function () {

        let getUserData = await pool.getUserTokenCollateralAndBorrow(user1.address, erc20Token.address)
        expect(getUserData[0]).to.equal(getAmountInWei(100))

    })

    it("should not withdraw token when balance exceeds limit", async function() {

        //get token vault details 
        await pool.getTokenVault(erc20Token.address);
        await expect(pool.withdraw(erc20Token.address, getAmountInWei(100))).to.be.revertedWith("InsufficientBalance");

    })

    it("should withdraw token", async function() {

        await pool.connect(user1).withdraw(erc20Token.address, getAmountInWei(100));
        expect(await erc20Token.balanceOf(pool.address)).to.equal(getAmountInWei(0))

    })


})
