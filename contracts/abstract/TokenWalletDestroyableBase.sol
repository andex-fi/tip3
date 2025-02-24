pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./TokenWalletBase.sol";
import "../interfaces/ITokenRoot.sol";
import "../interfaces/IDestroyable.sol";
import "../libraries/TokenErrors.sol";
import "../libraries/TokenMsgFlag.sol";

/**
 * @dev Implementation of the {IDestroyable} interface.
 *
 * This abstraction extends the functionality of {TokenWalletBase} and adding
 * the ability to destroy the wallet.
 */
abstract contract TokenWalletDestroyableBase is TokenWalletBase, IDestroyable {

    /**
     * @dev See {IDestroyable-destroy}.
     *
     * Precondition:
     *
     *  - The wallet balance must be empty.
     */
    function destroy(address remainingGasTo) override external onlyOwner {
        require(balance_ == 0, TokenErrors.NON_EMPTY_BALANCE);
        remainingGasTo.transfer({
            value: 0,
            flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.DESTROY_IF_ZERO,
            bounce: false
        });
    }
}
