// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UserAccount} from "../accounts/UserAccount.sol";

contract AccountFactory {
    address public immutable aavePool;
    mapping(address => address) public accountOf;

    error Exists();

    constructor(address _aavePool) {
        aavePool = _aavePool;
    }

    function getOrCreate(
        address _owner
    ) external returns (address userAccount) {
        userAccount = accountOf[_owner];
        if (userAccount == address(0)) {
            userAccount = address(new UserAccount());
            UserAccount(userAccount).init(_owner, aavePool);
            accountOf[_owner] = userAccount;
        }
    }
}
