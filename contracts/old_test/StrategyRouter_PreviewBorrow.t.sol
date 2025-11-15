// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {UserAccount} from "../src/accounts/UserAccount.sol";
import {AccountFactory} from "../src/factory/AccountFactory.sol";
import {StrategyRouter} from "../src/router/StrategyRouter.sol";
import {IERC20, IERC20Metadata} from "../src/interfaces/IERC20.sol";
import {
    IPoolAddressesProvider
} from "../src/interfaces/aave-v3/IPoolAddressesProvider.sol";

import {IPool} from "../src/interfaces/aave-v3/IPool.sol";
import {
    IAaveProtocolDataProvider
} from "../src/interfaces/aave-v3/IAaveProtocolDataProvider.sol";

contract StrategyRouterPreviewBorrow is Test {
    // --- External infra (Sepolia) ---
    IAaveProtocolDataProvider public dataProvider;
    IPool public aavePool; // derived from provider
    address public dataAddr; // ProtocolDataProvider
    address public providerAddr; // Aave V3 PoolAddressesProvider
    address public AAVE; // sample ERC20 for tests
    address public WBTC;

    // --- Actors ---
    address public user;
    address public admin;

    // --- System Under Test ---
    AccountFactory public factory;
    StrategyRouter public router;

    // -- Helpers ---
    function _scale(
        address token,
        uint256 raw
    ) internal view returns (uint256) {
        uint8 d = IERC20Metadata(token).decimals();
        return raw * (10 ** uint256(d));
    }

    function setUp() public {
        // 1) Fork Sepolia
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        assertEq(block.chainid, 11155111, "not on sepolia");

        // 2) Load external addresses
        providerAddr = vm.envAddress("AAVE_POOL_ADDRESSES_PROVIDER");
        require(providerAddr != address(0), "PROVIDER missing");
        dataAddr = vm.envAddress("AAVE_PROTOCOL_DATA_PROVIDER");
        require(dataAddr != address(0), "DATA_PROVIDER missing");
        AAVE = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        require(AAVE != address(0), "AAVE token missing");
        WBTC = vm.envAddress("WBTC_UNDERLYING_SEPOLIA");
        require(WBTC != address(0), "WBTC token missing");

        // 3) Basic code existence checks
        assertGt(
            address(IPoolAddressesProvider(providerAddr)).code.length,
            0,
            "provider has no code"
        );
        assertGt(address(dataAddr).code.length, 0, "dataProvider has no code");
        assertGt(address(AAVE).code.length, 0, "AAVE token has no code");

        // 4) Dervive pool from provider & validate

        aavePool = IPool(IPoolAddressesProvider(providerAddr).getPool());
        assertGt(address(aavePool).code.length, 0, "pool has no code");
        assertEq(
            IPoolAddressesProvider(providerAddr).getPool(),
            address(aavePool),
            "provider -> pool mismatch"
        );

        // 5) Bind data provider
        dataProvider = IAaveProtocolDataProvider(dataAddr);

        // 6) Prepare actors
        user = makeAddr("USER");
        admin = makeAddr("ADMIN");
        vm.deal(user, 1 ether);
        vm.deal(admin, 10 ether);

        // 7) Seed ERC20 to user
        uint256 amt = _scale(AAVE, 1000);
        deal(AAVE, user, amt);
        assertEq(IERC20(AAVE).balanceOf(user), amt, "user token seed failed");

        // 8) Deploy AccountFactory.sol + StrategyRouter.sol
        vm.startPrank(admin);
        factory = new AccountFactory(providerAddr);
        assertGt(address(factory).code.length, 0, "factory not deployed");

        router = new StrategyRouter(
            providerAddr,
            address(factory),
            address(dataAddr)
        );
        assertGt(address(router).code.length, 0, "router not deployed");

        vm.stopPrank();
    }

    /// @notice Sanity: all wiring must be vaild before higher-level tests
    function test_setup_isValid() public view {
        // provider/pool/dataprovider codes checked in setUp: repeat key invariants:
        assertEq(block.chainid, 11155111, "wrong chain id");
        assertEq(
            IPoolAddressesProvider(providerAddr).getPool(),
            address(aavePool),
            "poold drifted"
        );
        // ensure token still funded
        assertGt(IERC20(AAVE).balanceOf(user), 0, "user has no token balance");
        // factory/router alive
        assertGt(address(factory).code.length, 0, "factory code missing");
        assertGt(address(router).code.length, 0, "router code missing");
    }

    /// @dev Vault 없는 User가 PreviewBorrow를 실행해도 revert 안되고 정상동작 해야.
    function test_PreviewBorrow_NewUser_NoValut_Succeeds() public {
        vm.startPrank(user);

        // user Valut 없어야
        address userVault = factory.accountOf(user);
        assertEq(userVault, address(0), "user must have no Vault");

        // previewBorrow 호출
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user) / 2;
        (
            uint256 finalToken,
            uint256 projectedHF1e18,
            uint256 byHFToken,
            uint256 policyMaxToken,
            uint256 capRemainingToken,
            uint256 liquidityToken,
            uint256 collBeforeBase,
            uint256 debtBeforeBase,
            uint256 collAfterBase,
            uint256 ltBeforeBps,
            uint256 ltAfterBps
        ) = router.previewBorrow(user, AAVE, supplyAmt, WBTC, 0);

        // previewBorrow 호출해도 vault 생성되면 안 됨.
        assertEq(userVault, address(0), "preview must not create Vault");

        // before/after 계정 상태 비교
        assertEq(
            collBeforeBase,
            0,
            "new user must have zero collBeforeBase before"
        );
        assertEq(
            debtBeforeBase,
            0,
            "new user must have zero debtBeforeBase before"
        );
        assertGt(
            collAfterBase,
            0,
            "collAfterBase after privew must be positive"
        );
        assertGt(
            ltAfterBps,
            ltBeforeBps,
            "LT after should not be lower htan before"
        );

        assertGt(projectedHF1e18, 0, "projected HF must be positive");

        assertLe(
            finalToken,
            byHFToken,
            "finalToken must respect HF-based limit"
        );
        assertLe(
            finalToken,
            policyMaxToken,
            "finalToken must respect policyMaxToken"
        );
        assertLe(
            finalToken,
            capRemainingToken,
            "finalToken must respect capRemainingToken"
        );
        assertLe(
            finalToken,
            liquidityToken,
            "finalToken must respect liquidityToken"
        );
    }

    /// @dev PreviewBorrow 결과와 openPosition 결과의 일치성 체크
    function test_PreviewBorrow_ConsistentWithOpenPosition() public {
        // approve (user -> router)

        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user) / 2;
        bool ok = IERC20(AAVE).approve(address(router), supplyAmt);
        assertTrue(ok, "approve failed");
        uint256 targetHF1e18 = 1.7e18;

        // user Valut 없어야
        address userVault = factory.accountOf(user);
        assertEq(userVault, address(0), "user must have no Vault");

        // previewBorrow 호출
        (
            uint256 finalToken,
            uint256 projectedHF1e18,
            uint256 byHFToken,
            uint256 policyMaxToken,
            uint256 capRemainingToken,
            uint256 liquidityToken,
            uint256 collBeforeBase,
            uint256 debtBeforeBase,
            uint256 collAfterBase,
            uint256 ltBeforeBps,
            uint256 ltAfterBps
        ) = router.previewBorrow(user, AAVE, supplyAmt, WBTC, targetHF1e18);

        assertGt(finalToken, 0, "finalToken must be > 0 ");
        assertGt(projectedHF1e18, 0, "projected HF must be > 0");

        // 새 유저라면 before 값은 0이어야
        assertEq(collBeforeBase, 0, "new user collateral before must be 0");
        assertEq(debtBeforeBase, 0, "new user debt before must be 0");
        assertGt(
            collAfterBase,
            collBeforeBase,
            "collateral after must increase"
        );
        assertGt(ltAfterBps, 0, "ltAfterBps must be > 0");

        // 최종 차입량은 각 제한 값들을 초과하면 안 됨
        assertLe(
            finalToken,
            byHFToken,
            "finalToken must respect HF-based limit"
        );
        assertLe(
            finalToken,
            policyMaxToken,
            "finalToken must respect policy max"
        );
        assertLe(
            finalToken,
            capRemainingToken,
            "finalToken must respect cap remaining"
        );
        assertLe(
            finalToken,
            liquidityToken,
            "finalToken must respect available liquidity"
        );

        // router.openPosition (supply AAVE & borrow WBTC)
        router.openPosition(AAVE, supplyAmt, WBTC, targetHF1e18);
        address vault = factory.accountOf(user);
        assertTrue(
            vault != address(0),
            "vault must be created after openPosition"
        );

        // openPosition 이후 유저의 상태
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = aavePool.getUserAccountData(vault);

        // previewBorrow 결과와 실제 openPosition 결과 비교
        // 6-1) 담보/부채가 실제로 반영되었는지
        assertGt(
            totalCollateralBase,
            0,
            "totalCollateralBase must be > 0 after openPosition"
        );
        assertGt(
            totalDebtBase,
            debtBeforeBase,
            "totalDebtBase must increase after openPosition"
        );

        // 6-2) preview에서 계산한 LT와 실제 LT 일치
        assertEq(
            ltAfterBps,
            currentLiquidationThreshold,
            "LT must match preview"
        );

        // 6-3) previewBorrow에서 계산한 차입 토큰 수량과 실제 Vault WBTC 잔고 일치
        uint256 borrowedWBTC = IERC20(WBTC).balanceOf(vault);
        assertEq(
            borrowedWBTC,
            finalToken,
            "borrowed WBTC must match preview finalToken"
        );

        vm.stopPrank();
    }
}
