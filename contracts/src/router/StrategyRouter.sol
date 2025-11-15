// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AaveModule} from "./AaveModule.sol";
import {UniswapV4Module} from "./UniswapV4Module.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";

import {IERC20} from "../interfaces/IERC20.sol";

contract StrategyRouter is AaveModule, UniswapV4Module {
    event PositionOpened(
        address indexed user,
        address indexed vault,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 borrowedAmount,
        uint256 tokenId,
        uint256 amount0ForLp,
        uint256 amount1ForLp,
        uint256 spent0,
        uint256 spent1
    );

    /// @param addressesProvider Aave V3 PoolAddressesProvider (Sepolia)
    /// @param dataProvider      AaveProtocolDataProvider (Sepolia)
    /// @param _factory          AccountFactory
    constructor(
        address addressesProvider,
        address _factory,
        address dataProvider,
        address _swapRouter,
        address _positionManager,
        address _permit2
    )
        AaveModule(addressesProvider, _factory, dataProvider)
        UniswapV4Module(_swapRouter, _positionManager)
    {
        permit2 = IPermit2(_permit2);
    }

    /// @dev 이미 sepolia에서 init 된 v4 Pool 정보를 admin이 한 번 더 세팅
    function setUniswapV4PoolConfig(
        PoolKey memory key,
        int24 defaultTickLower,
        int24 defaultTickUpper
    ) external onlyAdmin {
        _setUniswapV4PoolConfig(key, defaultTickLower, defaultTickUpper);
    }

    /// @notice 호출 전: 사용자는 반드시 supplyAsset.approve(address(this), supplyAmount)를 먼저 실행해야 함
    function openPosition(
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18 // 0이면 1.35e18로 처리
    ) external {
        // Aave-v3 (Supply -> Borrow)
        (address userAccount, uint256 borrowedAmount) = _openAavePosition(
            msg.sender,
            supplyAsset,
            supplyAmount,
            borrowAsset,
            targetHF1e18
        );

        if (borrowedAmount == 0) {
            return;
        }

        // 2) Uniswap v4: Router가 들고 있는 borrowedAmount를 사용해서
        //    - 절반 스왑해서 0/1 비율 맞추고
        //    - vault 소유의 LP 포지션 생성
        (
            uint256 tokenId,
            uint256 spent0,
            uint256 spent1,
            uint256 amount0ForLp,
            uint256 amount1ForLp
        ) = _enterUniswapV4Position(userAccount, borrowAsset, borrowedAmount);

        // 3)
        emit PositionOpened(
            msg.sender,
            userAccount,
            supplyAsset,
            supplyAmount,
            borrowAsset,
            borrowedAmount,
            tokenId,
            amount0ForLp,
            amount1ForLp,
            spent0,
            spent1
        );
    }

    function initPermit2(
        address token0,
        address token1,
        address poolManager
    ) external onlyAdmin {
        // 1) 토큰 → Permit2 allowance
        IERC20(token0).approve(address(permit2), type(uint256).max);
        IERC20(token1).approve(address(permit2), type(uint256).max);

        // 2) Permit2 내부 allowance (owner = StrategyRouter, spender = PoolManager)
        permit2.approve(
            token0,
            poolManager,
            type(uint160).max,
            type(uint48).max
        );
        permit2.approve(
            token1,
            poolManager,
            type(uint160).max,
            type(uint48).max
        );
    }
}
