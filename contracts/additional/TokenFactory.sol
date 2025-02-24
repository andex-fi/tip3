pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./ITokenFactory.sol";
import "../libraries/TokenErrors.sol";
import "../libraries/TokenMsgFlag.sol";
import "../TokenRoot.sol";
import "../TokenRootUpgradeable.sol";

/**
 * @title TokenFactory
 * @dev This contract is used to create new {TokenRoot} and {TokenRootUpgradeable}.
 */
contract TokenFactory is ITokenFactory {

    uint256 static _randomNonce;

    address public _owner;
    address public _pendingOwner;
    uint256 public _tokenNonce;
    uint128 public _deployValue;

    TvmCell public _rootCode;
    TvmCell public _walletCode;

    TvmCell public _rootUpgradeableCode;
    TvmCell public _walletUpgradeableCode;
    TvmCell public _platformCode;

    /**
     * @dev Modifier than throws if called by any account other than the `owner_`.
     */
    modifier onlyOwner {
        require(msg.sender == _owner && _owner.value != 0, TokenErrors.NOT_OWNER);
        _;
    }

    /**
     * @dev Modifier that returns all remaining gas to the caller.
     */
    modifier cashBack {
        _;
        msg.sender.transfer({value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false});
    }

    /**
     * @dev This is the constructor for the token factory contract,
     * which is used to deploy token root contracts.
     *
     * @param owner The owner of the factory.
     * @param deployValue The value to be sent to the token root contract
     *        upon deployment. This is typically used to transfer initial funds
     *        to the contract.
     * @param rootCode The code of the {TokenRoot} contract, which serves as
     *        the base contract for deployed token contracts.
     * @param walletCode The code of the {TokenWallet} contract, which can be
     *        used to create wallet contracts.
     * @param rootUpgradeableCode The code of the {TokenRootUpgradeable} contract,
     *        which is an upgradeable version of the {TokenRoot} contract.
     *        This contract can be updated without redeploying it.
     * @param walletUpgradeableCode The code of the {TokenWalletUpgradeable}
     *        contract, which is an upgradeable version of the {TokenWallet} contract.
     *        This contract can be updated without redeploying it.
     * @param platformCode Code of the {TokenWalletPlatform} contract.
    */
    constructor(
        address owner,
        uint128 deployValue,
        TvmCell rootCode,
        TvmCell walletCode,
        TvmCell rootUpgradeableCode,
        TvmCell walletUpgradeableCode,
        TvmCell platformCode
    ) public {
        tvm.accept();
        _owner = owner;
        _deployValue = deployValue;
        _rootCode = rootCode;
        _walletCode = walletCode;
        _rootUpgradeableCode = rootUpgradeableCode;
        _walletUpgradeableCode = walletUpgradeableCode;
        _platformCode = platformCode;
    }

    /**
     * @dev See {ITokenFactory-deployRoot}.
     */
    function deployRoot(
        string name,
        string symbol,
        uint8 decimals,
        address owner,
        address initialSupplyTo,
        uint128 initialSupply,
        uint128 deployWalletValue,
        bool mintDisabled,
        bool burnByRootDisabled,
        bool burnPaused,
        address remainingGasTo,
        bool upgradeable
    ) external responsible override returns (address) {
        tvm.rawReserve(address(this).balance - msg.value, 0);
        function (uint256, string, string, uint8, address) returns (TvmCell) buildStateInit =
            upgradeable ? _buildUpgradeableStateInit : _buildCommonStateInit;
        TvmCell stateInit = buildStateInit(_tokenNonce++, name, symbol, decimals, owner);
        // constructors of `TokenRoot` and `TokenRootUpgradeable` have the same signatures and the same functionID
        // so use `new TokenRoot` for both roots
        address root = new TokenRoot {
            value: _deployValue,
            flag: TokenMsgFlag.SENDER_PAYS_FEES,
            bounce: false,
            stateInit: stateInit
        }(
            initialSupplyTo,
            initialSupply,
            deployWalletValue,
            mintDisabled,
            burnByRootDisabled,
            burnPaused,
            remainingGasTo
        );
        return {value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: false} root;
    }

    /**
     * @dev Builds a `StateInit` for the common {TokenRoot} contract.
     *
     * @param nonce - nonce of the token
     * @param name - name of the token
     * @param symbol - symbol of the token
     * @param decimals - number of decimals of the token
     * @param owner - owner of the token
     *
     * @return `StateInit` for the TokenRoot contract.
     */
    function _buildCommonStateInit(
        uint256 nonce,
        string name,
        string symbol,
        uint8 decimals,
        address owner
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenRoot,
            varInit: {
                randomNonce_: nonce,
                deployer_: address(this),
                name_: name,
                symbol_: symbol,
                decimals_: decimals,
                rootOwner_: owner,
                walletCode_: _walletCode
            },
            code: _rootCode,
            pubkey: 0
        });
    }
    /**
     * @dev Builds a `StateInit` for the {TokenRootUpgradeable} contract.
     *
     * @param nonce - nonce of the token
     * @param name - name of the token
     * @param symbol - symbol of the token
     * @param decimals - number of decimals of the token
     * @param owner - owner of the token
     *
     * @return `StateInit`.
     */
    function _buildUpgradeableStateInit(
        uint256 nonce,
        string name,
        string symbol,
        uint8 decimals,
        address owner
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenRootUpgradeable,
            varInit: {
                randomNonce_: nonce,
                deployer_: address(this),
                name_: name,
                symbol_: symbol,
                decimals_: decimals,
                rootOwner_: owner,
                walletCode_: _walletUpgradeableCode,
                platformCode_: _platformCode
            },
            code: _rootUpgradeableCode,
            pubkey: 0
        });
    }
    /**
     * @dev Changes the value to be sent to the root contract when deploying
     * a new token root.
     * @param deployValue New value to be sent to the root contract.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *  - `_deployValue` is changed to `deployValue`.
     */
    function changeDeployValue(uint128 deployValue) public onlyOwner cashBack {
        _deployValue = deployValue;
    }

    /**
     * @dev Changes the rootCode.
     * @param rootCode - new rootCode
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_rootCode` is changed to `rootCode`.
     */
    function changeRootCode(TvmCell rootCode) public onlyOwner cashBack {
        _rootCode = rootCode;
    }

    /**
     * @dev Changes the code of the TokenWallet contract, which is used
     * to deploy new wallets.
     * @param walletCode New code of the TokenWallet contract.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_walletCode` is changed to `walletCode`.

     */
    function changeWalletCode(TvmCell walletCode) public onlyOwner cashBack {
        _walletCode = walletCode;
    }

    /**
     * @dev Changes the code of the {TokenRootUpgradeable} contract, which
     * is used to deploy new token roots.
     * @param rootUpgradeableCode New code of the TokenRootUpgradeable contract.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_rootUpgradeableCode` is changed to `rootUpgradeableCode`.
     */
    function changeRootUpgradeableCode(TvmCell rootUpgradeableCode) public onlyOwner cashBack {
        _rootUpgradeableCode = rootUpgradeableCode;
    }

    /**
     * @dev Changes the code of the {TokenWalletUpgradeable} contract,
     * which is used to deploy new token roots.
     * @param walletUpgradeableCode New code of the TokenWalletUpgradeable contract.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_walletUpgradeableCode` is changed to `walletUpgradeableCode`.
     */
    function changeWalletUpgradeableCode(TvmCell walletUpgradeableCode) public onlyOwner cashBack {
        _walletUpgradeableCode = walletUpgradeableCode;
    }

    /**
     * @dev Changes the code of the {TokenWalletPlatform} contract, which
     * is used to deploy new token roots.
     *
     * @param platformCode New code of the TokenWalletPlatform contract.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_platformCode` is changed to `platformCode`.
     */
    function changePlatformCode(TvmCell platformCode) public onlyOwner cashBack {
        _platformCode = platformCode;
    }

    /**
     * @dev Changes the owner of the factory.
     *
     * It's two-step process: first, the new pending owner is set,
     * then the pending owner can accept the ownership.
     *
     * @param owner New owner of the factory.
     *
     * Precondition:
     *
     *  - Should be called only by the owner.
     *
     * Postcondition:
     *
     *  - `_pendingOwner` is changed to `owner`.
     */
    function transferOwner(address owner) public onlyOwner cashBack {
        _pendingOwner = owner;
    }

    /**
     * @dev Accepts the ownership of the factory.
     *
     * It's two-step process: first, the new pending owner is set,
     * then the pending owner can accept the ownership.
     *
     * Precondition:
     *
     *  - Sender should be the pending owner.
     *  - Pending owner should not be zero.
     *
     * Postcondition:
     *
     *  - `_owner` is changed to `_pendingOwner`.
     *  - `_pendingOwner` is changed to zero.
     */
    function acceptOwner() public cashBack {
        require(msg.sender == _pendingOwner && _pendingOwner.value != 0, TokenErrors.NOT_OWNER);
        _owner = _pendingOwner;
        _pendingOwner = address(0);
    }

    /**
     * @dev Upgrades the factory code to a new version.
     *
     * @param code New code of the factory.
     *
     * Precondition:
     *
     * - Should be called only by the owner.
     *
     * Postcondition:
     *
     * - Factory code is changed to `code`.
     */
    function upgrade(TvmCell code) public onlyOwner {
        TvmBuilder common;
        common.store(_rootCode);
        common.store(_walletCode);

        TvmBuilder upgradeable;
        upgradeable.store(_rootUpgradeableCode);
        upgradeable.store(_walletUpgradeableCode);
        upgradeable.store(_platformCode);

        TvmBuilder builder;
        builder.store(_owner);
        builder.store(_pendingOwner);
        builder.store(_tokenNonce);
        builder.store(_deployValue);
        builder.storeRef(common);
        builder.storeRef(upgradeable);

        tvm.setcode(code);
        tvm.setCurrentCode(code);
        onCodeUpgrade(builder.toCell());
    }

    /**
     * @dev Called when the factory code is upgraded for rewriting the storage.
     * @param data Data of the factory.
     *
     * Postcondition:
     *
     *  - Factory storage is rewritten.
     */
    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();
        TvmSlice slice = data.toSlice();
        (_owner, _pendingOwner, _tokenNonce, _deployValue) = slice.decode(address, address, uint256, uint128);

        TvmSlice common = slice.loadRefAsSlice();
        _rootCode = common.loadRef();
        _walletCode = common.loadRef();

        TvmSlice upgradeable = slice.loadRefAsSlice();
        _rootUpgradeableCode = upgradeable.loadRef();
        _walletUpgradeableCode = upgradeable.loadRef();
        _platformCode = upgradeable.loadRef();
    }

}
