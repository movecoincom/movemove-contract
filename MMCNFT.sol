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

contract MMCNFT is ERC1155, Ownable, ERC1155Burnable, ERC1155Supply, IERC1155Receiver {
    using SafeERC20 for IERC20;
    event Received(address, uint);
    using Strings for uint256;

    address public uniswapPair;
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Factory public uniswapV2Factory;

    mapping(uint256 => string) private _tokenURIs;

    constructor(address _router, address _factory) ERC1155("") Ownable(msg.sender) {
        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Factory = IUniswapV2Factory(_factory);
    }


    // Set liquidity pair address
    function uniSetLiquidityPair(address _tokenA, address _tokenB) external onlyOwner {
        // Check if a pairing already exists
        address existingPair = uniswapV2Factory.getPair(_tokenA, _tokenB);

        // If the pairing does not exist, create the pairing
        if (existingPair == address(0)) {
            address newPair = uniswapV2Factory.createPair(_tokenA, _tokenB);
            uniswapPair = newPair;
        } else {
            // If the pair already exists, you can choose to update uniswapPair or just log that it already exists
            uniswapPair = existingPair;
        }
    }

    function getLatestPrice(address _tokenA, address _tokenB) public view returns (uint price) {
        address pairAddress = uniswapV2Factory.getPair(_tokenA, _tokenB);
        require(pairAddress != address(0), "No pool exists for this token pair");
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (address token0,) = (pair.token0(), pair.token1());
        if (_tokenA == token0) {
            price = (reserve1 * 1e18) / reserve0; // Convert to price per token A in terms of token B with 18 decimals
        } else {
            price = (reserve0 * 1e18) / reserve1;
        }
        return price;
    }

    // Add Liquidity
    function uniAddLiquidity(address _tokenA, address _tokenB, uint256 _amountA, uint256 _amountB, uint256 maxSlippage) external onlyOwner {
        uint256 priceA = getLatestPrice(_tokenA, _tokenB); // Get the latest price of token A in terms of token B
        uint256 minAmountB = (_amountA * (priceA * (100 - maxSlippage) / 100) / 1e18);

        IERC20(_tokenA).safeIncreaseAllowance(address(uniswapV2Router), _amountA);
        IERC20(_tokenB).safeIncreaseAllowance(address(uniswapV2Router), _amountB);

        uint256 deadline = block.timestamp + 15 minutes; // Set the deadline

        uniswapV2Router.addLiquidity(
            _tokenA,
            _tokenB,
            _amountA,
            _amountB,
            _amountA,  // Minimum amount of A expected
            minAmountB,  // Minimum amount of B expected
            address(this),
            deadline
        );
    }

    struct LiquidityParams {
        uint256 amountA;
        uint256 amountB;
        uint256 latestPrice;
        uint256 minAmountA;
        uint256 minAmountB;
    }

    // Remove Liquidity
    function uniRemoveLiquidity(address _tokenA, address _tokenB, uint256 _liquidity, uint256 maxSlippage) external onlyOwner {
        address pairAddress = uniswapV2Factory.getPair(_tokenA, _tokenB);
        require(pairAddress != address(0), "No pool exists for this token pair");
        require(pairAddress == uniswapPair, "Uniswap pair mismatch");

        IERC20(pairAddress).safeIncreaseAllowance(address(uniswapV2Router), _liquidity);

        uint256 deadline = block.timestamp + 15 minutes; // Set deadline


        LiquidityParams memory params;
        params.latestPrice = getLatestPrice(_tokenA, _tokenB); // This will give us token B per token A

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();
        params.amountA = _liquidity * reserve0 / totalSupply;
        params.amountB = _liquidity * reserve1 / totalSupply;

        params.minAmountA = params.amountA * (100 - maxSlippage) / 100;
        params.minAmountB = (params.amountA * params.latestPrice / 1e18) * (100 - maxSlippage) / 100; // Adjust amount B based on the latest price

        uniswapV2Router.removeLiquidity(
            _tokenA,
            _tokenB,
            _liquidity,
            params.minAmountA,
            params.minAmountB,
            address(this),
            deadline
        );
    }

    function setBaseURI(string memory newUri) external onlyOwner {
        _setURI(newUri);
    }

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

    //Separate settings
    function setTokenURI(uint256 tokenId, string memory newUri) external onlyOwner {
        require(bytes(newUri).length > 0, "URI should not be empty");
        _tokenURIs[tokenId] = newUri;
    }

    // Batch settings
    function setTokenURIBatch(uint256[] memory tokenIds, string[] memory newUris) external onlyOwner {
        require(tokenIds.length == newUris.length, "Arrays must have the same length");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _tokenURIs[tokenIds[i]] = newUris[i];
        }
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory _uri = _tokenURIs[tokenId];
        string memory base = super.uri(tokenId); // Get base URI
        // If a URI is set for a specific tokenId, return it
        if (bytes(_uri).length > 0) {
            return string(abi.encodePacked(base, _uri));
        }
        // If no URI is set for a specific tokenId, the base URI and tokenId are returned
        return string(abi.encodePacked(base, tokenId.toString()));
    }

    // Single forge and set url
    function mint(address account, uint256 id, uint256 amount, string memory tokenUri, bytes memory data) public onlyOwner {
        require(bytes(tokenUri).length > 0, "URI should not be empty");
        _mint(account, id, amount, data);  // minting tokens
        _tokenURIs[id] = tokenUri;
    }

    // Batch forge and set url
    function mintBatchWithUri(address to, uint256[] memory ids, uint256[] memory amounts, string[] memory tokenUris, bytes memory data) public onlyOwner {
        require(ids.length == amounts.length && ids.length == tokenUris.length, "Arrays must have the same length");
        _mintBatch(to, ids, amounts, data);  // Minting tokens in batches
        for (uint256 i = 0; i < ids.length; i++) {
            _tokenURIs[ids[i]] = tokenUris[i];
        }
    }

    // The contract sends nft to the specified address
    function safeTransfer(address to, uint256 tokenId, uint256 amount, bytes memory data) external onlyOwner {
        safeTransferFrom(msg.sender, to, tokenId, amount, data);
    }


    function safeTransferContract(address to, uint256 tokenId, uint256 amount, bytes memory data) external onlyOwner {
        _safeTransferFrom(address(this), to, tokenId, amount, data);
    }

    // Destroy nft
    function burn(uint256 tokenId, uint256 amount) external onlyOwner {
        _burn(msg.sender, tokenId, amount);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
    internal
    override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    //Receive erc20 tokens
    function receiveERC20(IERC20 _token, uint256 amount) external {
        _token.transferFrom(msg.sender, address(this), amount);
    }

    // take over
    receive() external payable {
        emit Received(msg.sender, msg.value);  // Updated receive() function
    }

}