// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {
    IAaveProtocolDataProvider
} from "../../src/interfaces/aave-v3/IAaveProtocolDataProvider.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

interface IPoolLite {
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLite {
    function getPriceOracle() external view returns (address);
}

/**
 * @dev Thin probe against live Aave V3 Sepolia.
 *      Not a unit test – used to understand which assets are realistically
 *      supplyable / borrowable for a given USER_ADDRESS, with the same rules
 *      the official UI uses.
 */
contract AaveSepoliaProbeTest is Test {
    address private providerAddr;
    address private poolAddr;
    IAaveProtocolDataProvider private data;
    address private userAddr;

    function setUp() public {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        userAddr = vm.envAddress("USER_ADDRESS");
        providerAddr = vm.envAddress("AAVE_POOL_ADDRESSES_PROVIDER");
        poolAddr = vm.envAddress("AAVE_POOL");
        address dataAddr = vm.envAddress("AAVE_PROTOCOL_DATA_PROVIDER");
        require(providerAddr != address(0), "PROVIDER missing");
        require(poolAddr != address(0), "POOL missing");
        require(dataAddr != address(0), "DATA_PROVIDER missing");
        require(userAddr != address(0), "USER_ADDRESS missing");

        data = IAaveProtocolDataProvider(dataAddr);

        vm.label(providerAddr, "AAVE_PROVIDER");
        vm.label(poolAddr, "AAVE_POOL");
        vm.label(address(data), "AAVE_PROTOCOL_DATA_PROVIDER");
    }

    /// @dev Log assets that are both protocol-supplyable and actually held by userAddr.
    function test_printSupplyableForUser() public view {
        console2.log("=== Aave V3 Sepolia: Supplyable Probe (latest) ===");
        console2.log("Provider:", vm.toString(providerAddr));
        console2.log("Pool    :", vm.toString(poolAddr));
        console2.log("Data    :", vm.toString(address(data)));
        console2.log("-----------------------------------------------");

        IAaveProtocolDataProvider.TokenData[] memory list = data
            .getAllReservesTokens();
        console2.log("reserves :", list.length);

        for (uint256 i = 0; i < list.length; i++) {
            address asset = list[i].tokenAddress;

            (
                uint256 decimals,
                ,
                ,
                ,
                ,
                bool usageAsCollateralEnabled, // whether the asset can be used as collateral (supply itself may still be allowed)
                ,
                ,
                bool isActive, // inactive reserves cannot be supplied or borrowed
                bool isFrozen // frozen reserves allow repay/withdraw only
            ) = data.getReserveConfigurationData(asset);

            bool paused = false;
            try data.getPaused(asset) returns (bool p) {
                // emergency kill-switch that can block supply/borrow even if not frozen
                paused = p;
            } catch {}
            // caps & aToken total supply
            (, uint256 supplyCap) = data.getReserveCaps(asset); // (borrowCap, supplyCap) – per-reserve supply ceiling
            (address aTokenAddr, , ) = data.getReserveTokensAddresses(asset);
            uint256 aTotal = aTokenAddr == address(0)
                ? 0
                : IERC20(aTokenAddr).totalSupply();

            // normalize cap to token units: cap * 10**decimals
            bool capOk = (supplyCap == 0) ||
                (aTotal < supplyCap * (10 ** decimals));

            // user’s wallet balance for this underlying
            uint256 userBal = IERC20(asset).balanceOf(userAddr);
            bool userHas = (userBal > 0);

            // protocol-level supply allowed?
            bool protocolOk = (isActive && !isFrozen && !paused && capOk);

            // mirrors the condition for the "Supply" button being enabled in the UI
            bool buttonOn = (protocolOk && userHas);

            // log only the assets that are actually supplyable for this user
            if (buttonOn) {
                console2.log("----------------------------------------");
                console2.log("symbol:", list[i].symbol);
                console2.log("asset:");
                console2.logAddress(asset);
                console2.log("aToken:");
                console2.logAddress(aTokenAddr);
                console2.log("decimals:", decimals);
                console2.log("user balance:", userBal);
                console2.log("=> BUTTON_ON (supplyable for user):", buttonOn);
            }

            // WETH → ETH:
            // WETH: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
            if (asset == 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c) {
                // treat native ETH as a "virtual" supply option via the WETH reserve

                uint256 userEth = userAddr.balance; // native ETH
                bool ethButtonOn = protocolOk && (userEth > 0);
                if (ethButtonOn) {
                    console2.log("----------------------------------------");
                    console2.log("symbol: ETH (via WETH Gateway)");
                    console2.log("asset (WETH):");
                    console2.logAddress(asset);
                    console2.log("aToken:");
                    console2.logAddress(aTokenAddr);
                    console2.log("user balance (native ETH):", userEth);
                    console2.log("=> BUTTON_ON (supplyable for user):", true);
                }
            }
        }
    }

    /// @dev Log assets that are currently borrowable for userAddr under Aave rules.
    function test_printBorrowableForUser() public view {
        console2.log("===Borrowable FOR USER===");

        // base protocol handles
        IPoolLite pool = IPoolLite(poolAddr);
        address oracleAddr = IPoolAddressesProviderLite(providerAddr)
            .getPriceOracle();
        IPriceOracleGetter oracle = IPriceOracleGetter(oracleAddr);

        // user’s total borrow capacity in base currency units
        (, , uint256 availableBase, , , ) = pool.getUserAccountData(userAddr);

        IAaveProtocolDataProvider.TokenData[] memory list = data
            .getAllReservesTokens();
        for (uint256 i = 0; i < list.length; i++) {
            address asset = list[i].tokenAddress;

            // protocol flags + borrowCap
            (
                uint256 decimals,
                ,
                ,
                ,
                ,
                ,
                bool borrowingEnabled,
                ,
                bool isActive,
                bool isFrozen
            ) = data.getReserveConfigurationData(asset);

            bool paused = false;
            try data.getPaused(asset) returns (bool p) {
                paused = p;
            } catch {}
            (uint256 borrowCap, ) = data.getReserveCaps(asset);
            (, address stableDebt, address variableDebt) = data
                .getReserveTokensAddresses(asset);

            uint256 debtStable = (stableDebt == address(0))
                ? 0
                : IERC20(stableDebt).totalSupply();
            uint256 debtVar = (variableDebt == address(0))
                ? 0
                : IERC20(variableDebt).totalSupply();
            uint256 totalDebt = debtStable + debtVar;
            bool capOk = (borrowCap == 0) ||
                (totalDebt < borrowCap * (10 ** decimals));

            bool protocolOk = (isActive &&
                !isFrozen &&
                !paused &&
                borrowingEnabled &&
                capOk);
            if (!protocolOk) continue;

            // pool-side liquidity check: cannot borrow what the pool does not have
            (address aTokenAddr, , ) = data.getReserveTokensAddresses(asset);
            uint256 availLiquidity = IERC20(asset).balanceOf(aTokenAddr);
            if (availLiquidity == 0) continue;

            // convert user’s residual borrow capacity into this asset’s units
            // (matches the "Available to borrow" column in UIs)
            uint256 priceBase = oracle.getAssetPrice(asset); // base currency 단가
            if (priceBase == 0) continue;

            // availableBase / price * 10**decimals
            uint256 userAvailInAsset = (availableBase * (10 ** decimals)) /
                priceBase;
            if (userAvailInAsset == 0) continue;

            // asset passes all guards → effectively "Borrow" button is enabled
            console2.log("----------------------------------------");
            console2.log("symbol:", list[i].symbol);
            console2.log("asset:");
            console2.logAddress(asset);
            console2.log("availableLiquidity:", availLiquidity);
            console2.log("userAvailInAsset:", userAvailInAsset);
            console2.log("=> BORROW_BUTTON_ON:", true);
        }
    }
}
