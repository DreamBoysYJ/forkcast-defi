// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * AaveSepoliaProbe.t.sol
 * 목적: 세폴리아 Aave v3에서 유저의 현재 자산을 바탕으로, 예치(supply), 대출(borrow) 가능한 자산 찾기
 * - 포크 블록 최신
 * 필요 세팅 ENV (.env):
 *   SEPOLIA_RPC_URL=<https://sepolia.infura.io/v3/XXX 등>
 *   USER_ADDRESS=0x

 *
 * 실행:
 *   forge test -vvv
 */

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

    // 목적 : 예치 가능 (supplyable) 자산이면서 userAddr가 가진 자산들만 식별
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
                bool usageAsCollateralEnabled, // 담보로 사용 되는지 여부 (담보 사용 안되도 예치가 가능할 수도 있음)
                ,
                ,
                bool isActive, // 리저브 활성화 여부 (false - 공급/대출 둘 다 불가)
                bool isFrozen // 동결 상태 (새 공급/새 대출 막힘, 상환/인출만 허용)
            ) = data.getReserveConfigurationData(asset);

            bool paused = false;
            try data.getPaused(asset) returns (bool p) {
                // frozen은 상환/인출은 허용되는데, 이것도 막을 수 있는 긴급 스위치 체크
                paused = p;
            } catch {}
            // caps & aToken total supply
            (, uint256 supplyCap) = data.getReserveCaps(asset); // (borrowCap, supplyCap) // 리저브 별 공급 상한
            (address aTokenAddr, , ) = data.getReserveTokensAddresses(asset);
            uint256 aTotal = aTokenAddr == address(0) // 현재 공급 내용
                ? 0
                : IERC20(aTokenAddr).totalSupply();

            // cap 단위 보정: cap * 10**decimals 와 비교
            bool capOk = (supplyCap == 0) ||
                (aTotal < supplyCap * (10 ** decimals));

            // 사용자의 해당 자산 잔액
            uint256 userBal = IERC20(asset).balanceOf(userAddr);
            bool userHas = (userBal > 0);

            // 프로토콜 레벨로 가능한가?
            bool protocolOk = (isActive && !isFrozen && !paused && capOk);

            // 실제 UI의 Supply 버튼 ON과 동일한 조건
            bool buttonOn = (protocolOk && userHas);

            // === 출력: 버튼 ON인 것만 ===
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
                // ETH 별칭 처리: WETH 리저브 + 네이티브 잔액으로 별도 항목

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

    // 목적 : 현재 userAddr 기준으로 빌릴 수 있는 자산만 식별 ======
    function test_printBorrowableForUser() public view {
        console2.log("===Borrowable FOR USER===");

        // 준비: 풀/오라클
        IPoolLite pool = IPoolLite(poolAddr);
        address oracleAddr = IPoolAddressesProviderLite(providerAddr)
            .getPriceOracle();
        IPriceOracleGetter oracle = IPriceOracleGetter(oracleAddr);

        // 내 총 대출 여력
        (, , uint256 availableBase, , , ) = pool.getUserAccountData(userAddr);

        IAaveProtocolDataProvider.TokenData[] memory list = data
            .getAllReservesTokens();
        for (uint256 i = 0; i < list.length; i++) {
            address asset = list[i].tokenAddress;

            // 프로토콜 플래그 + borrowCap
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

            // 풀 가용 유동성 (없으면 못 빌림)
            (address aTokenAddr, , ) = data.getReserveTokensAddresses(asset);
            uint256 availLiquidity = IERC20(asset).balanceOf(aTokenAddr);
            if (availLiquidity == 0) continue;

            // 네 대출 여력을 토큰 수량으로 환산 (UI의 "Available" 열과 동일한 개념)
            uint256 priceBase = oracle.getAssetPrice(asset); // base currency 단가
            if (priceBase == 0) continue;

            // availableBase / price * 10**decimals
            uint256 userAvailInAsset = (availableBase * (10 ** decimals)) /
                priceBase;
            if (userAvailInAsset == 0) continue;

            // 통과 → 출력
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
