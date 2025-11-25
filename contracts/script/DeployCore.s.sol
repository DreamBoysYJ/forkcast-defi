// script/DeployCore.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {Miniv4SwapRouter} from "../src/uniswapV4/Miniv4SwapRouter.sol";
import {AccountFactory} from "../src/factory/AccountFactory.sol";
import {UserAccount} from "../src/accounts/UserAccount.sol";
import {StrategyRouter} from "../src/router/StrategyRouter.sol";
import {StrategyLens} from "../src/lens/StrategyLens.sol";

contract DeployCore is Script {
    uint256 internal deployerPk;

    function setUp() public {
        deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function run() external {
        vm.startBroadcast(deployerPk);

        address deployerAddr = vm.addr(deployerPk);

        // 외부 컨트랙트 주소
        address aaveAddressesProvider = vm.envAddress(
            "AAVE_POOL_ADDRESSES_PROVIDER"
        );
        address aavePool = vm.envAddress("AAVE_POOL");
        address aaveDataProvider = vm.envAddress("AAVE_PROTOCOL_DATA_PROVIDER");
        address aaveOracle = vm.envAddress("AAVE_ORACLE");

        address uniPoolManager = vm.envAddress("POOL_MANAGER");
        address uniPositionManager = vm.envAddress("POSITION_MANAGER");
        address permit2 = vm.envAddress("PERMIT2");

        // 1. Miniv4SwapRouter (POOL_MANAGER)
        Miniv4SwapRouter miniRouter = new Miniv4SwapRouter(uniPoolManager);
        console2.log("MiniSwapRouter :", address(miniRouter));

        // 2. Factory (AAVE_POOL_ADDRESSES_PROVIDER)
        AccountFactory factory = new AccountFactory(aaveAddressesProvider);
        console2.log("AccountFactory:", address(factory));

        // 3. StrategyRouter
        // constructor(
        //   address addressesProvider,
        //   address _factory,
        //   address dataProvider,
        //   address _swapRouter,
        //   address _positionManager,
        //   address _permit2
        // )

        StrategyRouter router = new StrategyRouter(
            aaveAddressesProvider,
            address(factory),
            aaveDataProvider,
            address(miniRouter),
            uniPositionManager,
            permit2
        );

        console2.log("StrategyRouter :", address(router));

        // 4. StrategyLens
        // constructor(
        //   address _admin,
        //   address _aaveAddressesProvider,
        //   address _aavePool,
        //   address _aaveDataProvdier,
        //   address _accountFactory,
        //   address _aaveOracle,
        //   address _uniPoolManager,
        //   address _uniPositionManager,
        //   address _strategyRouter
        // )

        StrategyLens lens = new StrategyLens(
            deployerAddr,
            aaveAddressesProvider,
            aavePool,
            aaveDataProvider,
            address(factory),
            aaveOracle,
            uniPoolManager,
            uniPositionManager,
            address(router)
        );
        console2.log("StrategyLens:", address(lens));

        vm.stopBroadcast();
    }
}
