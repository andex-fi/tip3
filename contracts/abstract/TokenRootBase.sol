pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../interfaces/ITransferTokenRootOwnershipCallback.sol";
import "../interfaces/IAcceptTokensBurnCallback.sol";
import "../interfaces/ITokenRoot.sol";
import "../interfaces/ITokenWallet.sol";
import "../structures/ICallbackParamsStructure.sol";
import "../libraries/TokenErrors.sol";
import "../libraries/TokenMsgFlag.sol";

/**
 * @dev Implementation of the {ITokenRoot} interface.
 *
 * This abstraction describes the minimal required functionality of
 * Token Root contract according to the TIP-3 standard.
 *
 * Also used as a base class for implementing abstractions such as:
 *
 *  - {TokenRootBurnableByRootBase}
 *  - {TokenRootBurnPausableBase}
 *  - {TokenRootDisableableMintBase}
 *  - {TokenRootTransferableOwnershipBase}
 */
abstract contract TokenRootBase is ITokenRoot, ICallbackParamsStructure {

    string static name_;
    string static symbol_;
    uint8 static decimals_;

    address static rootOwner_;

    TvmCell static walletCode_;

    uint128 totalSupply_;

    /**
     * @dev Default entrypoint if no other entry point fits.
     */
    fallback() external {
    }

    /**
     * @dev Modifier than throws if called by any account other than the `rootOwner_`.
     */
    modifier onlyRootOwner() {
        require(rootOwner_.value != 0 && rootOwner_ == msg.sender, TokenErrors.NOT_OWNER);
        _;
    }

    /**
     * @dev See {TIP3TokenRoot-name}.
     */
    function name() override external view responsible returns (string) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } name_;
    }

    /**
     * @dev See {TIP3TokenRoot-symbol}.
     */
    function symbol() override external view responsible returns (string) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } symbol_;
    }

    /**
     * @dev See {TIP3TokenRoot-decimals}.
     */
    function decimals() override external view responsible returns (uint8) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } decimals_;
    }

    /**
     * @dev See {TIP3TokenRoot-totalSupply}.
     */
    function totalSupply() override external view responsible returns (uint128) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } totalSupply_;
    }

    /**
     * @dev See {TIP3TokenRoot-walletCode}.
     */
    function walletCode() override external view responsible returns (TvmCell) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } walletCode_;
    }

    /**
     * @dev See {ITokenRoot-rootOwner}.
     */
    function rootOwner() override external view responsible returns (address) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } rootOwner_;
    }

    /**
     * @dev See {ITokenRoot-walletOf}.
     *
     * Precondition:
     *
     *  - `walletOwner` cannot be the zero address.
     */
    function walletOf(address walletOwner)
        override
        public
        view
        responsible
        returns (address)
    {
        require(walletOwner.value != 0, TokenErrors.WRONG_WALLET_OWNER);
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } _getExpectedWalletAddress(walletOwner);
    }

    /**

     * @dev See {ITokenRoot-deployWallet}.
     *
     * Precondtion:
     *
     *  - `walletOwner` cannot be the zero address.
     *  - `deployWalletValue` must be enough to deploy a new wallet.
     *
     * Postcondition:
     *
     *  - Returns the address of the deployed wallet.
    */
    function deployWallet(address walletOwner, uint128 deployWalletValue)
        public
        override
        responsible
        returns (address tokenWallet)
    {
        require(walletOwner.value != 0, TokenErrors.WRONG_WALLET_OWNER);
        tvm.rawReserve(_reserve(), 0);

        tokenWallet = _deployWallet(_buildWalletInitData(walletOwner), deployWalletValue, msg.sender);

        return { value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: false } tokenWallet;
    }

    /**
     * @dev See {ITokenRoot-mint}.
     *
     * Preconditions:
     *
     *  - `sender` MUST be rootOwner.
     *  - Minting should be allowed on the TokenRoot contract.
     *  - Either recipients TokenWallet it must already be deployed,
     *    or there must be enough `deployWalletValue` available
     *    to deploy a new wallet.
     *  - `amount` cannot be zero.
     *  - `recipient` cannot be the zero address.
     *
     * Postconditions:
     *
     *  - The `totalSupply_` must increase by the `amount` that is minted.
     *  - If `deployWalletValue` is greater than 0, then a new
     *    TokenWallet MUST be deployed.
    */
    function mint(
        uint128 amount,
        address recipient,
        uint128 deployWalletValue,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        onlyRootOwner
    {
        require(_mintEnabled(), TokenErrors.MINT_DISABLED);
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(recipient.value != 0, TokenErrors.WRONG_RECIPIENT);

        tvm.rawReserve(_reserve(), 0);
        _mint(amount, recipient, deployWalletValue, remainingGasTo, notify, payload);
    }

    /**
     * @dev See {ITokenRoot-acceptBurn}.
     *
     * Preconditions:
     *
     *  - Burning should be allowed on the {TokenRoot} contract.
     *  - Sender should be a valid token wallet deployed by this contract.
     *
     * Postconditions:
     *
     *  - The `totalSupply_` must decrease by the `amount` that is burned.
     *  - If `callbackTo` is not set, `remainingGasTo` will receive the
     *    remaining gas, otherwise {IAcceptTokensBurnCallback-onAcceptTokensBurn}
     *    will be called on the `callbackTo` contract.
    */
    function acceptBurn(
        uint128 amount,
        address walletOwner,
        address remainingGasTo,
        address callbackTo,
        TvmCell payload
    )
        override
        external
        functionID(0x192B51B1)
    {
        require(_burnEnabled(), TokenErrors.BURN_DISABLED);
        require(msg.sender == _getExpectedWalletAddress(walletOwner), TokenErrors.SENDER_IS_NOT_VALID_WALLET);

        tvm.rawReserve(address(this).balance - msg.value, 2);

        totalSupply_ -= amount;

        if (callbackTo.value == 0) {
            remainingGasTo.transfer({
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            });
        } else {
            IAcceptTokensBurnCallback(callbackTo).onAcceptTokensBurn{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                amount,
                walletOwner,
                msg.sender,
                remainingGasTo,
                payload
            );
        }

    }

    // =============== Support functions ==================

    /**
     * @dev Realization of {TokenRootBase-mint} function.
     *
     * Postcondition:
     *
     *  - `totalSupply_` is increased by `amount`.
     *  - If `deployWalletValue` is zero
     *    then `balance` of `recipient` is increased by `amount`.
     *  - Else, new {TokenWallet} is deployed with initial balance equal to `deployWalletValue`.
     *  - {ITokenWallet-acceptMint} is called on the deployed wallet.
     *
     * NOTE: We pass `bounce` flag true in acceptMint, so that
     * in the TokenWallet cannot accept the mint, then TokenWallet will bounce
     * to the current {onBounce}, and the `totalSupply` will be decreased by `amount`.
     */
    function _mint(
        uint128 amount,
        address recipient,
        uint128 deployWalletValue,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        internal
    {
        TvmCell stateInit = _buildWalletInitData(recipient);

        address recipientWallet;

        if(deployWalletValue > 0) {
            recipientWallet = _deployWallet(stateInit, deployWalletValue, remainingGasTo);
        } else {
            recipientWallet = address(tvm.hash(stateInit));
        }

        totalSupply_ += amount;

        ITokenWallet(recipientWallet).acceptMint{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            remainingGasTo,
            notify,
            payload
        );
    }

    /**
     * @dev Derive wallet address from owner.
     *
     * The function uses the `tvm.hash`, that computes the representation
     * hash of of the wallet `StateInit` data and returns it as a 256-bit unsigned
     * integer, then converted to an address.
     *
     * For string and bytes it computes hash of the tree of cells that contains
     * data but not data itself.
     *
     * This allows the contract to determine the expected address of a wallet
     * based on its owner's address. See sha256 to count hash of data.
     *
     * @param walletOwner Token wallet owner address
     * @return Token wallet address
    */
    function _getExpectedWalletAddress(address walletOwner) internal view returns (address) {
        return address(tvm.hash(_buildWalletInitData(walletOwner)));
    }

    /**
     * @dev On-bounce handler.
     *
     * Used in case {ITokenWallet-acceptMint} fails so the `totalSupply_`
     * can be decreased back.
     *
     * @param slice body of the bounced message.
     *
     * Postcondition:
     *
     *  - `totalSupply_` is decreased by the amount of tokens that was passed
     *    to `acceptMint`.
    */
    onBounce(TvmSlice slice) external {
        if (slice.decode(uint32) == tvm.functionId(ITokenWallet.acceptMint)) {
            totalSupply_ -= slice.decode(uint128);
        }
    }

    /**
     * @dev Withdraw all surplus balance in EVERs.
     * @dev Can by called only by owner address.
     *
     * @param to Recipient address of the surplus balance.
     *
     * NOTE: We pass flag ALL_NOT_RESERVED, so that message carries
     * all the remaining balance of the current smart contract. Parameter value is ignored.
     * The contract's balance will be equal to zero after the message processing.
     *
     * See {https://github.com/tonlabs/TON-Solidity-Compiler/blob/master/API.md#addresstransfer}
     * for more details about flags.
     */
    function sendSurplusGas(address to) external view onlyRootOwner {
        tvm.rawReserve(_targetBalance(), 0);
        to.transfer({
            value: 0,
            flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
            bounce: false
        });
    }

    /**
     * @dev Calculates reserve EVERs for the remainder of the contract that
     * subsequent output actions cannot spend more money than the remainder.
     *
     * @return Reserve EVERs
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
     * @dev Checks if minting is enabled.
     *
     * @return Boolean value indicating if minting is enabled.
     */
    function _mintEnabled() virtual internal view returns (bool);

    /**
     * @dev Checks if burning is enabled.
     *
     * @return Boolean value indicating if burning is enabled.
     */
    function _burnEnabled() virtual internal view returns (bool);

    /**
     * @dev Builds the wallet `StateInit` data.
     * @param walletOwner The owner of the wallet for which the `WalletInitData` is being building.
     * @return The Wallet `StateInit` data.
     */
    function _buildWalletInitData(address walletOwner) virtual internal view returns (TvmCell);

    /**
     * @dev Deploys new token wallet.
     * @param initData wallet `StateInit` data.
     * @param deployWalletValue value for deploy wallet.
     * @param remainingGasTo address for remaining gas.
     * @return deployed wallet address.
     */
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address remainingGasTo) virtual internal view returns (address);

}
