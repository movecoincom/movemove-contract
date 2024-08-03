// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MMCNFTV2 is ERC1155, Ownable, ERC1155Burnable, ERC1155Supply, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Factory public uniswapV2Factory;

    // Token information structure
    struct TokenInfo {
        uint256 price;
        uint8 tokenType;
        uint8 status;
        string uri;
    }

    // Mapping of Token ID to TokenInfo
    mapping(uint256 => TokenInfo) public tokenInfo;

    // Pool percentage, default 50%
    uint256 public poolPercentage = 50;
    // Withdrawable USDT balance
    uint256 public withdrawableUSDT;
    // Selling status
    uint8 public saleStatus;

    // Interface for USDT and MMC tokens
    IERC20 public usdtToken;
    IERC20 public mmcToken;

    // Constructor to initialize Uniswap router, factory and token address
    constructor(address _router, address _factory, address _usdtToken, address _mmcToken) ERC1155("") Ownable(msg.sender) {
        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Factory = IUniswapV2Factory(_factory);
        usdtToken = IERC20(_usdtToken);
        mmcToken = IERC20(_mmcToken);
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
        // Check if _tokenA is USDT and ensure not to use withdrawable USDT
        uint256 usdtBalance = usdtToken.balanceOf(address(this)) - withdrawableUSDT;

        if (_tokenA == address(usdtToken)) {
            require(_amountA <= usdtBalance, "Invalid request");
        }

        // Check if _tokenB is USDT and ensure not to use withdrawable USDT
        if (_tokenB == address(usdtToken)) {
            require(_amountB <= usdtBalance, "Invalid request");
        }

        // Safe increase allowance
        IERC20(_tokenA).safeIncreaseAllowance(address(uniswapV2Router), _amountA);
        IERC20(_tokenB).safeIncreaseAllowance(address(uniswapV2Router), _amountB);

        // Add liquidity
        uniswapV2Router.addLiquidity(
            _tokenA,
            _tokenB,
            _amountA,
            _amountB,
            _minAmountA,
            _minAmountB,
            address(this),
            block.timestamp + 15 minutes
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
        // Remove Liquidity
        uniswapV2Router.removeLiquidity(
            _tokenA,
            _tokenB,
            _liquidity,
            _minAmountA,
            _minAmountB,
            address(this),
            block.timestamp + 15 minutes
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
            require(amountIn <= usdtToken.balanceOf(address(this)) - withdrawableUSDT, "Invalid request");
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

    // Set base URI
    function setBaseURI(string memory newUri) external onlyOwner {
        _setURI(newUri);
    }

    // Implementing the ERC1155 receiver interface
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
    external
    override
    returns(bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
    external
    override
    returns(bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    // Set Token URI individually
    function setTokenURI(uint256 tokenId, string memory newUri) external onlyOwner {
        require(bytes(newUri).length > 0, "Invalid request");
        tokenInfo[tokenId].uri = newUri;
    }

    // Set Token URI in batches
    function setTokenURIBatch(uint256[] memory tokenIds, string[] memory newUris) external onlyOwner {
        require(tokenIds.length == newUris.length, "Invalid request");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenInfo[tokenIds[i]].uri = newUris[i];
        }
    }

    // Get Token URI
    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory _uri = tokenInfo[tokenId].uri;
        string memory base = super.uri(tokenId);
        return bytes(_uri).length > 0 ? string(abi.encodePacked(base, _uri)) : string(abi.encodePacked(base, tokenId.toString()));
    }


    // Mint Tokens in batches and set URI, price, and type
    function mintBatchWithUri(address to, uint256[] memory ids, uint256[] memory amounts, string[] memory tokenUris, uint256[] memory prices, uint8[] memory types, uint8[] memory statuses, bytes memory data) public onlyOwner {
        require(ids.length == amounts.length && ids.length == tokenUris.length && ids.length == prices.length && ids.length == types.length && ids.length == statuses.length, "Invalid request");
        _mintBatch(to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; i++) {
            tokenInfo[ids[i]] = TokenInfo(prices[i], types[i], statuses[i], tokenUris[i]);
        }
    }

    // Secure transfer of tokens
    function safeTransfer(address to, uint256 tokenId, uint256 amount, bytes memory data) external onlyOwner {
        safeTransferFrom(msg.sender, to, tokenId, amount, data);
    }

    // Transfer token from contract
    function safeTransferContract(address to, uint256 tokenId, uint256 amount, bytes memory data) external onlyOwner {
        _safeTransferFrom(address(this), to, tokenId, amount, data);
    }

    // Destroy the NFT in the contract
    function destroyContractNFT(uint256 tokenId, uint256 amount) external onlyOwner {
        _burn(address(this), tokenId, amount);
    }

    // Update function, overrides the update function of the parent class
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
    internal
    override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    // Set the pool entry percentage, ranging from 50% to 100%
    function setPoolPercentage(uint256 _percentage) external onlyOwner {
        // 50 and 100
        require(_percentage >= 50 && _percentage <= 100, "Invalid request");
        poolPercentage = _percentage;
    }

    // Set sales status, global switch
    function setSaleStatus(uint8 _status) external onlyOwner {
        // 0 or 1
        require(_status == 0 || _status == 1, "Invalid request");
        saleStatus = _status;
    }

    // Set the price of Token
//    function setTokenInfo(uint256 tokenId, uint256 price, uint8 _type, uint8 status) external onlyOwner {
//        tokenInfo[tokenId].price = price;
//        tokenInfo[tokenId].tokenType = _type;
//        tokenInfo[tokenId].status = status;
//    }

    // Set Token status
    function setTokenStatus(uint256 tokenId, uint8 status) external onlyOwner {
        require(status == 0 || status == 1, "Invalid request");
        tokenInfo[tokenId].status = status;
    }


    // Purchase NFT tokenId: NFT ID quantity: NFT Number
    function buyNFT(address to, uint256 tokenId, uint256 quantity, bytes memory data) external nonReentrant {
        require(to != address(0) && quantity > 0 && saleStatus == 1 && tokenInfo[tokenId].status == 1, "Invalid request");
        // Check if the contract has enough NFT balance

        uint256 totalAmount = tokenInfo[tokenId].price * quantity;
        require(balanceOf(address(this), tokenId) >= quantity && usdtToken.allowance(msg.sender, address(this)) >= totalAmount && usdtToken.balanceOf(msg.sender) >= totalAmount, "Invalid request");

        usdtToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        if (tokenInfo[tokenId].tokenType == 1) {
            withdrawableUSDT += totalAmount - ((totalAmount * poolPercentage) / 100);
        }
        _safeTransferFrom(address(this), to, tokenId, quantity, data);
    }

    // Withdraw your withdrawable USDT balance
    function withdrawUSDT(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0) && amount <= withdrawableUSDT, "Invalid request");
        // Update the state before transferring the tokens
        withdrawableUSDT -= amount;
        // Transfer USDT to the specified address
        usdtToken.safeTransfer(to, amount);
    }

    // Receive ERC20 tokens
    function receiveERC20(IERC20 _token, uint256 amount) external {
        _token.transferFrom(msg.sender, address(this), amount);
    }


}