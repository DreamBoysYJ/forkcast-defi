// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {UserAccount} from "../src/accounts/UserAccount.sol";
import {AccountFactory} from "../src/factory/AccountFactory.sol";
import {StrategyRouter} from "../src/router/StrategyRouter.sol";
import {IERC20, IERC20Metadata} from "../src/interfaces/IERC20.sol";
import {IPool} from "../src/interfaces/aave-v3/IPool.sol";
import {
    IAaveProtocolDataProvider
} from "../src/interfaces/aave-v3/IAaveProtocolDataProvider.sol";

contract StrategyRouterAaveSupply is Test {
    // Aave
    IPool public aavePool;
    address public poolAddr;
    IAaveProtocolDataProvider public dataProvider;
    address public dataAddr;
    address public AAVE;

    // Actor
    address public user;
    address public admin;

    //
    AccountFactory public factory;
    StrategyRouter public router;

    function setUp() public {
        // Set sepolia-rpc-url
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);

        // Set aave-v3 pool instance
        poolAddr = vm.envAddress("AAVE_POOL");
        require(poolAddr != address(0), "POOL missing");
        aavePool = IPool(poolAddr);
        vm.label(poolAddr, "AAVE_POOL");

        // Set aave-ProtocolDataProvider
        dataAddr = vm.envAddress("AAVE_PROTOCOL_DATA_PROVIDER");
        require(dataAddr != address(0), "PROVIDER missing");
        dataProvider = IAaveProtocolDataProvider(dataAddr);
        vm.label(dataAddr, "DATA_PROVIDER");

        // Set user, admin account
        user = makeAddr("USER");
        vm.label(user, "USER");
        admin = vm.addr(1);
        vm.label(admin, "ADMIN");
        vm.deal(admin, 100 ether);

        // Set Aave token to user
        AAVE = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        vm.label(AAVE, "AAVE");
        uint8 decimal = IERC20Metadata(AAVE).decimals();
        uint256 amount = 1000 * (10 ** uint256(decimal));
        deal(AAVE, user, amount);

        uint256 bal = IERC20(AAVE).balanceOf(user);
        console2.log("User AAVE Balance :", bal / (10 ** uint256(decimal)));

        // Deploy AccountFactory.sol
        vm.startPrank(admin);

        factory = new AccountFactory(poolAddr);
        vm.label(address(factory), "AccountFactory");
        console2.log("Factory : ", vm.toString(address(factory)));

        // Deploy StrategyRouter.sol
        router = new StrategyRouter(poolAddr, address(factory));
        vm.label(address(router), "StrategyRouter");
        console2.log("Router : ", vm.toString(address(router)));

        vm.stopPrank();
    }

    /* -------------------------- Helper Functions -------------------------- */

    /// @dev underlying -> aToken Address
    function _aTokenOf(address asset) internal view returns (address aToken) {
        (aToken, , ) = dataProvider.getReserveTokensAddresses(asset);
    }

    /// @dev approve + openPosition(all) -> returns UA
    function _supplyAllAAVE()
        internal
        returns (address ua, address aToken, uint256 amtSupplied)
    {
        aToken = _aTokenOf(AAVE);
        assertTrue(aToken != address(0), "aToken missing");

        amtSupplied = IERC20(AAVE).balanceOf(user);
        vm.startPrank(user);

        bool ok = IERC20(AAVE).approve(address(router), amtSupplied);
        assertTrue(ok, "approve failed");
        router.openPosition(AAVE, amtSupplied, AAVE); //borrowAsset 현재는 더미
        vm.stopPrank();

        ua = factory.accountOf(user);
        assertTrue(ua != address(0), "UA not created by router");
    }

    /// @dev approve + openPosition(partial) -> returns UA
    function _supplyAAVE(
        uint256 amt
    ) internal returns (address ua, address aToken) {
        aToken = _aTokenOf(AAVE);
        assertTrue(aToken != address(0), "aToken missing");

        vm.startPrank(user);
        bool ok = IERC20(AAVE).approve(address(router), amt);
        assertTrue(ok, "approve failed");
        router.openPosition(AAVE, amt, AAVE);
        vm.stopPrank();

        ua = factory.accountOf(user);
        assertTrue(ua != address(0), "UA not created by router");
    }

    /* -------------------------- Tests -------------------------- */

    function test_setup_only() public {
        assertTrue(true);
    }

    /// @notice aToken minted =>  evidence of supplying
    function test_supply_All_MintsAToken_AndUpdatesAccountData() public {
        (address ua, address aToken, uint256 amt) = _supplyAllAAVE();

        (uint256 col, uint256 debt, uint256 available, , , ) = aavePool
            .getUserAccountData(ua);

        assertGt(col, 0, "no collateral accounted"); // 담보가 반영되어야 함
        assertEq(debt, 0, "debt should be zero"); // 대출 안 했으니 0이어야 함
        assertGt(available, 0, "available should > 0"); // 담보를 넣으면 한도는 > 0

        uint256 aBal = IERC20(aToken).balanceOf(ua);
        assertEq(aBal, amt, "aToken != supplied");

        assertEq(IERC20(AAVE).balanceOf(address(router)), 0, "router dust");
        assertEq(IERC20(AAVE).balanceOf(ua), 0, "UA dust");
        assertEq(
            IERC20(AAVE).allowance(user, address(router)),
            0,
            "allowance remains"
        );
    }

    /// @notice aToken minted =>  evidence of supplying
    function test_supply_Partial_MintsAToken_AndUpdatesAccountData() public {
        uint256 bal = IERC20(AAVE).balanceOf(user);
        (address ua, address aToken) = _supplyAAVE(bal / 2);

        (uint256 col, uint256 debt, uint256 available, , , ) = aavePool
            .getUserAccountData(ua);

        assertGt(col, 0, "no collateral accounted"); // 담보가 반영되어야 함
        assertEq(debt, 0, "debt should be zero"); // 대출 안 했으니 0이어야 함
        assertGt(available, 0, "available should > 0"); // 담보를 넣으면 한도는 > 0

        uint256 aBal = IERC20(aToken).balanceOf(ua);
        assertEq(aBal, bal / 2, "aToken != supplied");

        assertEq(IERC20(AAVE).balanceOf(address(router)), 0, "router dust");
        assertEq(IERC20(AAVE).balanceOf(ua), 0, "UA dust");
        assertEq(
            IERC20(AAVE).allowance(user, address(router)),
            0,
            "allowance remains"
        );
    }

    function test_openPosition_Reverts_WithoutApprove() public {
        vm.startPrank(user);
        uint256 bal = IERC20(AAVE).balanceOf(user);
        vm.expectRevert();
        router.openPosition(AAVE, bal, AAVE);
        vm.stopPrank();
    }

    function test_openPosition_Reverts_ZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(StrategyRouter.ZeroAmount.selector);
        router.openPosition(AAVE, 0, AAVE);
        vm.stopPrank();
    }
}
