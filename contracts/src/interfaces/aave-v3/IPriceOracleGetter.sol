// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256); // base currency (1e8)
    function BASE_CURRENCY_UNIT() external view returns (uint256); // 보통 1e8
}
