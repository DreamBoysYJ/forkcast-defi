// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/console2.sol";

import {AaveModule} from "./AaveModule.sol";
import {UniswapV4Module} from "./UniswapV4Module.sol";
import {UserAccount} from "../accounts/UserAccount.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {IERC20, IERC20Metadata} from "../interfaces/IERC20.sol";

import {UniswapV4LiquidityPreview} from "../libs/UniswapV4LiquidityPreview.sol";

import {
    PositionInfo as V4PositionInfo,
    PositionInfoLibrary
} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

contract StrategyRouter is AaveModule, UniswapV4Module {
    struct PositionInfo {
        address owner;
        address vault;
        address supplyAsset;
        address borrowAsset;
        bool isOpen;
    }

    error PositionNotOpen();
    error NotPositionOwner();

    mapping(uint256 => PositionInfo) public positions; // key = LP tokenId
    mapping(address => uint256[]) public userPositionIds;

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

    event PositionClosed(
        address indexed user,
        address indexed vault,
        uint256 indexed tokenId,
        address supplyAsset,
        address borrowAsset,
        uint256 amountSupplyReturned, // 유저가 최종 받는 A 수량
        uint256 amountBorrowReturned // 유저가 최종 받는 B 수량
    );

    event FeesCollected(
        address indexed user,
        uint256 indexed tokenId,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
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
            revert BorrowAmountZero();
        }
        console2.log("Borrowed amount :::", borrowedAmount);
        UserAccount(userAccount).approveUniswapV4Operator(
            address(positionManager),
            address(this)
        );

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

        // 남은 토큰 (supplyAsset) : user 주소로 보내주기
        uint256 leftover0 = IERC20(supplyAsset).balanceOf(address(this));
        uint256 leftover1 = IERC20(borrowAsset).balanceOf(address(this));
        console2.log("TOKEN 0 ROUTER HAS AFTER LP :", leftover0);
        console2.log("TOKEN 1 ROUTER HAS AFTER LP :", leftover1);

        if (leftover0 > 0) {
            IERC20(supplyAsset).transfer(msg.sender, leftover0);
            console2.log("LEFTOVER TOKEN 0 Back to user :", leftover0);
        }
        // 남은 토큰 (borrowAsset) : aave repay (빚 갚기)
        if (leftover1 > 0) {
            IERC20(borrowAsset).transfer(userAccount, leftover1);
            UserAccount(userAccount).repay(borrowAsset, leftover1);
            console2.log("LEFTOVER TOKEN 1 Repay to userAccount :", leftover1);
        }

        // 3) 데이터 저장
        userPositionIds[msg.sender].push(tokenId);

        positions[tokenId] = PositionInfo({
            owner: msg.sender,
            vault: userAccount,
            supplyAsset: supplyAsset,
            borrowAsset: borrowAsset,
            isOpen: true
        });

        console2.log("FUCKKKK");

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

    /// @notice Close a previously opened leveraged LP position (Aave repay + v4 LP unwind)
    function closePosition(uint256 tokenId) external {
        // 0) Position verification
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();
        if (p.owner != msg.sender) revert NotPositionOwner();

        address positionOwner = p.owner;
        address vault = p.vault;
        address supplyAsset = p.supplyAsset;
        address borrowAsset = p.borrowAsset;

        // 1) Close Uniswap Position (LP 제거 + borrowAsset으로 스왑)
        // 모든 토큰을 borrowAsset 기준으로 정리
        uint256 borrowAmountOut = _exitUniswapV4PositionAndSwapToBorrow(
            vault,
            borrowAsset,
            tokenId
        );
        console2.log("borrowAmountOut:", borrowAmountOut);

        // 2) Close Aave Position (Repay BorrowAsset + Withdraw Supply)
        //    - borrowAsset 빚 전액 상환 (vault 기준)
        //    - 담보(supplyAsset) 전부 user에게 출금
        //    - 남은 borrowAsset(수익)은 user에게 전송

        (
            uint256 repaidToken,
            uint256 collateralOut,
            uint256 leftoverBorrow
        ) = _closeAavePosition(
                positionOwner,
                vault,
                supplyAsset,
                borrowAsset,
                borrowAmountOut
            );

        // 3) Mark position closed
        p.isOpen = false;

        // 4) Emit event
        emit PositionClosed(
            positionOwner,
            vault,
            tokenId,
            supplyAsset,
            borrowAsset,
            collateralOut,
            leftoverBorrow
        );
    }

    /// @dev
    function previewLpWithdrawAmounts(
        uint256 tokenId
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        )
    {
        (
            PoolKey memory key,
            address t0,
            address t1,
            uint256 a0,
            uint256 a1
        ) = _previewLpWithdrawAmounts(tokenId);

        // PoolKey 까진 안 보여줘도 되면 버리고, 주소/수량만 리턴
        token0 = t0;
        token1 = t1;
        amount0 = a0;
        amount1 = a1;
    }

    /// @notice 포지션을 지금 정리(close)한다고 가정했을 때,
    ///         LP 제거 시 받게 될 토큰 양 + Aave 빚 + 유저가 추가로 넣어야 할 B 토큰 범위를 미리보기.
    function previewClosePosition(
        uint256 tokenId
    )
        external
        view
        returns (
            address vault,
            address supplyAsset,
            address borrowAsset,
            uint256 totalDebtToken, // 현재 Aave 빚 (borrowAsset 토큰 개수 기준)
            uint256 lpBorrowTokenAmount, // LP 전량 제거 시 바로 얻는 borrowAsset 양
            uint256 minExtraFromUser, // 권장 최소 추가 필요량 (보수적 기준)
            uint256 maxExtraFromUser, // 이론상 최대 추가 필요량 (빚 전체)
            uint256 amount0FromLp, // LP 제거 시 받는 token0 양
            uint256 amount1FromLp // LP 제거 시 받는 token1 양
        )
    {
        // 0) 포지션 메타 정보
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();
        // owner 체크는 여기선 안 함 (view 미리보기라서 누구나 볼 수 있게)
        vault = p.vault;
        supplyAsset = p.supplyAsset;
        borrowAsset = p.borrowAsset;

        // 1) LP 전량 제거했을 때 나오는 token0/token1 양 미리보기
        PoolKey memory key;
        address token0;
        address token1;
        (
            key,
            token0,
            token1,
            amount0FromLp,
            amount1FromLp
        ) = _previewLpWithdrawAmounts(tokenId);

        // borrowAsset이 풀의 token0/1 중 어느 쪽인지에 따라 LP에서 나오는 "빌린 토큰" 양 계산
        if (borrowAsset == token0) {
            lpBorrowTokenAmount = amount0FromLp;
        } else if (borrowAsset == token1) {
            lpBorrowTokenAmount = amount1FromLp;
        } else {
            // 이 경우는 설계상 잘못된 상태이므로, 일단 "LP로는 빚을 못 갚는다" 느낌으로 0 리턴
            totalDebtToken = 0;
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        // 2) Aave variableDebtToken 기준으로 현재 빚(B 토큰 개수)을 직접 읽기
        (, , address variableDebtToken) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        if (variableDebtToken == address(0)) {
            // 잘못된 설정 방어용
            totalDebtToken = 0;
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        totalDebtToken = IERC20(variableDebtToken).balanceOf(vault);

        // 빚이 아예 없으면, LP에서 나오는 건 전부 유저 수익
        if (totalDebtToken == 0) {
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        // 3) 권장 최소/최대 추가 필요량 계산
        //    - recommended(보수적 최소): "LP에서 나온 borrowAsset만 쓴다고 가정했을 때 부족분"
        //    - max: 빚 전체 (슬리피지/가격 변동/스왑 손실까지 감안한 상한)
        if (totalDebtToken > lpBorrowTokenAmount) {
            minExtraFromUser = totalDebtToken - lpBorrowTokenAmount;
        } else {
            // 이미 LP만으로 빚을 다 갚거나 초과하는 상태면, 추가로 넣어야 할 최소량은 0
            minExtraFromUser = 0;
        }

        maxExtraFromUser = totalDebtToken;
    }

    function collectFees(
        uint256 tokenId
    ) external returns (uint256 collected0, uint256 collected1) {
        // 1) owner 확인
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();
        if (p.owner != msg.sender) revert NotPositionOwner();

        // 2) key 가져오기
        PoolKey memory key = _getPoolKey();

        // 3) 수수료를 유저 지갑으로 전송
        (collected0, collected1) = _collectFees(
            key,
            p.vault,
            tokenId,
            msg.sender
        );

        // 4) 이벤트 로깅
        emit FeesCollected(
            msg.sender,
            tokenId,
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            collected0,
            collected1
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
