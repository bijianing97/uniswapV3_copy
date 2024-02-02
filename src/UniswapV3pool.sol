// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./interfaces/IERC20.sol";
import "./lib/TickBitmap.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IUniswapV3MintCallback.sol";

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error InsufficientInputAmount();

    error InvalidTickRange();

    error ZeroLiquidity();

    event Mint(
        address sender,
        address indexed recipient,
        int24 indexed lowerTick,
        int24 indexed upperTick,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    address public immutable token0;
    address public immutable token1;

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
    }

    Slot0 public slot0;

    uint128 public liquidity;

    mapping(int24 => Tick.Info) public ticks;
    mapping(bytes32 => Position.Info) public positions;

    constructor(
        address _token0,
        address _token1,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = _token0;
        token1 = _token1;
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    function position(
        int24 tick
    ) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0); // ensure that the tick is spaced
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    function nextInitializedTickWithOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;

            next = initialized
                ? (compressed -
                    int24(
                        uint24(bitPos - BitMath.mostSignificantBit(masked))
                    )) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed +
                    1 +
                    int24(
                        uint24((BitMath.leastSignificantBit(masked) - bitPos))
                    )) * tickSpacing
                : (compressed + 1 + int24(uint24((type(uint8).max - bitPos)))) *
                    tickSpacing;
        }
    }

    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );

        position.update(amount);

        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
        );

        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(
            msg.sender,
            owner,
            lowerTick,
            upperTick,
            amount,
            amount0,
            amount1
        );
    }

    function swap(
        address recipient,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
        );

        if (balance1Before + uint256(amount1) < balance1()) {
            revert InsufficientInputAmount();
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }
}
