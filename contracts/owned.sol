/**
 * Early prototype of the Edgeless Black Jack contract.
 * Allows an user to initialize a round of black jack, withdraw the win in case he won or both on the same time,
 * while verifying the game data.
 * author: Julia Altenried
 **/
pragma solidity >=0.5.0 <0.6.0;

contract owned {
  address public owner;
  modifier onlyOwner {
      require(msg.sender == owner);
      _;
  }
  constructor () public { owner = msg.sender; }
  function changeOwner(address newOwner) public onlyOwner{
    owner = newOwner;
  }
}
