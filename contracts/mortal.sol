pragma solidity >=0.5.0 <0.6.0;

import "./owned.sol";

contract mortal is owned{
  function close() public onlyOwner {
        selfdestruct(msg.sender);
    }
}
