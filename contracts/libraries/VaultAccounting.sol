// SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

struct Vault {
    uint128 amount;
    uint128 shares;
}

library VaultAccountingLibrary {

    /**
    @dev add amount of tokens to the the vault and return the number of shares
    @param total the total amount of tokens and shares in the vault
    @param amount the amount of tokens to add to the vault
    @param roundUp if true, round up the number of shares to the nearest whole number
    */
    function toShares(
        Vault memory total,
        uint256 amount,
        bool roundUp
    ) internal pure returns (uint256 shares) {
        if (total.amount == 0) {
            shares = amount;
        } else {
            shares = (amount * total.shares) / total.amount;
            if (roundUp && (shares * total.amount) / total.shares < amount) {
                shares = shares + 1;
            }
        }
    }

    /**
    @dev add the amount of tokens to the vault and return the number of shares
    @param total the total amount of tokens and shares in the vault
    @param shares the number of shares to add to the vault
    @param roundUp if true, round up the number of shares to the nearest whole number
    */
    function toAmount(
        Vault memory total,
        uint256 shares,
        bool roundUp
    ) internal pure returns (uint256 amount) {
        if (total.shares == 0) {
            amount = shares;
        } else {
            amount = (shares * total.amount) / total.shares;
            if (roundUp && (amount * total.shares) / total.amount < shares) {
                amount = amount + 1;
            }
        }
    }
}
