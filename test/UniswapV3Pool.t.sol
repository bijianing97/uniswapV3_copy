// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquility;
        uint160 currentSqrtP;
        bool transferInSwapCallback;
        bool mintLiquility;
    }

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDX", "USDX", 18);
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquility: 15178823437515098684544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInSwapCallback: true,
            mintLiquility: true
        });

        (uint256 poolBalace0, uint256 poolBalance1) = setupTestCase(params);
        uint256 expectedAmount0 = 0.998976618347425280 ether;
        uint256 expectedAmount1 = 5000 ether;

        assertEq(
            poolBalace0,
            expectedAmount0,
            "incorrect token0 deposited amount"
        );

        assertEq(
            poolBalance1,
            expectedAmount1,
            "incorrect token1 deposited amount"
        );

        assertEq(
            token0.balanceOf(address(this)),
            expectedAmount0,
            "incorrect token0 balance"
        );

        assertEq(
            token1.balanceOf(address(this)),
            expectedAmount1,
            "incorrect token1 balance"
        );

        bytes32 positionKey = keccak256(
            (
                abi.encodePacked(
                    address(this),
                    params.lowerTick,
                    params.upperTick
                )
            )
        );

        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquility, "incorrect liquidity");

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(
            params.lowerTick
        );

        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquility);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();

        assertEq(
            sqrtPriceX96,
            5602277097478614198912276234240,
            "invalid current sqrtP"
        );

        assertEq(tick, 85176, "invalid current tick");
        assertEq(
            pool.liquidity(),
            15178823437515098684544,
            "invalid pool liquidity"
        );
    }

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        if (params.mintLiquility) {
            (poolBalance0, poolBalance1) = pool.mint(
                address(this),
                params.lowerTick,
                params.upperTick,
                params.liquility,
                ""
            );
        }
        transferInSwapCallback = params.transferInSwapCallback;
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        if (transferInMintCallback) {
            UniswapV3Pool.CallbackData memory extra = abi.decode(
                data,
                (UniswapV3Pool.CallbackData)
            );

            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    }

    function testSwapBuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquility: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInSwapCallback: true,
            mintLiquility: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        token1.mint(address(this), 42 ether);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1) public {
        if (amount0 > 0) {
            token0.transfer(msg.sender, uint256(amount0));
        }

        if (amount1 > 0) {
            token1.transfer(msg.sender, uint256(amount1));
        }
    }
}
