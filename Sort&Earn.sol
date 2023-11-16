// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SortAndEarn is ERC20, Ownable {
    using SafeMath for uint256;

    IERC20 public usdc;

    uint8 public buyFees;
    uint8 public sellFees;
    FeeRecipient[] public buyRecipients;
    FeeRecipient[] public sellRecipients;
    uint8 public burnRate;
    uint32 public _priceStepPerToken = (1 / 2500000000) * 1e18;

    constructor() ERC20("SortAndEarn", "SAE") {
        // Only for tests purposes
        _mint(msg.sender, 600000 * 1e18);
    }

    struct FeeRecipient {
        address payable wallet;
        uint8 percentage;
    }

    function modifyBurnRate(uint8 newBurnRate) public onlyOwner {
        require(newBurnRate <= 100, "Burn rate can only be 0-100");
        require(
            newBurnRate != burnRate,
            "The burn rate entered is already configured"
        );
        _modifyBurnRate(newBurnRate);
    }

    function _modifyBurnRate(uint8 newBurnRate) internal {
        burnRate = newBurnRate;
    }

    function modifyBuyFees(uint8 newBuyFees) public onlyOwner {
        require(newBuyFees <= 100, "Fees can only be 0-100");
        require(
            newBuyFees != buyFees,
            "The fees entered are already configured"
        );
        _modifyBuyFees(newBuyFees);
    }

    function _modifyBuyFees(uint8 newBuyFees) internal {
        buyFees = newBuyFees;
    }

    function modifySellFees(uint8 newSellFees) public onlyOwner {
        require(newSellFees <= 100, "Fees can only be 0-100");
        require(
            newSellFees != sellFees,
            "The fees entered are already configured"
        );
        _modifySellFees(newSellFees);
    }

    function _modifySellFees(uint8 newSellFees) internal {
        sellFees = newSellFees;
    }

    function setBuyRecipients(
        address payable[] memory _wallets,
        uint8[] memory _percentages
    ) public onlyOwner {
        require(
            _wallets.length == _percentages.length,
            "Wallets and percentages array lengths must match"
        );
        require(_wallets.length > 0, "Need at least one recipient");
        _setBuyRecipients(_wallets, _percentages);
    }

    function _setBuyRecipients(
        address payable[] memory _wallets,
        uint8[] memory _percentages
    ) internal {
        uint8 totalPercentage;
        for (uint256 i = 0; i < _percentages.length; i++) {
            totalPercentage += _percentages[i];
        }

        require(totalPercentage == 100, "Total percentages must be equal to 100");

        delete buyRecipients; // Clear the existing recipients array

        for (uint256 i = 0; i < _wallets.length; i++) {
            FeeRecipient memory newRecipient;
            newRecipient.wallet = _wallets[i];
            newRecipient.percentage = _percentages[i];
            buyRecipients.push(newRecipient);
        }
    }

    function setSellRecipients(
        address payable[] memory _wallets,
        uint8[] memory _percentages
    ) public onlyOwner {
        require(
            _wallets.length == _percentages.length,
            "Wallets and percentages array lengths must match"
        );
        require(_wallets.length > 0, "Need at least one recipient");
        _setSellRecipients(_wallets, _percentages);
    }

    function _setSellRecipients(
        address payable[] memory _wallets,
        uint8[] memory _percentages
    ) internal {
        uint8 totalPercentage;
        for (uint256 i = 0; i < _percentages.length; i++) {
            totalPercentage += _percentages[i];
        }

        require(totalPercentage == 100, "Total percentages must be equal to 100");

        delete sellRecipients; // Clear the existing recipients array

        for (uint256 i = 0; i < _wallets.length; i++) {
            FeeRecipient memory newRecipient;
            newRecipient.wallet = _wallets[i];
            newRecipient.percentage = _percentages[i];
            sellRecipients.push(newRecipient);
        }
    }

    function currentPrice() public view returns (uint256) {
        uint256 _currentPrice = 1e16 +
            ((totalSupply() * _priceStepPerToken) / 1e18);
        return _currentPrice;
    }

    function calculatePriceForBuy(uint256 tokenNumber)
        public
        view
        returns (uint256)
    {
        uint256 _currentPrice = currentPrice();
        return
            ((tokenNumber * (_currentPrice + (tokenNumber / 2500000000) / 2)) /
                1e18) / 1e12;
    }

    function calculatePriceForSell(uint256 tokenNumber)
        public
        view
        returns (uint256)
    {
        uint256 _currentPrice = currentPrice();
        return
            ((tokenNumber * (_currentPrice - (tokenNumber / 2500000000) / 2)) /
                1e18) / 1e12;
    }

    function _buy(uint256 tokenNumber) public payable {
        require(tokenNumber > 0, "Cannot buy 0 token");

        uint256 price = calculatePriceForBuy(tokenNumber);
        require(usdc.balanceOf(msg.sender) >= price, "Insufficient balance");

        uint256 fee = 0;

        require(
            usdc.transferFrom(msg.sender, address(this), price),
            "Failed to transfer USDC"
        );
        _mint(address(this), tokenNumber);
        uint256 tokenToBurn = ((tokenNumber * burnRate) / 100);
        if (buyFees > 0) {
            _burn(address(this), tokenToBurn);
            fee = (tokenNumber * (buyFees - burnRate)) / 100;
            _distributeBuyFees(fee);
        }
        uint256 totalFee = fee + tokenToBurn;
        uint256 tokenNumberWithFees = tokenNumber - totalFee;
        this.transfer(msg.sender, tokenNumberWithFees);
    }

    function sell(uint256 tokenNumber) public {
        require(balanceOf(msg.sender) >= tokenNumber, "Insufficient balance");
        uint256 usdcToReturn = calculatePriceForSell(tokenNumber);
        usdc.transfer(msg.sender, usdcToReturn);

        uint256 totalFee = 0;
        if (sellFees > 0) {
            totalFee = (tokenNumber * sellFees) / 100;
            _distributeSellFees(totalFee);
        }

        uint256 tokenNumberWithFees = tokenNumber - totalFee;
        _burn(msg.sender, tokenNumberWithFees);
    }

    function _distributeBuyFees(uint256 feesToDistribute) internal {
        require(buyFees == 0 || feesToDistribute > 0, "Fees equal 0");
        for (uint256 i = 0; i < buyRecipients.length; i++) {
            uint256 recipientFee = (feesToDistribute *
                buyRecipients[i].percentage) / 100;
            this.transfer(buyRecipients[i].wallet, recipientFee);
        }
    }

    function _distributeSellFees(uint256 feesToDistribute) internal {
        require(sellFees == 0 || feesToDistribute > 0, "Fees equal 0");
        for (uint256 i = 0; i < sellRecipients.length; i++) {
            uint256 recipientFee = (feesToDistribute *
                sellRecipients[i].percentage) / 100;
            this.transfer(sellRecipients[i].wallet, recipientFee);
        }
    }

    function _mintForTest(uint256 number) public onlyOwner {
        _mint(msg.sender, number);
    }

    function _setUsdcForTest(address tokenAddress) public onlyOwner {
        usdc = IERC20(tokenAddress);
    }
}