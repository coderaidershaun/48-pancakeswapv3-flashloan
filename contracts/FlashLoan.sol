// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "hardhat/console.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlashLoan {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IUniswapV2Router02 constant pancakeswapV2 = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    ISwapRouter constant pancakeswapV3 = ISwapRouter(0x1b81D678ffb9C0263b24A97847620C99d213eB14);

    address private constant deployer = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9; // https://docs.pancakeswap.finance/developers/smart-contracts/pancakeswap-exchange/v3-contracts

    IERC20 private immutable token0;
    IERC20 private immutable token1;
    IUniswapV3Pool private immutable pool;

    struct FlashCallbackData {
        uint amount0;
        uint amount1;
        address caller;
        address[2] path;
        uint8[3] exchRoute;
        uint24 fee;
    }

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        pool = IUniswapV3Pool(getPool(_token0, _token1, _fee));
    }

    function flashloanRequest(
        address[2] memory _path,
        uint256 _amount0, // WBNB
        uint256 _amount1, // BUSD
        uint24 _fee,
        uint8[3] memory _exchRoute
    ) external {
        bytes memory data = abi.encode(
            FlashCallbackData({
                amount0: _amount0, 
                amount1: _amount1, 
                caller: msg.sender, 
                path: _path,
                exchRoute: _exchRoute,
                fee: _fee
            })
        );
        console.log("");
        console.log("Flashloan Pool Address: ", address(pool));
        IUniswapV3Pool(pool).flash(address(this), _amount0, _amount1, data);
    }

    function pancakeV3FlashCallback(
        uint fee0,
        uint fee1,
        bytes calldata data
    ) external {

        require(msg.sender == address(pool), "not authorized");
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));

        // Initialize
        IERC20 baseToken = (fee0 > 0) ? token0 : token1;
        uint256 acquiredAmt = (fee0 > 0) ? decoded.amount0 : decoded.amount1;
        console.log("Fee0: ", fee0);
        console.log("Fee1: ", fee1);
        console.log("baseToken: ", address(baseToken));
        console.log("BORROW: ", acquiredAmt);

        // Trade 1: Swap base for first token to trade
        acquiredAmt = _place_swap(
            acquiredAmt, 
            [address(baseToken), decoded.path[0]], 
            decoded.exchRoute[0], 
            decoded.fee
        );
        console.log("SWAP1 Token: ", decoded.path[0]);
        console.log("SWAP1 Amount: ", acquiredAmt);

        // Trade 2: Swap token for token
        acquiredAmt = _place_swap(
            acquiredAmt, 
            [decoded.path[0], decoded.path[1]], 
            decoded.exchRoute[1], 
            decoded.fee
        );
        console.log("SWAP2 Token: ", decoded.path[1]);
        console.log("SWAP2 Amount: ", acquiredAmt);

        // Trade 3: Swap token for base
        acquiredAmt = _place_swap(
            acquiredAmt, 
            [decoded.path[1], address(baseToken)], 
            decoded.exchRoute[2], 
            decoded.fee
        );
        console.log("SWAP3 Token: ", address(baseToken));
        console.log("SWAP3 Amount: ", acquiredAmt);
        // Repay Flashloan and caller
        if (fee0 > 0) {
            TransferHelper.safeApprove(address(token0), address(this), token0.balanceOf(address(this)));
            token0.safeTransfer(address(pool), decoded.amount0 + fee0); // pay flashloan
            console.log("Token0: ", address(token0));
            console.log("Token0 Balance: ", token0.balanceOf(address(this)));
            token0.safeTransfer(decoded.caller, token0.balanceOf(address(this))); // pay caller
        } else {
            TransferHelper.safeApprove(address(token1), address(this), token1.balanceOf(address(this)));
            token1.safeTransfer(address(pool), decoded.amount1 + fee1); // pay flashloan
            console.log("Token1: ", address(token1));
            console.log("Token1 Balance: ", token1.balanceOf(address(this)));
            token1.safeTransfer(decoded.caller, token1.balanceOf(address(this))); // pay caller
        }       
    }


    // Swap a token
    function _place_swap(
        uint256 _amountIn, 
        address[2] memory _tokenPath, 
        uint8 _routing, 
        uint24 _v3_fee
    ) private returns (uint256) {

        // Initialize
        uint deadline = block.timestamp + 30; // 30 seconds
        uint256 swap_amount_out = 0;

        address[] memory path = new address[](2);
        path[0] = _tokenPath[0];
        path[1] = _tokenPath[1];

        // Handle for Uniswap V2
        if (_routing == 0) {

            // Initialize approval
            TransferHelper.safeApprove(_tokenPath[0], address(pancakeswapV2), _amountIn);

            // Perform swap
            swap_amount_out = pancakeswapV2.swapExactTokensForTokens({
                amountIn: _amountIn, 
                amountOutMin: 0, 
                path: path,
                to: address(this),
                deadline: deadline
            })[1];

        // Handle for Uniswap V3
        } else if (_routing == 1) {

            // Initialize approval
            TransferHelper.safeApprove(_tokenPath[0], address(pancakeswapV3), _amountIn);

            // Perform swap
            uint256 amountOutMinimum = 0;
            uint160 sqrtPriceLimitX96 = 0;
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: _tokenPath[0],
                    tokenOut: _tokenPath[1],
                    fee: _v3_fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amountIn,
                    amountOutMinimum: amountOutMinimum,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                });
            swap_amount_out = pancakeswapV3.exactInputSingle(params);
        }

        // Return trade amount out
        return swap_amount_out;
    }


    // Get pool address (based on tokens)
    function getPool(
        address _token0,
        address _token1,
        uint24 _fee
    ) public pure returns (address) {
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(
            _token0,
            _token1,
            _fee
        );
        return PoolAddress.computeAddress(deployer, poolKey);
    }
}


library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2; // found within smart router contract code: https://bscscan.com/address/0x13f4EA83D0bd40E75C8222255bc855a974568Dd4#code

    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    function computeAddress(
        address deployer,
        PoolKey memory key
    ) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            deployer,
                            keccak256(abi.encode(key.token0, key.token1, key.fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}