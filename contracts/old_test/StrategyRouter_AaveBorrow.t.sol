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

contract StrategyRouterAaveBorrow is Test {
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

        // router = new StrategyRouter(
        //     providerAddr,
        //     address(factory),
        //     address(dataAddr),

        // );
        // assertGt(address(router).code.length, 0, "router not deployed");

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

    /// @dev Supply AAVE -> Borrow WBTC
    /// @notice 성공 케이스
    function test_OpenPosition_SupplyAndBorrow_Succeeds() public {
        // 1) approve (user -> router)
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        bool ok = IERC20(AAVE).approve(address(router), supplyAmt);
        assertTrue(ok, "approve failed");

        // 2) router.openPosition (supply AAVE & borrow WBTC)
        router.openPosition(AAVE, supplyAmt, WBTC, 1.5e18);

        // 3) check userAccount
        address vault = factory.accountOf(user);
        assertTrue(vault != address(0), "vault not created");

        // 4) check status of AAVE : collateral/debt/HF
        (uint256 collateralBase, uint256 debtBase, , , , uint256 hf) = aavePool
            .getUserAccountData(vault);
        assertGt(collateralBase, 0, "collateralBase=0");
        assertGt(debtBase, 0, "debtBase=0 (borrow failed?)");
        assertGt(hf, 1e18, "HF <= 1.0");

        // 5) validate token movement of AAVE
        assertEq(
            IERC20(AAVE).balanceOf(address(router)),
            0,
            "router holds AAVE"
        );
        assertEq(IERC20(AAVE).balanceOf(user), 0, "user still has AAVE");

        // 6) check aToken/variableDebt
        (, , address variableDebtWbtc) = dataProvider.getReserveTokensAddresses(
            WBTC
        );
        assertGt(
            IERC20(variableDebtWbtc).balanceOf(vault),
            0,
            "Vault varDebt(WBTC) = 0"
        );

        (address aTokenAave, , ) = dataProvider.getReserveTokensAddresses(AAVE);
        assertGt(
            IERC20(aTokenAave).balanceOf(vault),
            0,
            "Vault aToken(AAVE) = 0"
        );

        // 7) debug logs
        // ---------- USD (1e8) 스케일: Collateral ----------
        uint256 collInt = collateralBase / 1e8;
        uint256 collFrac2 = (collateralBase % 1e8) / 1e6; // 소수 2자리
        string memory collFrac2s = collFrac2 < 10
            ? string.concat("0", vm.toString(collFrac2))
            : vm.toString(collFrac2);
        console2.log(
            string.concat(
                "Collateral (USD): ",
                vm.toString(collInt),
                ".",
                collFrac2s
            )
        );

        // ---------- USD (1e8) 스케일: Debt ----------
        uint256 debtInt = debtBase / 1e8;
        uint256 debtFrac2 = (debtBase % 1e8) / 1e6; // 소수 2자리
        string memory debtFrac2s = debtFrac2 < 10
            ? string.concat("0", vm.toString(debtFrac2))
            : vm.toString(debtFrac2);
        console2.log(
            string.concat("Debt (USD): ", vm.toString(debtInt), ".", debtFrac2s)
        );

        // ---------- HF (1e18) 스케일 ----------
        uint256 hfInt = hf / 1e18;
        uint256 hfFrac2 = (hf % 1e18) / 1e16; // 소수 2자리
        string memory hfFrac2s = hfFrac2 < 10
            ? string.concat("0", vm.toString(hfFrac2))
            : vm.toString(hfFrac2);
        console2.log(string.concat("HF: ", vm.toString(hfInt), ".", hfFrac2s));

        // ---------- aToken(AAVE) (18 decimals) ----------
        uint256 aBal = IERC20(aTokenAave).balanceOf(vault);
        uint256 aInt = aBal / 1e18;
        uint256 aFrac2 = (aBal % 1e18) / 1e16; // 소수 2자리
        string memory aFrac2s = aFrac2 < 10
            ? string.concat("0", vm.toString(aFrac2))
            : vm.toString(aFrac2);
        console2.log(
            string.concat("aToken(AAVE): ", vm.toString(aInt), ".", aFrac2s)
        );

        // ---------- varDebt(WBTC) (8 decimals) ----------
        uint256 dBal = IERC20(variableDebtWbtc).balanceOf(vault);
        uint256 dInt = dBal / 1e8;
        uint256 dFrac2 = (dBal % 1e8) / 1e6; // 소수 2자리
        string memory dFrac2s = dFrac2 < 10
            ? string.concat("0", vm.toString(dFrac2))
            : vm.toString(dFrac2);
        console2.log(
            string.concat("varDebt(WBTC): ", vm.toString(dInt), ".", dFrac2s)
        );

        vm.stopPrank();
    }

    /// @dev supplyAsset == address(0)
    function test_OpenPosition_Revert_ZeroSupplyAsset() public {
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        IERC20(AAVE).approve(address(router), supplyAmt);

        // vm.expectRevert(StrategyRouter.ZeroAddress.selector);
        // supplyAsset = address(0) , 나머진 정상
        router.openPosition(address(0), supplyAmt, WBTC, 1.5e18);
        vm.stopPrank();
    }

    /// @dev borrowAsset == address(0)
    function test_OpenPosition_Revert_ZeroBorrowAsset() public {
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        IERC20(AAVE).approve(address(router), supplyAmt);

        // vm.expectRevert(StrategyRouter.ZeroAddress.selector);
        // borrowAsset = address(0) , 나머진 정상
        router.openPosition(AAVE, supplyAmt, address(0), 1.5e18);
        vm.stopPrank();
    }

    /// @dev supplyAmount == 0
    function test_OpenPosition_Revert_ZeroSupplyAmount() public {
        vm.startPrank(user);
        // uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        // IERC20(AAVE).approve(address(router), supplyAmt);

        vm.expectRevert(StrategyRouter.ZeroAmount.selector);
        // supplyAmount == 0 , 나머진 정상
        router.openPosition(AAVE, 0, WBTC, 1.5e18);
        vm.stopPrank();
    }

    /// @dev 예치 가드
    function test_OpenPosition_Revert_SupplyingDisabled() public {
        // given : supply 자산의 reserve가 paused 라고 가정
        vm.mockCall(
            // 지금부터 이 주소로, 이 calldata가 들어가는 외부 호출을 가짜 응답으로 갈아치워라
            address(dataProvider), // 타겟 주소
            abi.encodeWithSignature("getPaused(address)", AAVE), // 정확히 이 calldata로 호출되면
            abi.encode(true) // 무조건 이 반환값을 돌려줘
        );

        // when : 유저가 토큰 보유 및 approve 완료
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        IERC20(AAVE).approve(address(router), supplyAmt);

        // then : openPosition 호출 시 예치 가드로 즉시 revert
        vm.expectRevert(StrategyRouter.SupplyingDisabled.selector);
        router.openPosition(AAVE, supplyAmt, WBTC, 1.5e18);
        vm.stopPrank();
    }

    /// @dev 대출 가드
    function test_OpenPosition_Revert_BorrowingDisabled() public {
        // given : borrow 자산의 reserve가 paused 라고 가정
        vm.mockCall(
            address(dataProvider),
            abi.encodeWithSignature("getPaused(address)", WBTC),
            abi.encode(true)
        );

        // when : 유저가 토큰 보유 및 approve 완료
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        IERC20(AAVE).approve(address(router), supplyAmt);

        // then : openPosition 호출 시 대출 가드로 즉시 revert
        vm.expectRevert(StrategyRouter.BorrowingDisabled.selector);
        router.openPosition(AAVE, supplyAmt, WBTC, 1.5e18);
        vm.stopPrank();
    }

    /// @dev finalToken이 HF/정책/Cap/유동성 한도들 중 최소값으로 clamp 되는지 테스트
    function test_PreviewBorrow_FinalTokenIsMinOfAllSafetyLimits() public {
        vm.startPrank(user);

        uint256 userBalance = IERC20(AAVE).balanceOf(user);
        assertGt(userBalance, 0, "user must have AAVE");

        uint256 supplyAmt = userBalance / 2;
        IERC20(AAVE).approve(address(router), supplyAmt);

        uint256 targetHF1e18 = 1.7e18;

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

        // 1) 일단 전부 0은 아니어야 함
        assertGt(byHFToken, 0, "byHFToken must be > 0");
        // 나머지는 네 정책에 따라 0 허용 여부 판단

        // 2) 테스트 코드에서 "expected = min(네 개 한도)" 계산
        uint256 expected = byHFToken;

        if (policyMaxToken < expected) {
            expected = policyMaxToken;
        }
        if (capRemainingToken < expected) {
            expected = capRemainingToken;
        }
        if (liquidityToken < expected) {
            expected = liquidityToken;
        }

        // 3) finalToken이 이 expected와 정확히 같은지 확인
        assertEq(
            finalToken,
            expected,
            "finalToken must be min(byHF, policyMax, capRemaining, liquidity)"
        );

        vm.stopPrank();
    }

    /// @dev Router/owner가 아닌 주소가 UserAccount를 통해 자산을 건드리려 할 때 revert 되는지 테스트
    function test_UserAccount_Revert_UnauthorizedCaller() public {
        // 1) approve (user -> router)
        vm.startPrank(user);
        uint256 supplyAmt = IERC20(AAVE).balanceOf(user);
        bool ok = IERC20(AAVE).approve(address(router), supplyAmt);
        assertTrue(ok, "approve failed");

        // 2) router.openPosition (supply AAVE & borrow WBTC)
        router.openPosition(AAVE, supplyAmt, WBTC, 1.5e18);

        // 3) check userAccount
        address vault = factory.accountOf(user);
        assertTrue(vault != address(0), "vault not created");

        vm.stopPrank();

        // 4) Attacker

        address attacker = vm.addr(10);
        vm.startPrank(attacker);

        // 5) userVault의 supply 호출 시도

        vm.expectRevert(UserAccount.NotAuthorized.selector);
        UserAccount(vault).supply(AAVE, 10);

        vm.stopPrank();
    }
}
