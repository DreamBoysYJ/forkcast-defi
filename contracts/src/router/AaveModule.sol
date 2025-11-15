// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {UserAccount} from "../accounts/UserAccount.sol";
import {AccountFactory} from "../factory/AccountFactory.sol";
import {
    IAaveProtocolDataProvider
} from "../interfaces/aave-v3/IAaveProtocolDataProvider.sol";
import {
    IPoolAddressesProvider
} from "../interfaces/aave-v3/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "../interfaces/aave-v3/IPriceOracleGetter.sol";
import {IERC20Metadata} from "../interfaces/IERC20.sol";

abstract contract AaveModule {
    // ── 기존 StrategyRouter의 상태 변수 그대로 ──
    address public admin;
    IPoolAddressesProvider public immutable PROVIDER;
    AccountFactory public immutable factory;
    IAaveProtocolDataProvider public immutable DATA_PROVIDER;
    IPriceOracleGetter public immutable ORACLE;

    uint16 public safe_borrow_bps = 10000;

    struct BorrowQuote {
        uint256 byHFToken;
        uint256 policyCappedToken;
        uint256 capRemainingToken;
        uint256 poolLiquidityToken;
        uint256 finalToken;
        uint256 projectedHF1e18;
    }

    // ── 기존 에러 / 이벤트 그대로 ──
    error ZeroAddress();
    error ZeroAmount();
    error TransferFromFailed();
    error TransferFailed();
    error BorrowingDisabled();
    error BorrowCapExceeded();
    error InsufficientLiquidity();
    error ZeroBorrowAfterSafety();
    error OraclePriceZero();
    error NotAdmin();
    error SameAddress();
    error InvalidBps();
    error SameValue();
    error SupplyingDisabled();

    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event SafeBorrowBpsUpdated(
        uint16 previousBps,
        uint16 newBps,
        address indexed caller
    );

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @param addressesProvider Aave V3 PoolAddressesProvider (Sepolia)
    /// @param dataProvider      AaveProtocolDataProvider (Sepolia)
    /// @param _factory          AccountFactory
    constructor(
        address addressesProvider,
        address _factory,
        address dataProvider
    ) {
        if (addressesProvider == address(0)) revert ZeroAddress();
        if (_factory == address(0)) revert ZeroAddress();
        if (dataProvider == address(0)) revert ZeroAddress();

        PROVIDER = IPoolAddressesProvider(addressesProvider);
        DATA_PROVIDER = IAaveProtocolDataProvider(dataProvider);
        ORACLE = IPriceOracleGetter(PROVIDER.getPriceOracle());
        admin = msg.sender;
        factory = AccountFactory(_factory);
    }

    // ── Aave 헬퍼들 그대로 ──

    function _pool() internal view returns (IPool) {
        return IPool(PROVIDER.getPool());
    }

    function _isReservePaused(address asset) internal view returns (bool) {
        (bool ok, bytes memory out) = address(DATA_PROVIDER).staticcall(
            abi.encodeWithSignature("getPaused(address)", asset)
        );
        if (ok && out.length >= 32) {
            return abi.decode(out, (bool));
        }
        return false;
    }

    /// @dev 현재 상태(담보/부채/LT/가격/데시멀/목표HF)에서 차입 가능한 토큰 수량 산출
    function _quoteBorrowAmount(
        address borrowAsset,
        uint8 decBorrow,
        uint256 priceBorrow,
        uint256 collateralBase,
        uint256 effectiveLTBps,
        uint256 debtBaseBefore,
        uint256 targetHF1e18
    ) internal view returns (BorrowQuote memory Q) {
        if (priceBorrow == 0 || targetHF1e18 == 0) {
            return Q;
        }

        // 1) HF 목표 추가 부채(base) 역산
        uint256 capacityBase = (collateralBase * effectiveLTBps * 1e18) /
            (10000 * targetHF1e18);
        uint256 byHFBase = capacityBase > debtBaseBefore
            ? (capacityBase - debtBaseBefore)
            : 0;

        // 2) base -> token
        uint256 scaleBorrow = 10 ** uint256(decBorrow);
        Q.byHFToken = (byHFBase == 0)
            ? 0
            : (byHFBase * scaleBorrow) / priceBorrow;

        // 3) 정책 버퍼
        Q.policyCappedToken = (Q.byHFToken * uint256(safe_borrow_bps)) / 10_000;

        // 4) BorrowCap / 유동성 체크
        (uint256 borrowCap, ) = DATA_PROVIDER.getReserveCaps(borrowAsset);
        (address aToken, address sDebt, address vDebt) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        uint256 totalDebtToken = 0;
        if (sDebt != address(0)) totalDebtToken += IERC20(sDebt).totalSupply();
        if (vDebt != address(0)) totalDebtToken += IERC20(vDebt).totalSupply();

        if (borrowCap == 0) {
            Q.capRemainingToken = type(uint256).max;
        } else {
            uint256 capMaxToken = borrowCap * scaleBorrow;
            Q.capRemainingToken = capMaxToken > totalDebtToken
                ? (capMaxToken - totalDebtToken)
                : 0;
        }

        Q.poolLiquidityToken = (aToken == address(0))
            ? 0
            : IERC20(borrowAsset).balanceOf(aToken);

        // 5) 최종 min
        Q.finalToken = Q.policyCappedToken;
        if (Q.finalToken > Q.capRemainingToken)
            Q.finalToken = Q.capRemainingToken;
        if (Q.finalToken > Q.poolLiquidityToken)
            Q.finalToken = Q.poolLiquidityToken;

        // 6) 예상 HF
        if (Q.finalToken == 0) {
            Q.projectedHF1e18 = 0;
        } else {
            uint256 finalBase = (Q.finalToken * priceBorrow) / scaleBorrow;
            uint256 projectedDebtBase = debtBaseBefore + finalBase;
            Q.projectedHF1e18 = (projectedDebtBase == 0)
                ? type(uint256).max
                : (collateralBase * effectiveLTBps * 1e18) /
                    (10000 * projectedDebtBase);
        }
    }

    /// @dev Aave에서 해당 자산을 빌릴 수 있는지 현재 풀 체크
    function _aaveCanBorrow(address asset) internal view returns (bool) {
        if (asset == address(0)) revert ZeroAddress();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            bool borrowingEnabled,
            ,
            bool isActiveBorrow,
            bool isFrozenBorrow
        ) = DATA_PROVIDER.getReserveConfigurationData(asset);

        return
            borrowingEnabled &&
            isActiveBorrow &&
            !isFrozenBorrow &&
            !_isReservePaused(asset);
    }

    /// @dev Aave에서 해당 자산을 예치할 수 있는지 현재 풀 체크
    function _aaveCanSupply(address asset) internal view returns (bool) {
        if (asset == address(0)) revert ZeroAddress();

        (
            ,
            ,
            ,
            ,
            ,
            bool usageAsCollateralEnabled,
            ,
            ,
            bool isActive,
            bool isFrozen
        ) = DATA_PROVIDER.getReserveConfigurationData(asset);

        return
            isActive &&
            !isFrozen &&
            usageAsCollateralEnabled &&
            !_isReservePaused(asset);
    }

    // ── admin 관련 함수도 그대로 ──

    function changeAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        if (newAdmin == admin) revert SameAddress();
        address prev = admin;
        admin = newAdmin;
        emit AdminChanged(prev, newAdmin);
    }

    function setSafeBorrowBfs(uint16 newBps) external onlyAdmin {
        if (newBps > 10000) revert InvalidBps();
        if (newBps == safe_borrow_bps) revert SameValue();

        uint16 prev = safe_borrow_bps;
        safe_borrow_bps = newBps;
        emit SafeBorrowBpsUpdated(prev, newBps, msg.sender);
    }

    // ── previewBorrow도 그대로 (Router에서 상속받아 사용) ──
    function previewBorrow(
        address user,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18
    )
        external
        view
        returns (
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
        )
    {
        // 0) 기본값
        if (targetHF1e18 == 0) {
            targetHF1e18 = 135e16;
        }
        if (supplyAmount == 0) revert ZeroAmount();

        // 1) 현재 금고 조회
        address vault = factory.accountOf(user);
        if (vault != address(0)) {
            (collBeforeBase, debtBeforeBase, , ltBeforeBps, , ) = _pool()
                .getUserAccountData(vault);
        } else {
            // 첫 사용자
            collBeforeBase = 0;
            debtBeforeBase = 0;
            ltBeforeBps = 0;
        }
        // 2) supply 가능 여부 체크
        if (!_aaveCanSupply(supplyAsset)) {
            return (
                0,
                0,
                0,
                0,
                0,
                0,
                collBeforeBase,
                debtBeforeBase,
                collBeforeBase,
                ltBeforeBps,
                ltBeforeBps
            );
        }

        // 3) 오라클/데시멀
        uint8 decSupply = IERC20Metadata(supplyAsset).decimals();
        uint8 decBorrow = IERC20Metadata(borrowAsset).decimals();

        uint256 priceSupply = ORACLE.getAssetPrice(supplyAsset);
        uint256 priceBorrow = ORACLE.getAssetPrice(borrowAsset);
        if (priceSupply == 0 || priceBorrow == 0) {
            // 오라클 가격 에러
            return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        // 4) 공급 반영 (가치 가중 LT)
        uint256 scaleSupply = 10 ** uint256(decSupply);
        uint256 supplyValueBase = (supplyAmount * priceSupply) / scaleSupply;
        collAfterBase = collBeforeBase + supplyValueBase;

        (, , uint256 ltSupplyBps, , , , , , , ) = DATA_PROVIDER
            .getReserveConfigurationData(supplyAsset);
        if (collAfterBase == 0) {
            ltAfterBps = 0;
        } else if (collBeforeBase == 0) {
            ltAfterBps = ltSupplyBps;
        } else {
            ltAfterBps =
                (collBeforeBase * ltBeforeBps + supplyValueBase * ltSupplyBps) /
                collAfterBase;
        }

        // 5) borrow 가능 여부 (조기 컷)
        if (!_aaveCanBorrow(borrowAsset)) {
            return (
                0,
                0,
                0,
                0,
                0,
                0,
                collBeforeBase,
                debtBeforeBase,
                collAfterBase,
                ltBeforeBps,
                ltAfterBps
            );
        }

        // 6) 공통화: 차입 사이징 한 방에 계산
        BorrowQuote memory Q = _quoteBorrowAmount(
            borrowAsset,
            decBorrow,
            priceBorrow,
            collAfterBase, // collateralBase
            ltAfterBps, // effectiveLTBps
            debtBeforeBase, // debtBaseBefore
            targetHF1e18
        );

        // 7) 결과 매핑해서 리턴
        byHFToken = Q.byHFToken;
        policyMaxToken = Q.policyCappedToken;
        capRemainingToken = Q.capRemainingToken;
        liquidityToken = Q.poolLiquidityToken;
        finalToken = Q.finalToken;
        projectedHF1e18 = Q.projectedHF1e18;
    }

    /// @dev Aave 예치 + 차입 + 금고→라우터 토큰 이동까지 처리 (Uniswap은 관여 X)
    function _openAavePosition(
        address user,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18 // 0이면 1.35e18로 처리
    ) internal returns (address userAccount, uint256 borrowedAmount) {
        if (supplyAsset == address(0)) revert ZeroAddress();
        if (borrowAsset == address(0)) revert ZeroAddress();
        if (supplyAmount == 0) revert ZeroAmount();
        if (targetHF1e18 == 0) targetHF1e18 = 135e16; // 1.35e18

        // user vault 주소 가져오기
        userAccount = factory.getOrCreate(user);

        // supply asset 현재 pool 상태 체크
        if (!_aaveCanSupply(supplyAsset)) {
            revert SupplyingDisabled();
        }

        // user -> router : 담보 토큰 가져오기 (사전 approve 필요)
        if (
            !IERC20(supplyAsset).transferFrom(user, address(this), supplyAmount)
        ) {
            revert TransferFromFailed();
        }

        // router -> userAccount : 담보 입금
        if (!IERC20(supplyAsset).transfer(userAccount, supplyAmount)) {
            revert TransferFailed();
        }

        // userAccount -> aave : supply
        UserAccount(userAccount).supply(supplyAsset, supplyAmount);

        // ---- HF-우선 사이징 ----

        // 대출 자산 상태 플래그 체크 (pause/freeze/enable)
        if (!_aaveCanBorrow(borrowAsset)) {
            revert BorrowingDisabled();
        }

        // 공급 반영된 최신 계정 상태
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            uint256 currentLiquidationThreshold, // BPS (1e4)
            ,

        ) = _pool().getUserAccountData(userAccount);

        // 가격/decimals
        uint8 decBorrow = IERC20Metadata(borrowAsset).decimals();
        uint256 priceBorrow = ORACLE.getAssetPrice(borrowAsset);
        if (priceBorrow == 0) revert OraclePriceZero();

        // 현재 상태에서 목표 HF를 위해 차입 가능한 토큰 양 산출
        BorrowQuote memory Q = _quoteBorrowAmount(
            borrowAsset,
            decBorrow,
            priceBorrow,
            totalCollateralBase, // collateralBase (supply 반영됨)
            currentLiquidationThreshold, // effectiveLTBps
            totalDebtBase, // debtBaseBefore
            targetHF1e18
        );

        // 8) 이유별 가드
        if (Q.capRemainingToken == 0) revert BorrowCapExceeded();
        if (Q.poolLiquidityToken == 0) revert InsufficientLiquidity();
        if (Q.finalToken == 0) revert ZeroBorrowAfterSafety();

        // 9) 차입 실행
        UserAccount(userAccount).borrow(borrowAsset, Q.finalToken);

        // 10) 금고 -> 라우터 토큰 가져오기
        UserAccount(userAccount).pullToOperator(borrowAsset, Q.finalToken);

        borrowedAmount = Q.finalToken;
    }
}
