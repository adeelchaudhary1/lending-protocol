// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/VaultAccounting.sol";

contract LendingPool {
    using VaultAccountingLibrary for Vault;

    //--------------------------------------------------------------------
    /** VARIABLES */

    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80%
    //TODO following can be used in liquidation function implementation to which is not given in this
    //uint256 public constant LIQUIDATION_CLOSE_FACTOR = 50; // 50%
    //uint256 public constant LIQUIDATION_REWARD = 5; // 5%
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant STABLE_RATE = 0.025e18;

    uint256 public lastTimestamp;

    // USED uint256 instead of bool to save gas
    // paused = 1 && active = 2
    uint256 public paused = 2;
    address public manager;

    struct SupportedERC20 {
        address daiPriceFeed;
        bool supported;
    }

    struct TokenVault {
        Vault totalAsset;
        Vault totalBorrow;
    }

    address[] private supportedTokensList;
    mapping(address => SupportedERC20) supportedTokens;

    mapping(address => TokenVault) private vaults;

    mapping(address => mapping(address => uint256))
        private userCollateralBalance;
    mapping(address => mapping(address => uint256)) private userBorrowBalance;

    //--------------------------------------------------------------------
    /** ERRORS */

    error TokenNotSupported();
    error BorrowNotAllowed();
    error InsufficientBalance();
    error UnderCollateralized();
    error BorrowerIsSolvant();
    error AlreadySupported(address token);
    error OnlyManager();
    error TransferFailed();
    error PoolIsPaused();

    //--------------------------------------------------------------------
    /** EVENTS */

    event Deposit(address user, address token, uint256 amount, uint256 shares);
    event Borrow(address user, address token, uint256 amount, uint256 shares);
    event Repay(address user, address token, uint256 amount, uint256 shares);
    event Withdraw(address user, address token, uint256 amount, uint256 shares);
    event UpdateInterestRate(uint256 elapsedTime, uint64 newInterestRate);
    event AccruedInterest(uint256 interestEarned);
    event AddSupportedToken(address token);

    constructor() {
        manager = msg.sender;
    }

    /**
     * @dev function to supply assets to the pool
     * @param token address of the token to supply
     * @param amount amount of the token to supply
     */
    function supply(address token, uint256 amount) external {
        WhenNotPaused();
        allowedToken(token);
        _accrueInterest(token);

        transferERC20(token, msg.sender, address(this), amount);

        uint256 shares = vaults[token].totalAsset.toShares(amount, false);
        vaults[token].totalAsset.shares += uint128(shares);
        vaults[token].totalAsset.amount += uint128(amount);

        userCollateralBalance[msg.sender][token] += shares;

        emit Deposit(msg.sender, token, amount, shares);
    }

    /**
     * @dev function to borrow assets from the pool
     * @param token address of the token to borrow
     * @param amount amount of the token to borrow
     */
    function borrow(address token, uint256 amount) external {
        WhenNotPaused();
        allowedToken(token);

        _accrueInterest(token);

        if (amount > IERC20(token).balanceOf(address(this)))
            revert InsufficientBalance();

        uint256 shares = vaults[token].totalBorrow.toShares(amount, false);
        vaults[token].totalBorrow.shares += uint128(shares);
        vaults[token].totalBorrow.amount += uint128(amount);

        userBorrowBalance[msg.sender][token] += shares;

        transferERC20(token, address(this), msg.sender, amount);

        // health factor value determined whether user can borrow amount not 
        if (healthFactor(msg.sender) <= MIN_HEALTH_FACTOR)
            revert BorrowNotAllowed();

        emit Borrow(msg.sender, token, amount, shares);
    }

    /**
     * @dev function to repay assets to the pool
     * @param token address of the token to repay
     * @param amount amount of the token to repay
     */
    function repay(address token, uint256 amount) external {

        _accrueInterest(token);

        transferERC20(token, msg.sender, address(this), amount);

        uint256 shares = vaults[token].totalBorrow.toShares(amount, false);
        vaults[token].totalBorrow.shares -= uint128(shares);
        vaults[token].totalBorrow.amount -= uint128(amount);

        userBorrowBalance[msg.sender][token] -= shares;

        emit Repay(msg.sender, token, amount, shares);
    }

    /**
     * @dev function to withdraw assets from the pool
     * @param token address of the token to withdraw
     * @param amount amount of the token to withdraw
     */
    function withdraw(address token, uint256 amount) external {
        _accrueInterest(token);

        uint256 shares = vaults[token].totalAsset.toShares(amount, false);
        if (userCollateralBalance[msg.sender][token] < shares)
            revert InsufficientBalance();

        vaults[token].totalAsset.shares -= uint128(shares);
        vaults[token].totalAsset.amount -= uint128(amount);

        unchecked {
            userCollateralBalance[msg.sender][token] -= shares;
        }

        transferERC20(token, address(this), msg.sender, amount);

        emit Withdraw(msg.sender, token, amount, shares);
    }

    /** 
    * @dev function to liquidate the user's collateral
    */
    function liquidateUserCollateral() external {

        // liquidate collateral is integral part of every lending protocol 
        // not implemented as not required in the given instructions
    }
 
    /**
     * @dev get the total collateral of the user for all supported tokens
     * @param user address of the user
     */
    function getUserTotalCollateral(
        address user
    ) public view returns (uint256 totalInDai) {
        uint256 len = supportedTokensList.length;
        for (uint256 i; i < len; ) {
            address token = supportedTokensList[i];

            uint256 tokenAmount = vaults[token].totalAsset.toAmount(
                userCollateralBalance[user][token],
                false
            );

            if (tokenAmount != 0) {
                totalInDai += getTokenPrice(token) * tokenAmount;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev get the total borrow of the user for all supported tokens
     * @param user address of the user
     */
    function getUserTotalBorrow(
        address user
    ) public view returns (uint256 totalInDai) {
        uint256 len = supportedTokensList.length;
        for (uint256 i; i < len; ) {
            address token = supportedTokensList[i];

            uint256 tokenAmount = vaults[token].totalBorrow.toAmount(
                userBorrowBalance[user][token],
                false
            );
            if (tokenAmount != 0) {
                totalInDai += getTokenPrice(token) * tokenAmount;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev get the total collateral and borrow of the user for all supported tokens
     * @param user address of the user
     */
    function getUserData(
        address user
    ) public view returns (uint256 totalCollateral, uint256 totalBorrow) {
        totalCollateral = getUserTotalCollateral(user);
        totalBorrow = getUserTotalBorrow(user);
    }

    /**
     * @dev get the collateral and borrow of the user for a specific token
     * @param user address of the user
     * @param token address of the token
     */
    function getUserTokenCollateralAndBorrow(
        address user,
        address token
    )
        external
        view
        returns (uint256 tokenCollateralAmount, uint256 tokenBorrowAmount)
    {
        tokenCollateralAmount = userCollateralBalance[user][token];
        tokenBorrowAmount = userBorrowBalance[user][token];
    }

    /**
     * @dev get the health factor of the user, which is the ratio of collateral to borrow
     * @param user address of the user
     */
    function healthFactor(address user) public view returns (uint256 factor) {
        (
            uint256 totalCollateralAmount,
            uint256 totalBorrowAmount
        ) = getUserData(user);

        if (totalBorrowAmount == 0) return 100 * MIN_HEALTH_FACTOR;

        uint256 collateralAmountWithThreshold = (totalCollateralAmount *
            LIQUIDATION_THRESHOLD) / 100;
        factor =
            (collateralAmountWithThreshold * MIN_HEALTH_FACTOR) /
            totalBorrowAmount;
    }

    /**
     * @dev get the token vault
     * @param token address of the token
     */
    function getTokenVault(
        address token
    ) public view returns (TokenVault memory vault) {
        vault = vaults[token];
    }

    /**
     * @dev get the token price from chainlink
     * @param token address of the token
     */
    function getTokenPrice(address token) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            supportedTokens[token].daiPriceFeed
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 decimals = priceFeed.decimals();
        return uint256(price) / 10 ** decimals;
    }

    //--------------------------------------------------------------------
    /** INTERNAL FUNCTIONS */

    /**
     * @dev calculate the interest of the borrowed token amount
     * @param token address of the token
     */
    function _accrueInterest(
        address token
    ) internal returns (uint256 _interestEarned) {
        TokenVault memory _vault = vaults[token];

        if (_vault.totalAsset.amount == 0) {
            return 0;
        }

        // If there are no borrows, no interest accrues
        if (_vault.totalBorrow.shares == 0) {
            lastTimestamp = uint64(block.timestamp);
        } else {
            uint256 _deltaTime = block.timestamp - lastTimestamp;

            lastTimestamp = uint64(block.timestamp);

            // Calculate interest accrued
            _interestEarned =
                (_deltaTime * _vault.totalBorrow.amount * STABLE_RATE) /
                1e18;
            // Accumulate interest
            _vault.totalBorrow.amount += uint128(_interestEarned);
            _vault.totalAsset.amount += uint128(_interestEarned);

            emit AccruedInterest(_interestEarned);

            vaults[token] = _vault;
        }
    }

    /**
     * @dev check if the token is supported
     * @param token address of the token
     */
    function allowedToken(address token) internal view {
        if (!supportedTokens[token].supported) revert TokenNotSupported();
    }

    /**
     * @dev check if the pool is not paused
     */
    function WhenNotPaused() internal view {
        if (paused == 1) revert PoolIsPaused();
    }

    /**
    @dev transfer the token from the user to the contract or from contract to user
    @param _token address of the token
    @param _from address of the sender
    @param _to address of the receiver
    @param _amount amount of the token
    */
    function transferERC20(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        bool success;
        if (_from == address(this)) {
            success = IERC20(_token).transfer(_to, _amount);
        } else {
            success = IERC20(_token).transferFrom(_from, _to, _amount);
        }
    }

    //--------------------------------------------------------------------
    /** OWNER FUNCTIONS */

    /**
     * @dev set the manager of the contract
     * @param _state 1 for pause, 2 for unpause
     */
    function setPaused(uint256 _state) external {
        if (msg.sender != manager) revert OnlyManager();
        if (_state == 1 || _state == 2) paused = _state;
    }

    /**
     * @dev add the token for the lending pool and price feed for the token
     * @param token address of the token
     * @param priceFeed address of the price feed of the token of chainlink
     */
    function addSupportedToken(address token, address priceFeed) external {
        if (msg.sender != manager) revert OnlyManager();
        if (supportedTokens[token].supported) revert AlreadySupported(token);

        supportedTokens[token].daiPriceFeed = priceFeed;
        supportedTokens[token].supported = true;
        supportedTokensList.push(token);

        emit AddSupportedToken(token);
    }
}
