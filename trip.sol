// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts 

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // import the ERC20 token standard
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // import SafeERC20 library for safer token transfers
import "@openzeppelin/contracts/utils/math/SafeMath.sol"; // import SafeMath library for safe arithmetic operations
import "@openzeppelin/contracts/access/Ownable.sol"; // import Ownable contract for contract ownership functionality
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // import ReentrancyGuard contract to prevent reentrancy attacks
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; // import Chainlink's AggregatorV3Interface contract for getting external price feed data

// Contract definition
contract TripToken is ERC20, Ownable, ReentrancyGuard {
   using SafeMath for uint256; // use SafeMath library for safe arithmetic operations
   
   // Global variables
   uint8 public buyTaxRate = 5; // tax rate applied on buy transactions
   uint8 public sellTaxRate = 5; // tax rate applied on sell transactions
   uint256 private constant MAX_SCALING_FACTOR = 2e18; // maximum scaling factor for rebase function
   uint256 private constant MIN_SCALING_FACTOR = 5e17; // minimum scaling factor for rebase function
   uint256 private constant TOTAL_SUPPLY = 100000000e18; // total supply of the token
   uint8 public liquidityTax = 2; // tax rate applied on transfers to liquidity wallet
   uint8 public teamTax = 1; // tax rate applied on transfers to team wallet
   uint8 public developmentTax = 1; // tax rate applied on transfers to development wallet
   uint8 public marketingTax = 1; // tax rate applied on transfers to marketing wallet
   AggregatorV3Interface private priceFeed; // instance of Chainlink's AggregatorV3Interface contract for getting external price feed data

   // Constructor function
   constructor(uint256 _initialSupply, uint256 _targetPrice) ERC20("Trip Token", "TRIP") {
      totalSupplyLast = TOTAL_SUPPLY; // set the total supply of the token
      teamWallet = msg.sender; // set the team wallet address to contract creator
      developmentWallet = msg.sender; // set the development wallet address to contract creator
      marketingWallet = msg.sender; // set the marketing wallet address to contract creator
      liquidityWallet = msg.sender; // set the liquidity wallet address to contract creator
      targetPrice = _targetPrice; // set the target price of the token
      buyTaxRate = 5; // set the default buy tax rate
      sellTaxRate = 5; // set the default sell tax rate
      requiredPoolSize = 1000 ether; // set the required pool size for rebase function
      priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // set the address of Chainlink's AggregatorV3Interface contract for getting external price feed data
      _mint(msg.sender, _initialSupply); // mint the initial supply of the token and send it to the contract creator
   }

// This function applies a tax to an amount based on a tax rate
function _applyTax(uint256 amount, uint256 taxRate) private pure returns (uint256) {
   return amount * taxRate / 100;
}

// This function applies transfer taxes to an amount when a transfer occurs
function applyTransferTaxes(uint256 amount) private {
    uint256 totalTax = _applyTax(amount, sellTaxRate + buyTaxRate); // Calculate total tax as the sum of sell and buy taxes
    for (uint256 i = 0; i < 4; i++) { // Loop through each wallet that receives a tax
        address wallet;
        uint256 taxPercent;
        if (i == 0) { // Liquidity wallet
            wallet = address(this);
            taxPercent = liquidityTax;
        } else if (i == 1) { // Team wallet
            wallet = teamWallet;
            taxPercent = teamTax;
        } else if (i == 2) { // Development wallet
            wallet = developmentWallet;
            taxPercent = developmentTax;
        } else { // Marketing wallet
            wallet = marketingWallet;
            taxPercent = marketingTax;
        }
        uint256 taxAmount = _applyTax(amount, taxPercent); // Calculate the amount of tax for the current wallet
        safeTransfer(wallet, taxAmount); // Transfer the tax amount to the current wallet
        emit Transfer(msg.sender, wallet, taxAmount); // Emit a Transfer event to reflect the tax transfer
        totalTax -= taxAmount; // Subtract the current tax amount from the total tax
    }
    if (totalTax > 0) { // If there is any remaining tax
        _burn(msg.sender, totalTax); // Burn the remaining tax amount
        emit Transfer(msg.sender, address(0), totalTax); // Emit a Transfer event to reflect the burn
    }
}

// This function applies sell taxes to an amount when a sell occurs
function applySellTaxes(uint256 amount) private {
    uint256 taxAmount = _applyTax(amount, sellTaxRate); // Calculate the sell tax amount
    safeTransfer(address(this), taxAmount); // Transfer the sell tax amount to the contract
    emit Transfer(msg.sender, address(this), taxAmount); // Emit a Transfer event to reflect the sell tax transfer
    applyTransferTaxes(amount - taxAmount); // Apply transfer taxes to the remaining amount
}

// This function applies buy taxes to an amount when a buy occurs
function applyBuyTaxes(uint256 amount) private {
    uint256 taxAmount = _applyTax(amount, buyTaxRate); // Calculate the buy tax amount
    safeTransfer(address(this), taxAmount); // Transfer the buy tax amount to the contract
    emit Transfer(msg.sender, address(this), taxAmount); // Emit a Transfer event to reflect the buy tax transfer
    applyTransferTaxes(amount - taxAmount); // Apply transfer taxes to the remaining amount
}

// This function sets the sell tax rate
function setSellTaxRate(uint8 _sellTaxRate) public {
   require(msg.sender == owner(), "Only the contract owner can call this function"); // Ensure only the contract owner can call this function
   sellTaxRate = _sellTaxRate; // Set the sell tax rate
}

// This function sets the buy tax rate
function setBuyTaxRate(uint8 _buyTaxRate) public {
   require(msg.sender == owner(), "Only the contract owner can call this function"); // Ensure only the contract owner can call this function
   buyTaxRate = _buyTaxRate; // Set the but tax rate
}


function buy() public payable {
   uint256 amountToBuy = msg.value * targetPrice / 1e18; // Calculate the amount of tokens to buy based on the received ether
   uint256 amountInWei = msg.value; // Store the amount of ether received
   uint256 balanceBefore = balanceOf(address(this)); // Get the balance of the contract before applying taxes
   applyTaxes(amountToBuy, false); // Apply taxes to the token amount being bought
   uint256 balanceAfter = balanceOf(address(this)); // Get the balance of the contract after applying taxes
   uint256 tokensBought = balanceAfter - balanceBefore; // Calculate the actual amount of tokens bought (taking into account taxes)
   require(tokensBought > 0, "Insufficient liquidity"); // Make sure that some tokens were actually bought
   _mint(msg.sender, tokensBought); // Mint the bought tokens to the buyer
   (bool success,) = address(this).call{value: amountInWei}(""); // Transfer the received ether to the contract
   require(success, "ETH transfer failed"); // Make sure that the ether transfer was successful
}


function sell(uint256 amount) public {
   require(amount > 0, "Amount must be greater than 0"); // Make sure that the selling amount is greater than zero
   uint256 balanceBefore = balanceOf(address(this)); // Get the balance of the contract before the sell
   _transfer(msg.sender, address(this), amount); // Transfer the tokens being sold to the contract
   applyTaxes(amount, true); // Apply taxes to the token amount being sold
   uint256 balanceAfter = balanceOf(address(this)); // Get the balance of the contract after applying taxes
   uint256 ethToReturn = balanceBefore - balanceAfter; // Calculate the amount of ether to return to the seller
   uint256 ethToTransfer = ethToReturn * targetPrice / 1e18; // Calculate the amount of ether to transfer based on the target price
   msg.sender.transfer(ethToTransfer); // Transfer the ether to the seller
}


function transfer(address recipient, uint256 amount) public returns (bool) {
   uint256 taxAmount = _applyTax(amount, sellTaxRate); // Calculate the tax amount for the transfer
   uint256 totalTax = taxAmount.mul(4); // Calculate the total tax amount (4%)
   uint256 netAmount = amount.sub(totalTax); // Calculate the net amount (amount minus taxes)


   uint256 liquidityShare = taxAmount.mul(2); // Calculate the liquidity share of the tax (2%)
   uint256 teamShare = taxAmount; // Calculate the team share of the tax (1%)
   uint256 developmentShare = taxAmount; // Calculate the development share of the tax (1%)
   uint256 marketingShare = taxAmount; // Calculate the marketing share of the tax (1%)


   _transferFromSender(msg.sender, recipient, netAmount); // Transfer the net amount to the recipient
   _transferFromSender(msg.sender, liquidityWallet, liquidityShare); // Transfer the liquidity share to the liquidity wallet
   _transferFromSender(msg.sender, teamWallet, teamShare); // Transfer the team share to the team wallet
   _transferFromSender(msg.sender, developmentWallet, developmentShare); // Transfer the development share to the development wallet
   _transferFromSender(msg.sender, marketingWallet, marketingShare); // Transfer the marketing share to the marketing wallet


   return true; // Return true to indicate that the transfer was successful
}


function _transferFromSender(address sender, address recipient, uint256 amount) private {
   _transfer(sender, recipient, amount);
}


function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
   rebase();


   // Use SafeMath library to prevent underflows
   return super.transferFrom(sender, recipient, SafeMath.sub(amount, allowance[sender][msg.sender]));
}


// Cache frequently used values
function transfer(address recipient, uint256 amount) public returns (bool) {
   uint256 taxAmount = _applyTax(amount, SELL_TAX_RATE);
   uint256 totalTax = taxAmount.mul(4);
   uint256 netAmount = amount.sub(totalTax);


   _transfer(msg.sender, recipient, netAmount);
   _transferTo(liquidityWallet, taxAmount.mul(2));
   _transferTo(teamWallet, taxAmount);
   _transferTo(developmentWallet, taxAmount);
   _transferTo(marketingWallet, taxAmount);


   return true;
}


// This function is used to perform a rebase operation on the token.
function rebase() external {
   // Get the current total supply of the token.
   uint256 currentSupply = totalSupply();
   // If the current supply is equal to the last supply, no rebase is needed, so return.
   if (currentSupply == totalSupplyLast) {
       return;
   }

   // Calculate the scaling factor for the rebase.
   uint256 scalingFactor = targetPrice.mul(MAX_SCALING_FACTOR).div(priceFeed.latestAnswer()).div(currentSupply);
   // Ensure that the scaling factor is within the acceptable range.
   scalingFactor = scalingFactor > MAX_SCALING_FACTOR ? MAX_SCALING_FACTOR : scalingFactor < MIN_SCALING_FACTOR ? MIN_SCALING_FACTOR : scalingFactor;

   // Calculate the new rebased supply and the amount of tokens to mint.
   uint256 rebasedSupply = currentSupply.mul(scalingFactor).div(1e18);
   uint256 rebasedAmount = rebasedSupply.sub(currentSupply);

   // Mint the new tokens to the sender of the transaction.
   _mint(msg.sender, rebasedAmount);
   // Update the total supply last value.
   totalSupplyLast = rebasedSupply;
}

// This function is used to perform a gradual rebase operation on the token.
function gradualRebase() public onlyTrusted {
   // Get the current total supply of the token.
   uint256 totalSupplyNow = totalSupply();
   // Set the scaling factor to the initial value of 1e18.
   uint256 scalingFactor = 1e18;
   // Calculate the price change factor based on the current price and target price.
   uint256 priceChangeFactor = getCurrentPrice().mul(1e18).div(targetPrice);

   // If the price has changed, calculate the gradual factor to adjust the scaling factor over time.
   if (priceChangeFactor != 1e18) {
       // Calculate the percentage change in price.
       uint256 percentChange = priceChangeFactor > 1e18 ? priceChangeFactor.sub(1e18) : 1e18.sub(priceChangeFactor);
       // Calculate the gradual factor based on the percentage change and rebase duration (30 days).
       uint256 gradualFactor = percentChange.div(30);
       // Calculate the time elapsed since the last rebase.
       uint256 timeElapsed = block.timestamp - lastRebaseTimestamp;
       // Calculate the total scaling factor based on the time elapsed and gradual factor.
       uint256 totalScalingFactor = timeElapsed < 7 days ? 1e18.add(gradualFactor.mul(timeElapsed).div(30 days)) : priceChangeFactor;

       // Ensure that the total scaling factor is within the acceptable range.
       totalScalingFactor = totalScalingFactor > 2e18 ? 2e18 : totalScalingFactor < 5e17 ? 5e17 : totalScalingFactor;

       // Update the scaling factor with the total scaling factor.
       scalingFactor = scalingFactor.mul(totalScalingFactor).div(1e18);
   } else {
       // If the price has not changed, keep the scaling factor at 1e18.
       scalingFactor = 1e18;
   }

   // Calculate the new rebased supply and call the internal _rebase function to update the token state.
   _rebase(totalSupplyNow.mul(scalingFactor).div(1e18));
   // Update the last rebase timestamp.
   lastRebaseTimestamp = block.timestamp;
}

// This is a private function that updates the scaling factor in order to rebase the token
function _updateRebase() private {
   uint256 currentPoolPrice = getPoolPrice(); // Get the current price of the token pool
   uint256 scalingFactor = calculateScalingFactor(currentPoolPrice); // Calculate the scaling factor based on the current pool price
   uint256 totalSupply = totalSupply(); // Get the total supply of the token
   uint256 targetSupply = scalingFactor.mul(TOTAL_SUPPLY).div(1e18); // Calculate the target supply based on the scaling factor and the total supply
   uint256 delta = targetSupply > totalSupply ? targetSupply.sub(totalSupply) : totalSupply.sub(targetSupply);
   if (delta > 0) {
       uint256 rebaseAmount;
   }
}  


  function addLiquidity() public payable {
   require(msg.value > 0, "Amount must be greater than zero");
   require(balanceOf(msg.sender) > 0, "Sender must have a positive balance");


   // Calculate current price and target price
   uint256 currentPrice = currentPrice();
   uint256 targetPrice = targetPrice();


   // Calculate current pool size and required pool size
   uint256 currentPoolSize = address(this).balance;
   uint256 requiredPoolSize = totalSupply().mul(targetPrice).div(1e18);


   // Calculate the amount of tokens to mint and send to the sender
   uint256 tokensToMint = msg.value.mul(1e18).div(currentPrice);
   uint256 requiredBalance = requiredPoolSize.sub(currentPoolSize);
   if (tokensToMint.mul(targetPrice).div(1e18) > requiredBalance) {
       tokensToMint = requiredBalance.mul(1e18).div(targetPrice);
   }


   // Calculate the tax to be applied to the transaction
   uint256 tax = msg.value.mul(5).div(100);
   uint256 liquidityFee = tax.mul(2).div(5);


   // Adjust the pool size by the received amount of Ether
   uint256 newPoolSize = currentPoolSize.add(msg.value.sub(tax));
   require(newPoolSize >= requiredPoolSize, "Insufficient liquidity");


   // Mint and send the required amount of tokens to the sender
   _mint(msg.sender, tokensToMint);


   // Update the target price based on the new price
   uint256 newPrice = newPoolSize.mul(1e18).div(totalSupply());
   if (newPrice > targetPrice.mul(120).div(100)) {
       targetPrice = targetPrice.mul(110).div(100);
   } else if (newPrice < targetPrice.mul(80).div(100)) {
       targetPrice = targetPrice.mul(90).div(100);
   }
   setTargetPrice(targetPrice);


   // Transfer the received Ether to the contract and add liquidity fee to the contract's balance
   (bool success, ) = address(this).call{value: msg.value.sub(tax).sub(liquidityFee)}("");
   require(success, "Transfer failed");
}


   function removeLiquidity(uint256 amount) public {
   require(amount > 0, "Amount must be greater than zero");
   require(balanceOf(msg.sender) >= amount, "Insufficient balance");


   uint256 currentPoolSize = address(this).balance;
   uint256 currentPoolPrice = currentPoolSize.mul(1e18).div(totalSupply());


   uint256 etherAmount = amount.mul(currentPoolPrice).div(1e18);


   // Transfer Ether to the sender
   (bool success, ) = msg.sender.call{value: etherAmount}("");
   require(success, "Transfer failed");


   // Calculate required pool size and new price
   uint256 targetPoolPrice = targetPrice;
   uint256 requiredPoolSize = totalSupply().mul(targetPoolPrice).div(1e18);
   uint256 newPoolSize = currentPoolSize.sub(etherAmount);
   require(newPoolSize >= requiredPoolSize, "Insufficient liquidity");


   uint256 newPrice = newPoolSize.mul(1e18).div(totalSupply());
}


function targetPriceFeed(AggregatorV3Interface aggregator) public {
   priceFeed = aggregator;
}


function updateTargetPrice() public {
   // Get the latest price from the price feed aggregator
   uint256 newPrice = getCurrentPrice();


   // Update target price if necessary
   if (newPrice > targetPoolPrice.mul(120).div(100)) {
       targetPrice = targetPoolPrice.mul(110).div(100);
   } else if (newPrice < targetPoolPrice.mul(80).div(100)) {
       targetPrice = targetPoolPrice.mul(90).div(100);
   }


   // Transfer tokens from the sender to the contract and burn them
   _transfer(msg.sender, address(this), amount);
   _burn(address(this), amount);


   // Update the target price
   setTargetPrice(targetPrice);
}


function getCurrentPrice() public view returns (uint256) {
   return priceFeed.latestAnswer();
}


function getPoolPrice() public view returns (uint256) {
   if (_cachedPoolPrice == 0) {
       _cachedPoolPrice = address(this).balance.mul(1e18).div(totalSupply());
   }
   return _cachedPoolPrice;
}


function tradingVolume() public view returns (uint256) {
   return totalSupply().sub(balanceOf(address(this)));
}


function setTargetPrice(uint256 _targetPrice) public {
   require(msg.sender == owner(), "Caller is not the owner");
   require(_targetPrice > 0, "Price must be greater than zero");
   targetPrice = _targetPrice;
}


function decimals() public view virtual override returns (uint8) {
   return 18;
}
}
