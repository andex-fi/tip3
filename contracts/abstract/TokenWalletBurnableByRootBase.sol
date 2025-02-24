pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./TokenWalletBase.sol";
import "../interfaces/IBurnableByRootTokenWallet.sol";

/**
 * @dev Implementation of the {IBurnableByRootTokenWallet} interface.
 *
 * This abstraction extends the functionality of {TokenWalletBase} and adding
 * burning tokens by TokenRoot.
 */
abstract contract TokenWalletBurnableByRootBase is TokenWalletBase, IBurnableByRootTokenWallet {

    /**
     * @dev See {IBurnableByRootTokenWallet-burnByRoot}.
     *
     * Precondition:
     *
     *  - the caller must be TokenRoot.
     *
     * Postcondition:
     *
     *  - The `balance_` of wallet must decrease by the `amount` that is burned.
     *
     * For implementation details, see {TokenWalletBase-_burn}.
    */
    function burnByRoot(uint128 amount, address remainingGasTo, address callbackTo, TvmCell payload)
        override
        external
        onlyRoot
    {
        _burn(amount, remainingGasTo, callbackTo, payload);
    }

}
