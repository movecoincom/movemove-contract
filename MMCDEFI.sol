// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
interface INFTContract {
    function buyNFT(address to, uint256 tokenId, uint256 quantity, bytes calldata data) external;
    function tokenInfo(uint256 tokenId) external view returns (uint256 price, uint8 tokenType, uint8 status, string memory uri);
}

contract MMCDEFI is Ownable, ERC721Holder, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Factory public uniswapV2Factory;

    INFTContract public nftContract;
    IERC20 public usdtToken;
    IERC20 public mmcToken;

    struct Investment {
        uint256 amount;
        uint256 timestamp;
        uint256 productId;
    }

    struct InvestmentProduct {
        uint256 duration;
        uint256 rate;
        uint256 totalInvested;
        mapping(address => Investment) investments;
    }

    mapping(uint256 => InvestmentProduct) public products;

    event Invested(address indexed user, uint256 productId, uint256 amount);
    event NFTContractUpdated(address indexed oldAddress, address indexed newAddress);

    constructor(
        address _router,
        address _factory,
        address _nftContract,
        address _usdtToken,
        address _mmcToken
    ) Ownable(msg.sender) {
        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Factory = IUniswapV2Factory(_factory);

        nftContract = INFTContract(_nftContract);
        usdtToken = IERC20(_usdtToken);
        mmcToken = IERC20(_mmcToken);
    }

    //Update contract information
    function updateNFTContract(address newNFTContract) external onlyOwner {
        require(newNFTContract != address(0), "Invalid address");
        address oldNFTContract = address(nftContract);
        nftContract = INFTContract(newNFTContract);
        emit NFTContractUpdated(oldNFTContract, newNFTContract);
    }

    // Create financial management
    function createProduct(uint256 duration, uint256 rate, uint256 productId) external onlyOwner {
        require(duration > 0, "Maturity period must be greater than zero");
        require(rate > 0, "Rate must be greater than zero");
        require(products[productId].duration == 0, "Product with this ID already exists");

        InvestmentProduct storage newProduct = products[productId];
        newProduct.duration = duration;
        newProduct.rate = rate;
        newProduct.totalInvested = 0;
    }

    // Query contract usdt balance
    function getUsdtContractBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }

    // Query user purchase financial information
    function getInvestment(address investor, uint256 productId) external view returns (uint256) {
        require(products[productId].duration > 0, "Product does not exist");

        Investment storage investment = products[productId].investments[investor];
        return investment.amount;
    }

    // Purchase financial management
    function buyDefi(address to, uint256 productId, uint256 amount) external nonReentrant {
        require(products[productId].duration > 0, "Product does not exist");
        require(amount > 0, "Invalid USDT amount");

        usdtToken.safeTransferFrom(msg.sender, address(this), amount);

        InvestmentProduct storage product = products[productId];
        product.totalInvested += amount;

        Investment storage investment = product.investments[to];
        investment.amount += amount;
        investment.timestamp = block.timestamp;
        investment.productId = productId;

        emit Invested(to, productId, amount);
    }

    // Add liquidity
    function uniAddLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _minAmountA,
        uint256 _minAmountB
    ) external onlyOwner {

        // Safe increase allowance
        IERC20(_tokenA).safeIncreaseAllowance(address(uniswapV2Router), _amountA);
        IERC20(_tokenB).safeIncreaseAllowance(address(uniswapV2Router), _amountB);

        // end date
        uint256 deadline = block.timestamp + 15 minutes;
        // Add liquidity
        uniswapV2Router.addLiquidity(
            _tokenA,
            _tokenB,
            _amountA,
            _amountB,
            _minAmountA,
            _minAmountB,
            address(this),
            deadline
        );
    }

    // Remove Liquidity
    function uniRemoveLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _minAmountA,
        uint256 _minAmountB
    ) external onlyOwner {

        address pairAddress = uniswapV2Factory.getPair(_tokenA, _tokenB);
        require(pairAddress != address(0), "Invalid request");

        IERC20(pairAddress).safeIncreaseAllowance(address(uniswapV2Router), _liquidity);
        // end date
        uint256 deadline = block.timestamp + 15 minutes;
        // Remove Liquidity
        uniswapV2Router.removeLiquidity(
            _tokenA,
            _tokenB,
            _liquidity,
            _minAmountA,
            _minAmountB,
            address(this),
            deadline
        );
    }


    // Exchange USDT <=> MMC
    function swapExchangeToken(
        uint amountIn,         // The amount of USDT entered
        uint amountOutMin,     // Minimum expected number of MMCs to receive
        uint8 swapType         // 0: Buy 1: Sell
    ) external onlyOwner {
        address[] memory path = new address[](2);
        if (swapType == 0) {
            // USDT => MMC
            usdtToken.safeIncreaseAllowance(address(uniswapV2Router), amountIn);
            path[0] = address(usdtToken);
            path[1] = address(mmcToken);
        } else {
            // MMC => USDT
            mmcToken.safeIncreaseAllowance(address(uniswapV2Router), amountIn);
            path[0] = address(mmcToken);
            path[1] = address(usdtToken);

        }

        uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 15 minutes
        );
    }


    // Financial management contract to purchase NFT
    function purchaseNFT(uint256 tokenId, uint256 quantity, bytes memory data) external onlyOwner {
        uint256 price = getPriceFromNFTContract(tokenId);
        uint256 totalPrice = price * quantity;

        require(usdtToken.balanceOf(address(this)) >= totalPrice, "Insufficient USDT in contract");

        usdtToken.safeIncreaseAllowance(address(nftContract), totalPrice);

        nftContract.buyNFT(address(this), tokenId, quantity, data);
    }

    // Check MoveMoveCoinNFTV2 NFT price
    function getPriceFromNFTContract(uint256 tokenId) public view returns (uint256) {
        (uint256 price,,,) = nftContract.tokenInfo(tokenId);
        return price;
    }

    receive() external payable {}


    function withdrawERC1155(
        address nftContractAddress,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) external onlyOwner {
        require(to != address(0), "Invalid address");
        IERC1155(nftContractAddress).safeTransferFrom(address(this), to, tokenId, amount, data);
    }

    function withdrawERC721(address nftContractAddress, address to, uint256 tokenId) external onlyOwner {
        require(to != address(0), "Invalid address");
        IERC721(nftContractAddress).safeTransferFrom(address(this), to, tokenId);
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        IERC20(token).safeTransfer(to, amount);
    }

    function withdrawEth(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        to.transfer(amount);
    }
}
