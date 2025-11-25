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
    error BorrowAmountZero();
    error InsufficientLiquidity();
    error ZeroBorrowAfterSafety();
    error OraclePriceZero();
    error NotAdmin();
    error SameAddress();
    error InvalidBps();
    error SameValue();
    error SupplyingDisabled();
    error NotEnoughToRepay();

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

    /// @dev 아베 borrow한 토큰 repay + 예치한 토큰 out
    /// @param user         포지션 소유자 (msg.sender)
    /// @param vault        UserAccount(금고) 주소
    /// @param supplyAsset  Aave에 예치한 담보 자산
    /// @param borrowAsset  Aave에서 빌린 자산 (Uniswap 풀의 token0 또는 token1)
    /// @param borrowAmountOut Uni V4 LP close 후, "LP/스왑으로부터" 라우터가 받았다고 예상한 borrowAsset 양
    function _closeAavePosition(
        address user,
        address vault,
        address supplyAsset,
        address borrowAsset,
        uint256 borrowAmountOut // Uni V4 LP Close 후 라우터의 borrowAsset의 양 (from LP)
    )
        internal
        returns (
            uint256 actualRepaid,
            uint256 collateralOut,
            uint256 leftovevrBorrow
        )
    {
        if (vault == address(0)) revert ZeroAddress();
        if (supplyAsset == address(0)) revert ZeroAddress();
        if (borrowAsset == address(0)) revert ZeroAddress();

        // 0) 라우터가 현재 들고 있는 borrowAsset (LP + 이전 잔여 포함)
        uint256 routerBal = IERC20(borrowAsset).balanceOf(address(this));
        if (routerBal == 0 && borrowAmountOut == 0) {
            // LP에서 아무것도 못 받았고, 라우터에 남은 borrowAsset도 하나도 없음
            revert ZeroBorrowAfterSafety();
        }

        // -------- Repay Debt --------

        // 1) 현재 정확한 빚 (variableDebt 기준)
        uint256 debtToken = _getExactDebtToken(vault, borrowAsset);

        uint256 collateralAmt;
        if (debtToken == 0) {
            // 이론상 여기에 올 일은 거의 없지만, 방어적 처리:
            // 빚이 없으면 담보/남은 토큰만 유저에게 돌려주는 흐름으로 가도 됨.
            // 여기서는 간단히, 담보/남은 borrowAsset만 유저에게 넘기는 쪽으로 처리.
            collateralAmt = _getExactCollateralToken(vault, supplyAsset);
            if (collateralAmt > 0) {
                collateralOut = UserAccount(vault).withdrawTo(
                    supplyAsset,
                    collateralAmt,
                    user
                );
            }

            leftovevrBorrow = IERC20(borrowAsset).balanceOf(address(this));
            if (leftovevrBorrow > 0) {
                IERC20(borrowAsset).transfer(user, leftovevrBorrow);
            }
            return (actualRepaid, collateralOut, leftovevrBorrow);
        }

        // 2) 라우터 잔고만으로 빚을 다 못 갚는 경우, user 지갑에서 부족분 끌어오기
        //    -> user는 미리 borrowAsset.approve(router, maxExtraFromUser) 해둔 상태여야 함.
        if (routerBal < debtToken) {
            uint256 shortfall = debtToken - routerBal;

            // 여기서 transferFrom이 revert 나면, "추가로 넣어라"는 프론트 메시지대로
            // 유저가 충분히 approve/잔고를 안 준비한 상태인 거라 자연스럽게 실패.
            IERC20(borrowAsset).transferFrom(user, address(this), shortfall);

            // 이제 라우터는 debtToken 이상을 보유하게 됨
            routerBal += shortfall;
        }

        // 여기 도달 시점에서는 routerBal >= debtToken 이 보장
        // (부족하면 위 transferFrom에서 revert 났을 것)
        // 필요 이상으로 들어온 borrowAsset(유저가 많이 넣었거나, LP profit)은 나중에 유저에게 다시 보내줌

        // 3) Router -> Vault로 빚만큼 보내고, Vault에서 repay
        IERC20(borrowAsset).transfer(vault, debtToken);
        UserAccount(vault).repay(borrowAsset, debtToken);
        actualRepaid = debtToken;

        // -------- Withdraw Collateral --------

        // 4) Vault가 들고 있던 담보(예치 자산) 전부 user에게 출금
        collateralAmt = _getExactCollateralToken(vault, supplyAsset);
        if (collateralAmt > 0) {
            collateralOut = UserAccount(vault).withdrawTo(
                supplyAsset,
                collateralAmt,
                user
            );
        }

        // -------- Collect Fees / Profit --------

        // 5) repay 이후 라우터가 여전히 들고 있는 borrowAsset 잔고 = 수익/잔여분
        leftovevrBorrow = IERC20(borrowAsset).balanceOf(address(this));
        if (leftovevrBorrow > 0) {
            IERC20(borrowAsset).transfer(user, leftovevrBorrow);
        }
    }

    /// @dev borrowAsset의 현재 빚(원금 + 이자) 계산
    function _getExactDebtToken(
        address vault,
        address borrowAsset
    ) internal view returns (uint256) {
        (, , address variableDebtTokenAddress) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        return IERC20(variableDebtTokenAddress).balanceOf(vault);
    }

    /// @dev supplyAsset의 현재 예치(원금 + 이자) 계산
    function _getExactCollateralToken(
        address vault,
        address supplyAsset
    ) internal view returns (uint256) {
        (address aToken, , ) = DATA_PROVIDER.getReserveTokensAddresses(
            supplyAsset
        );

        return IERC20(aToken).balanceOf(vault);
    }
}
