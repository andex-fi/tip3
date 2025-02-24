pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../interfaces/ITokenWallet.sol";
import "../interfaces/ITokenRoot.sol";
import "../interfaces/IAcceptTokensTransferCallback.sol";
import "../interfaces/IAcceptTokensMintCallback.sol";
import "../interfaces/IBounceTokensTransferCallback.sol";
import "../interfaces/IBounceTokensBurnCallback.sol";
import "../libraries/TokenErrors.sol";
import "../libraries/TokenMsgFlag.sol";

/**
 * @dev Implementation of the {ITokenWallet} interface.
 *
 * This abstraction describes the minimal required functionality of
 * TokenWaellet contract according to the TIP-3 standard.
 *
 * Also used as a base class for implementing abstractions such as:
 *
 * - {TokenWalletBurnableBase}
 * - {TokenWalletBurnableByRootBase}
 * - {TokenWalletDestroyableBase}
 */
abstract contract TokenWalletBase is ITokenWallet {

    address static root_;
    address static owner_;

    uint128 balance_;

    /**
     * @dev Modifier than throws if called by any account other than the TokenRoot.
     */
    modifier onlyRoot() {
        require(root_ == msg.sender, TokenErrors.NOT_ROOT);
        _;
    }

    /**
     * @dev Modifier than throws if called by any account other than the `owner_`.
     */
    modifier onlyOwner() {
        require(owner_ == msg.sender, TokenErrors.NOT_OWNER);
        _;
    }

    /**
     * @dev See {TIP3TokenWallet-balance}.
     */
    function balance() override external view responsible returns (uint128) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } balance_;
    }

    /**
     * @dev See {ITokenWallet-owner}.
     */
    function owner() override external view responsible returns (address) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } owner_;
    }

    /**
     * @dev See {TIP3TokenWallet-root}.
     */
    function root() override external view responsible returns (address) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } root_;
    }

    /**
     * @dev See {TIP3TokenWallet-walletCode}.
     */
    function walletCode() override external view responsible returns (TvmCell) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } tvm.code();
    }

    /**
     * @dev See {ITokenWallet-transfer}.
     *
     * The function then uses the address of the recipient and `StateInit`
     *  (derived using a function called {_buildWalletInitData})
     *
     * to determine the address of the recipient's token wallet. The sender's
     * wallet then decreases its `balance_` by the `amount` and calls the
     * {ITokenWallet-acceptTransfer} on the recipient's token wallet.
     *
     * If the recipient's wallet is unable to accept the transfer,
     * the sender's wallet will return an error message and increase its
     * `balance_` by the `amount`.
     *
     * Note that the recipient may not have a token wallet yet. In this case,
     * if a sufficient amount of `deployWalletValue` is passed to the function,
     * a token wallet will be deployed for the recipient. If a transfer is
     * attempted to a non-existent token wallet and the required value is not
     * provided, the transaction will fail with an error.
     *
     * Preconditions:
     *
     *  - `amount` must be greater than zero.
     *  - `amount` must be less than or equal to `balance_`.
     *  - `recipient` must be a non-zero address and should not be equal to the
     *     address of the owner of the sender's wallet.
     *
     * Postcondition:
     *
     *  - `balance_` will be decreased by `amount`.
     */
    function transfer(
        uint128 amount,
        address recipient,
        uint128 deployWalletValue,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        onlyOwner
    {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);
        require(recipient.value != 0 && recipient != owner_, TokenErrors.WRONG_RECIPIENT);

        tvm.rawReserve(_reserve(), 0);

        TvmCell stateInit = _buildWalletInitData(recipient);

        address recipientWallet;

        if (deployWalletValue > 0) {
            recipientWallet = _deployWallet(stateInit, deployWalletValue, remainingGasTo);
        } else {
            recipientWallet = address(tvm.hash(stateInit));
        }

        balance_ -= amount;

        ITokenWallet(recipientWallet).acceptTransfer{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            notify,
            payload
        );
    }

    /**
     * @dev See {ITokenWallet-transferToWallet}.
     *
     * Almost the same as the {TokenWalletBase-transfer}, only it takes the
     * address of the deployed TokenWallet.
     * If the `recipientTokenWallet` is not deployed, the transaction will fail.
     *
     * Preconditions:
     *
     *  - `amount` must be greater than zero.
     *  - `amount` must be less than or equal to `balance_`.
     *  - `recipientTokenWallet` must be a non-zero address and should
     *     not be equal to the address of the sender's TokenWallet.
     *
     * Postcondition:
     *
     *  - `balance_` will be decreased by `amount`.
    */
    function transferToWallet(
        uint128 amount,
        address recipientTokenWallet,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        onlyOwner
    {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);
        require(recipientTokenWallet.value != 0 && recipientTokenWallet != address(this), TokenErrors.WRONG_RECIPIENT);

        tvm.rawReserve(_reserve(), 0);

        balance_ -= amount;

        ITokenWallet(recipientTokenWallet).acceptTransfer{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            notify,
            payload
        );
    }

    /**
     * @dev See {ITokenWallet-acceptTransfer}.
     *
     * Accepts incoming transfer for amount amount of tokens from TokenWallet,
     * owned sender.
     *
     * If `notify` is `false`, than the remaining gas MUST be sent to the
     * `remainingGasTo`.
     * Otherwise, the {IAcceptTokensTransferCallback-onAcceptTokensTransfer}
     * sends to the TokenWallet owner with the same `remainingGasTo` and `payload`.
     *
     * Preconditions:
     *
     *  - The transfer must come from the same wallet.
     *
     * Postcondition:
     *
     *  - `balance_` will be increased by `amount`.
     */
    function acceptTransfer(
        uint128 amount,
        address sender,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        functionID(0x67A0B95F)
    {
        require(msg.sender == address(tvm.hash(_buildWalletInitData(sender))), TokenErrors.SENDER_IS_NOT_VALID_WALLET);

        tvm.rawReserve(_reserve(), 2);

        balance_ += amount;

        if (notify) {
            IAcceptTokensTransferCallback(owner_).onAcceptTokensTransfer{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount,
                sender,
                msg.sender,
                remainingGasTo,
                payload
            );
        } else {
            remainingGasTo.transfer({ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS, bounce: false });
        }
    }

    /**
     * @dev See {ITokenWallet-acceptMint}.
     *
     * Accepts incoming mint foramount of tokens from TokenRoot.
     * If `notify` is `false`, than the remaining gas MUST be sent to the
     * `remainingGasTo`.
     * Otherwise, the {IAcceptTokensMintCallback-onAcceptTokensMint} sends to the
     * TokenWallet owner with the same `remainingGasTo` and `payload`.
     *
     * Preconditions:
     *
     *  - The mint must come from the TokenRoot.
     *
     * Postcondition:
     *
     *  - `balance_` will be increased by `amount`.
    */
    function acceptMint(uint128 amount, address remainingGasTo, bool notify, TvmCell payload)
        override
        external
        functionID(0x4384F298)
        onlyRoot
    {
        tvm.rawReserve(_reserve(), 2);

        balance_ += amount;

        if (notify) {
            IAcceptTokensMintCallback(owner_).onAcceptTokensMint{
                value: 0,
                bounce: false,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS
            }(
                root_,
                amount,
                remainingGasTo,
                payload
            );
        } else if (remainingGasTo.value != 0 && remainingGasTo != address(this)) {
            remainingGasTo.transfer({ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS, bounce: false });
        }
    }

    /**
     * @dev Catch bounce if {acceptTransfer} or {acceptBurn} fails
     * @param body - body of the bounced message.
     *
     * If {ITokenWallet-acceptTransfer} fails - increase back tokens
     * `balance_` by `amount` and notify owner.
     *
     * If tokens burn `acceptBurn` fails - increase back `balance_`
     * by the `amount`, and notify the owner.
    */
    onBounce(TvmSlice body) external {
        tvm.rawReserve(_reserve(), 2);

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(ITokenWallet.acceptTransfer)) {
            uint128 amount = body.decode(uint128);
            balance_ += amount;
            IBounceTokensTransferCallback(owner_).onBounceTokensTransfer{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount,
                msg.sender
            );
        } else if (functionId == tvm.functionId(ITokenRoot.acceptBurn)) {
            uint128 amount = body.decode(uint128);
            balance_ += amount;
            IBounceTokensBurnCallback(owner_).onBounceTokensBurn{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount
            );
        }
    }

    /**
     * @dev Burns `amount` tokens from TokenWallet, decreasing the
     * `balance_`.
     *
     * Preconditions:
     *
     *  - `amount` must be greater than 0.
     *  - `amount` must be less than or equal to `balance_`.
     *
     * Postcondition:
     *
     *  - `balance_` will be decreased by `amount`.
     *    If {ITokenRoot-acceptBurn} fails - message will be bounced
     *    to {onBounce}, and `balance_` will be increased back.
    */
    function _burn(
        uint128 amount,
        address remainingGasTo,
        address callbackTo,
        TvmCell payload
    ) internal {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);

        tvm.rawReserve(_reserve(), 0);

        balance_ -= amount;

        ITokenRoot(root_).acceptBurn{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            callbackTo,
            payload
        );
    }

    /**
     * @dev Withdraw all surplus balance in EVERs.
     *
     * @param to Recipient address of the surplus balance.
     *
     * NOTE: We pass flag {TokenMsgFlag.ALL_NOT_RESERVED}, so that message carries
     * all the remaining balance of the current smart contract. Parameter value is ignored.
     * The contract's balance will be equal to zero after the message processing.
     *
     * See {https://github.com/tonlabs/TON-Solidity-Compiler/blob/master/API.md#addresstransfer}
     * for more details about flags.
     */
    function sendSurplusGas(address to) external view onlyOwner {
        tvm.rawReserve(_targetBalance(), 0);
        to.transfer({
            value: 0,
            flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
            bounce: false
        });
    }

    /**
     * @dev Calculates the reserve by taking the maximum of the contract's
     * current balance minus the value of the message
     * (i.e. the amount of EVERs spent on the current transaction) and the
     * target balance of the contract (as determined by the _targetBalance function).
     * This ensures that the reserve is set to the lower of the contract's
     * current balance or its target balance, ensuring that the contract
     * does not spend more EVERs than it has available.
     */
    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, _targetBalance());
    }

    /**
     * @dev Returns the target balance of the contract.
     *
     * Target balance is used for `tvm.rawReserve`, which creates an output
     * action that reserves EVER.
     * It is roughly equivalent to creating an outgoing message that carries
     * reserve nanoevers to itself, so that subsequent spend actions cannot
     * spend more money than the reserve.
     */
    function _targetBalance() virtual internal pure returns (uint128);

    /**
     * @dev Builds the wallet `StateInit` data.
     * @param walletOwner The owner of the wallet for which the `WalletInitData` is being building.
     * @return The Wallet `StateInit` data.
     */
    function _buildWalletInitData(address walletOwner) virtual internal view returns (TvmCell);

    /**
     * @dev Deploys new token wallet.
     * @param initData - wallet `StateInit` data.
     * @param deployWalletValue - value for deploy wallet.
     * @param remainingGasTo - address for remaining gas.
     * @return deployed wallet address.
     */
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address remainingGasTo) virtual internal view returns (address);
}
