// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20{
    constructor(string memory name, string memory symbol)ERC20(name, symbol)
    {
      _mint(msg.sender, 1000000000000 * 10 ** decimals());
    }
    
}