pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./abstract/TokenRootTransferableOwnershipBase.sol";
import "./abstract/TokenRootBurnPausableBase.sol";
import "./abstract/TokenRootBurnableByRootBase.sol";
import "./abstract/TokenRootDisableableMintBase.sol";

import "./TokenWallet.sol";
import "./libraries/TokenErrors.sol";
import "./libraries/TokenMsgFlag.sol";

/**
 * @title Fungible token root contract
 * @dev This is an implementation of TokenRoot that implements all the required
 * methods of the TIP-3 standard.
 *
 * You can read more about the standard TIP-3 in the documentation:
 * https://docs.everscale.network/standard/TIP-3/
 *
 * The token root contract stores general information about the token, such
 * as `name`, `symbol`, `decimals`, `walletCode_`, see {ITokenRoot}.
 *
 * Each token holder has its own instance of the token wallet contract,
 * which stores information about the balance of the tokens, see {ITokenWallet}.
 * The transfer of tokens is carried out in P2P mode between the wallets of
 * the sender's and recipient's tokens.
*/
contract TokenRoot is
    TokenRootTransferableOwnershipBase,
    TokenRootBurnPausableBase,
    TokenRootBurnableByRootBase,
    TokenRootDisableableMintBase
{

    uint256 static randomNonce_;
    address static deployer_;

    /**
     * @dev Sets the values for `mintDisabled_`, `burnByRootDisabled_`,
     * `burnPaused_`, and increases the `totalSupply_`
     * if `initialSupply` is not zero.
     *
     * Parameters such as `symbol`, `decimals`, `name`, `rootOwner_`,
     * `randomNonce_` and `walletCode_` are set during contract deployment,
     * and passed as `StateInit` params`.
     *
     * Also, the listed parameters, with the exception of {totalSupply_} and
     * `burnPaused_`, are immutable:
     * they can only be set once during construction.
     *
     * @param initialSupplyTo The address for which the initial suplay will be minted.
     * @param initialSupply The Initial amount to be minted.
     * @param deployWalletValue The initial value in EVER of the deploy wallet.
     * @param mintDisabled True If need to disable minting tokens.
     * @param burnByRootDisabled True If need to disabled burning by TokenRoot.
     * @param burnPaused True If need to paused burn.
     * @param remainingGasTo The address of the recipient of the remaining gas
     *        after deploy contract.
     *
     * Preconditions:
     *
     * - TokenRoot can be deployed using external or internal message:
     *
     * - If TokenRoot deployed by external message, then message
     *   must be signed with the same key passed to `StateInit`.
     *
     * - If TokenRoot deployed by internal message, then the sender of message
     *   must be a `deployer_` and the `deployer_` must be an existed address.
     *   Or the `deployer_` can be 0, but in this case the `msg.sender`
     *   must be a equal `rootOwner_` passed to `StateInit`.
    */
    constructor(
        address initialSupplyTo,
        uint128 initialSupply,
        uint128 deployWalletValue,
        bool mintDisabled,
        bool burnByRootDisabled,
        bool burnPaused,
        address remainingGasTo
    )
        public
    {

        if (msg.pubkey() != 0) {
            require(msg.pubkey() == tvm.pubkey() && deployer_.value == 0, TokenErrors.WRONG_ROOT_OWNER);
            tvm.accept();
        } else {
            require(deployer_.value != 0 && msg.sender == deployer_ ||
                    deployer_.value == 0 && msg.sender == rootOwner_, TokenErrors.WRONG_ROOT_OWNER);
        }

        totalSupply_ = 0;
        mintDisabled_ = mintDisabled;
        burnByRootDisabled_ = burnByRootDisabled;
        burnPaused_ = burnPaused;

        tvm.rawReserve(_targetBalance(), 0);

        if (initialSupplyTo.value != 0 && initialSupply != 0) {
            TvmCell empty;
            _mint(initialSupply, initialSupplyTo, deployWalletValue, remainingGasTo, false, empty);
        } else if (remainingGasTo.value != 0) {
            remainingGasTo.transfer({
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            });
        }
    }
    /**
     * @dev Implementation of the {SID} interface.
     */
    function supportsInterface(bytes4 interfaceID) override external view responsible returns (bool) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } (
            interfaceID == bytes4(0x3204ec29) ||    // SID
            interfaceID == bytes4(0x4371d8ed) ||    // TIP3TokenRoot
            interfaceID == bytes4(0x0b1fd263) ||    // ITokenRoot
            interfaceID == bytes4(0x18f7cce4) ||    // IBurnableByRootTokenRoot
            interfaceID == bytes4(0x0095b2fa) ||    // IDisableableMintTokenRoot
            interfaceID == bytes4(0x45c92654) ||    // IBurnPausableTokenRoot
            interfaceID == bytes4(0x1df385c6)       // ITransferableOwnership
        );
    }

    /**
     * @dev Implementation of the {TokenRootBase-_targetBalance} virtual function.
     *
     * @return the `TokenGas.TARGET_ROOT_BALANCE` EVER.
     */
    function _targetBalance() override internal pure returns (uint128) {
        return TokenGas.TARGET_ROOT_BALANCE;
    }

    /**
     * @dev See {TokenRootBase-_buildWalletInitData}.
     *
     * The `InitData` consists of:
     *
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
     *      contract, the most common example is Account.
     *
     *  - `code` - the code of the {TokenWallet}.
     */
    function _buildWalletInitData(address walletOwner) override internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenWallet,
            varInit: {
                root_: address(this),
                owner_: walletOwner
            },
            pubkey: 0,
            code: walletCode_
        });
    }

    /**
     * @dev Implementation of the virtual function {TokenRootBase-_deployWallet}.
     *
     * Deploys a new {TokenWallet} contract according to the TIP-3 standard.
     */
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address)
        override
        internal
        view
        returns (address)
    {
       address tokenWallet = new TokenWallet {
            stateInit: initData,
            value: deployWalletValue,
            flag: TokenMsgFlag.SENDER_PAYS_FEES,
            code: walletCode_
        }();
        return tokenWallet;
    }

}
