// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IAaveProtocolDataProvider {
    struct TokenData {
        string symbol;
        address tokenAddress;
    }

    function getAllReservesTokens() external view returns (TokenData[] memory);

    function getReserveConfigurationData(
        address asset
    )
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
    function getReserveTokensAddresses(
        address asset
    )
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        );

    function getReserveCaps(
        address asset
    ) external view returns (uint256 borrowCap, uint256 supplyCap);
    // 배포에 따라 없을 수 있으므로 try/catch로 호출 예정
    function getPaused(address asset) external view returns (bool);
}
