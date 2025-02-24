pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./abstract/TokenWalletBurnableByRootBase.sol";
import "./abstract/TokenWalletBurnableBase.sol";
import "./abstract/TokenWalletDestroyableBase.sol";

import "./libraries/TokenErrors.sol";
import "./libraries/TokenGas.sol";
import "./libraries/TokenMsgFlag.sol";
import "./interfaces/IVersioned.sol";


/**
 * @title Fungible token wallet contract.
 *
 * @dev This is an implementation of TokenWallet that implements all the
 * required methods of the TIP-3 standard.
 * As well as optional ones: burn and collections.
 *
 * Each token holder has its own instance of token wallet contract.
 * Transfer happens in a decentralized fashion - sender token wallet SHOULD
 * send the specific message to the receiver token wallet. Since token wallets
 * have the same code, it's easy for receiver token wallet to check the
 * correctness of sender token wallet.
 */
contract TokenWallet is
    TokenWalletBurnableBase,
    TokenWalletBurnableByRootBase,
    TokenWalletDestroyableBase
{

    /**
     * @dev Creates new token wallet
     *
     * @dev Nothing is passed to the constructor, but during the deployment
     * of the contract, the following parameters are passed to `StateInit`:
     *
     *   `root_` - address of the root token contract
     *   `owner_` - address of the owner of the wallet
     *
     * Preconditions:
     *
     * - `msg.pubkey()` MUST be equal to zero. This means that the owner of
     *   the TokenWallet can only smart contract.
     * - `owner_` MUST be a non-zero address.
    */
    constructor() public {
        require(tvm.pubkey() == 0, TokenErrors.NON_ZERO_PUBLIC_KEY);
        require(owner_.value != 0, TokenErrors.WRONG_WALLET_OWNER);
    }

    /**
     * @dev Implemetation of {SID} interface.
     */
    function supportsInterface(bytes4 interfaceID) override external view responsible returns (bool) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } (
            interfaceID == bytes4(0x3204ec29) ||    // SID
            interfaceID == bytes4(0x4f479fa3) ||    // TIP3TokenWallet
            interfaceID == bytes4(0x2a4ac43e) ||    // TokenWallet
            interfaceID == bytes4(0x562548ad) ||    // BurnableTokenWallet
            interfaceID == bytes4(0x0c2ff20d) ||    // BurnableByRootTokenWallet
            interfaceID == bytes4(0x0f0258aa)       // Destroyable
        );
    }

    /**
     * @dev See {TokenWalletBase-_targetBalance}.
     */
    function _targetBalance() override internal pure returns (uint128) {
        return TokenGas.TARGET_WALLET_BALANCE;
    }

    /**
     * @dev See {TokenRootBase-_buildWalletInitData}.
     *
     * We need this to deploy new wallets, as well as to
     * check incoming messages from other wallets.
     *
     * The `InitData` consists of:
     *  - `contr` (contract) - defines the contract whose `StateInit` will be created.
     *      Mandatory to be set if the `varInit` option is specified.
     *
     *  - `varInit` (initialization list) - used to set static variables of the
     *      contract, see {TokenWalletBase}.
     *      Conflicts with data and must be set contr.
     *
     *      `root_` - the address of the TokenRoot contract.
     *      `owner_` - the address of the owner of the wallet.
     *
     *  - pubkey` - the public key of the contract.
     *      The value 0 means that the wallet can be owned only by another contract.
     *      contract, the most common example is {Wallet}.
     *
     *  - `code` - the code of the TokenWallet, see {TokenRootBase}.
     */
    function _buildWalletInitData(address walletOwner) override internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenWallet,
            varInit: {
                root_: root_,
                owner_: walletOwner
            },
            pubkey: 0,
            code: tvm.code()
        });
    }

    /**
     * @dev Implementation of the virtual function {TokenWalletBase-_deployWallet}.
     */
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address)
        override
        internal
        view
        returns (address)
    {
        address wallet = new TokenWallet {
            stateInit: initData,
            value: deployWalletValue,
            wid: address(this).wid,
            flag: TokenMsgFlag.SENDER_PAYS_FEES
        }();
        return wallet;
    }
}
