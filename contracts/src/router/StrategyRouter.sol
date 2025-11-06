// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/Ipool.sol";
import {UserAccount} from "../accounts/UserAccount.sol";
import {AccountFactory} from "../factory/AccountFactory.sol";

contract StrategyRouter {
    IPool public immutable AAVE_POOL;
    AccountFactory public immutable factory;

    error ZeroAddress();
    error ZeroAmount();
    error TransferFromFailed();
    error TransferFailed();

    constructor(address aavePool, address _factory) {
        if (aavePool == address(0)) revert ZeroAddress();
        if (_factory == address(0)) revert ZeroAddress();
        AAVE_POOL = IPool(aavePool);
        factory = AccountFactory(_factory);
    }

    /// @notice 호출 전: 사용자는 반드시 supplyAsset.approve(address(this), supplyAmount)를 먼저 실행해야 함
    function openPosition(
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset
    ) external {
        if (supplyAsset == address(0)) revert ZeroAddress();
        if (borrowAsset == address(0)) revert ZeroAddress();
        if (supplyAmount == 0) revert ZeroAmount();

        // user vault 주소 가져오기
        address userAccount = factory.getOrCreate(msg.sender);

        // user -> router : 담보 토큰 가져오기 (사전 approve 필요)
        if (
            !IERC20(supplyAsset).transferFrom(
                msg.sender,
                address(this),
                supplyAmount
            )
        ) revert TransferFromFailed();

        // router -> userAccount : 담보 입금
        if (!IERC20(supplyAsset).transfer(userAccount, supplyAmount))
            revert TransferFailed();

        // userAccount -> aave : supply
        UserAccount(userAccount).supply(supplyAsset, supplyAmount);
    }
}
