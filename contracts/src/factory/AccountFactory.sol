// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UserAccount} from "../accounts/UserAccount.sol";

contract AccountFactory {
    address public immutable provider;
    mapping(address => address) public accountOf;

    event AccountCreated(
        address indexed owner,
        address indexed account,
        address indexed operator
    );

    error Exists();
    error ZeroAddress();

    constructor(address _provider) {
        if (_provider == address(0)) revert ZeroAddress();
        provider = _provider;
    }

    /// @notice 라우터가 호출. operator = msg.sender 로 고정.
    function getOrCreate(
        address _owner
    ) external returns (address userAccount) {
        if (_owner == address(0)) revert ZeroAddress();

        userAccount = accountOf[_owner];
        if (userAccount == address(0)) {
            userAccount = address(new UserAccount(address(this), provider));
            UserAccount(userAccount).init(_owner, msg.sender);
            accountOf[_owner] = userAccount;
            emit AccountCreated(_owner, userAccount, msg.sender);
        }
    }
}
