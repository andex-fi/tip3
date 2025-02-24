pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./abstract/TokenRootTransferableOwnershipBase.sol";
import "./abstract/TokenRootBurnPausableBase.sol";
import "./abstract/TokenRootBurnableByRootBase.sol";
import "./abstract/TokenRootDisableableMintBase.sol;

import "./interfaces/ITokenRootUpgradeable.sol";
import "./interfaces/ITokenWalletUpgradeable.sol";
import "./interfaces/IVersioned.sol";
import "./libraries/TokenErrors.sol";
import "./libraries/TokenMsgFlag.sol";
import "./libraries/TokenGas.sol";
import "./TokenWalletPlatform.sol";


/**
 * @title Fungible token root upgradeable contract.
 *
 * @dev This is an implementation of upgradable token root that implements
 * all the required methods of the TIP-3 standard.
 */
contract TokenRootUpgradeable is
    TokenRootTransferableOwnershipBase,
    TokenRootBurnPausableBase,
    TokenRootBurnableByRootBase,
    TokenRootDisableableMintBase,
    ITokenRootUpgradeable
{

    uint256 static randomNonce_;
    address static deployer_;

    TvmCell static platformCode_;
    uint32 walletVersion_;


    /**
     * @dev Sets the values for `mintDisabled_`, `burnByRootDisabled_`,`burnPaused_`,
     * and increases the `totalSupply_` if `initialSupply` is not zero.
     *
     * Parameters such as `symbol`, `decimals`, `name`, `rootOwner_` `randomNonce_`
     * `deployer_`, and `platformCode_` are set during contract deployment,
     * and passed as `StateInit` params.
     *
     * Also, the listed parameters, with the exception of `totalSupply_` and
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
     * - The owner of {TokenRoot} can be an external or internal:
     *
     * - If the owner of {TokenRoot} is external, then the message being expanded
     *   must be signed with the same key passed to `StateInit`.
     *
     * - If the owner of {TokenRoot} is internal, then the sender of the message
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
        walletVersion_ = 1;

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
            interfaceID == bytes4(0x376ddffc) ||    // IBurnPausableTokenRoot
            interfaceID == bytes4(0x1df385c6)       // ITransferableOwnership
        );
    }

    /**
     * @dev See {ITokenRootUpgradeable-walletVersion}.
     */
    function walletVersion() override external view responsible returns (uint32) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } walletVersion_;
    }

    /**
     * @dev See {ITokenRootUpgradeable-platformCode}.
     */
    function platformCode() override external view responsible returns (TvmCell) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } platformCode_;
    }

    /**
     * @dev See {ITokenRootUpgradeable-requestUpgradeWallet}.
     *
     * Preconditions:
     *  - Sender is a valid wallet.
     *  - `currentVersion` must be not equal to `walletVersion_`.
     *
     * Postcondition:
     *   - If `currentVersion` is not equal to `walletVersion_`, then
     *    the wallet will be upgraded to the new version. Otherwise,
     *    the remaining gas will be transferred to `remainingGasTo`.
     */
    function requestUpgradeWallet(
        uint32 currentVersion,
        address walletOwner,
        address remainingGasTo
    )
        override
        external
    {
        require(msg.sender == _getExpectedWalletAddress(walletOwner), TokenErrors.SENDER_IS_NOT_VALID_WALLET);

        tvm.rawReserve(_reserve(), 0);

        if (currentVersion == walletVersion_) {
            remainingGasTo.transfer({ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED });
        } else {
            ITokenWalletUpgradeable(msg.sender).acceptUpgrade{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED,
                bounce: false
            }(
                walletCode_,
                walletVersion_,
                remainingGasTo
            );
        }
    }

    /**
     * @dev See {ITokenRootUpgradeable-setWalletCode}.
     *
     * Preconditions:
     *  - Sender must be the owner of the TokenRoot.
     *
     * Postcondition:
     *  - `walletCode_` is set to `code`.
     *  - `walletVersion_` is incremented.
     */
    function setWalletCode(TvmCell code) override external onlyRootOwner {
        tvm.rawReserve(_targetBalance(), 0);
        walletCode_ = code;
        walletVersion_++;
    }

    /**
     * @dev See {ITokenRootUpgradeable-upgrade}.
     *
     * Precondition:
     *  - Sender must be the owner of the TokenRoot.
     */
    function upgrade(TvmCell code) override external onlyRootOwner {
        TvmBuilder builder;

        builder.store(rootOwner_);
        builder.store(totalSupply_);
        builder.store(decimals_);

        TvmBuilder codes;
        codes.store(walletVersion_);
        codes.store(platformCode_);
        codes.store(walletCode_);

        TvmBuilder naming;
        codes.store(name_);
        codes.store(symbol_);

        TvmBuilder params;
        params.store(mintDisabled_);
        params.store(burnByRootDisabled_);
        params.store(burnPaused_);

        builder.storeRef(naming);
        builder.storeRef(codes);
        builder.storeRef(params);

        tvm.setcode(code);
        tvm.setCurrentCode(code);
        onCodeUpgrade(builder.toCell());
    }

    /**
     * @dev See {ITokenRootUpgradeable-onCodeUpgrade}.
     */
    function onCodeUpgrade(TvmCell data) private { }

    /**
     * @dev Returns the target balance.
     */
    function _targetBalance() override internal pure returns (uint128) {
        return TokenGas.TARGET_ROOT_BALANCE;
    }

    /**
     * @dev Returns the wallet init data for deploy new wallet.
     * @param walletOwner - wallet owner.
     * @return wallet init data cell.
     */
    function _buildWalletInitData(address walletOwner) override internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenWalletPlatform,
            varInit: {
                root: address(this),
                owner: walletOwner
            },
            pubkey: 0,
            code: platformCode_
        });
    }

    /**
     * @dev implemetation logic `deployWallet` function.
     * @param initData - wallet init data.
     * @param deployWalletValue - value for deploy wallet.
     * @param remainingGasTo - recipient of remaining gas.
     * @return deployed wallet address.
     *
     * Postcondition:
     *  - Deploy new token wallet.
     */
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address remainingGasTo)
        override
        internal
        view
        returns (address)
    {
       address tokenWallet = new TokenWalletPlatform {
            stateInit: initData,
            value: deployWalletValue,
            wid: address(this).wid,
            flag: TokenMsgFlag.SENDER_PAYS_FEES
       }(walletCode_, walletVersion_, address(0), remainingGasTo);

       return tokenWallet;
    }

}
