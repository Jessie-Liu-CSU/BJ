pragma solidity >=0.5.0 <0.6.0;

import "./mortal.sol";

contract blackjack is mortal {
  struct Game {
    /** the game id is used to reference the game **/
    uint id;
    /** the hash of the (partial) deck **/
    bytes32 deck;
    /** the hash of the casino seed used for randomness generation and deck-hashing**/
    bytes32 seed;
    /** the player address **/
    address player;
    /** the bet **/
    uint bet;
    /** the timestamp of the start of the game, game ends automatically after certain time interval passed **/
    uint start;
  }

  /** the value of the cards: Ace, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K . Ace can be 1 or 11, of course.
   *   the value of a card can be determined by looking up cardValues[cardId%13]**/
  uint8[13] cardValues = [11, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 10];

  /** use the game id to reference the games **/
  mapping(uint => Game) games;
  /** the minimum bet**/
  uint public minimumBet;
  /** the maximum bet **/
  uint public maximumBet;
  /** the address which signs the number of cards dealt **/
  address public signer;
  
  /** notify listeners that a new round of blackjack started **/
  event NewGame(uint indexed id, bytes32 deck, bytes32 srvSeed, bytes32 cSeed, address player, uint bet);
  /** notify listeners of the game outcome **/
  event Result(uint indexed id, address player, uint win);
  /** notify listeners that an error occurred**/
  event Error(uint errorCode);

  /** constructur. initialize the contract with a minimum bet and a signer address. **/
  constructor(uint minBet, uint maxBet, address signerAddress) public payable{
    minimumBet = minBet;
    maximumBet = maxBet;
    signer = signerAddress;
  }

  /**
   *   initializes a round of blackjack with an id, the hash of the (partial) deck and the hash of the server seed.
   *   accepts the bet.
   *   throws an exception if the bet is too low or a game with the given id already exists.
   **/
  function initGame(uint id, bytes32 deck, bytes32 srvSeed, bytes32 cSeed) public payable {
    //throw if bet is too low or too high
    require(msg.value >= minimumBet && msg.value <= maximumBet);
    //throw if user could not be paiud out in case of suited blackjack
    require(msg.value * 3 <= address(this).balance);
    _initGame(id, deck, srvSeed, cSeed, msg.value);
  }

  /**
   * first checks if deck and the player's number of cards are correct, then checks if the player won and if so, sends the win.
   **/
  function stand(uint gameId, uint8[] memory deck, bytes32 seed, uint8 numCards, uint8 v, bytes32 r, bytes32 s) public {
    uint win = _stand(gameId,deck,seed,numCards,v,r,s, true);
  }
  
  /**
  *   first stands, then inits a new game with only one transaction
  **/
  function standAndRebet(uint oldGameId, uint8[] memory oldDeck, bytes32 oldSeed, uint8 numCards, uint8 v, bytes32 r, bytes32 s, uint newGameId, bytes32 newDeck, bytes32 newSrvSeed, bytes32 newCSeed) public {
    uint win = _stand(oldGameId,oldDeck,oldSeed,numCards,v,r,s, false);
    uint bet = games[oldGameId].bet;
    if(win >= bet){
      _initGame(newGameId, newDeck, newSrvSeed, newCSeed, bet);
      win-=bet;
    }
    
    require(win <= 0 || msg.sender.send(win));
    }
  
  
  /**
   *   internal function to initialize a round of blackjack with an id, the hash of the (partial) deck,
   *   the hash of the server seed and the bet.
   **/
  function _initGame(uint id, bytes32 deck, bytes32 srvSeed, bytes32 cSeed, uint bet) internal {
    //throw if game with id already exists. later maybe throw only if game with id is still running
    require(games[id].player == msg.sender);
    games[id] = Game(id, deck, srvSeed, msg.sender, bet, now);
    emit NewGame(id, deck, srvSeed, cSeed, msg.sender, bet);
  }
  
  /**
  * first checks if deck and the player's number of cards are correct, then checks if the player won and if so, calculates the win.
  **/
  function _stand(uint gameId, uint8[] memory deck, bytes32 seed, uint8 numCards, uint8 v, bytes32 r, bytes32 s, bool payout) internal returns(uint win){
    Game storage game = games[gameId];
    uint start = game.start;
    game.start = 0; //make sure outcome isn't determined a second time while win payment is still pending -> prevent double payout
    if(msg.sender!=game.player){
      emit Error(1);
      return 0;
    }
    if(!checkDeck(gameId, deck, seed)){
      emit Error(2);
      return 0;
    }
    if(!checkNumCards(gameId, numCards, v, r, s)){
      emit Error(3);
      return 0;
    }
    if(start + 1 hours < now){
      emit Error(4);
      return 0;
    }
    
    win = determineOutcome(gameId, deck, numCards);
    if (payout && win > 0 && !msg.sender.send(win)){
      emit Error(5);
      game.start = start;
      return 0;
    }
    emit Result(gameId, msg.sender, win);
  }
  
  /**
  * check if deck and casino seed are correct.
  **/
  function checkDeck(uint gameId, uint8[] memory deck, bytes32 seed) public payable returns (bool correct)  {
    if(keccak256(abi.encode(seed)) != games[gameId].seed) return false;
    if(keccak256(abi.encode(convertToBytes(deck), seed)) != games[gameId].deck) return false;
    return true;
  }
  
  function toBytes(uint256 x) public returns (bytes memory b) {
    b = new bytes(32);
    assembly { mstore(add(b, 32), x) }
  }
  
  function convertToBytes(uint8[] memory byteArray) public returns (bytes memory b) {
    b = new bytes(byteArray.length);
    for(uint8 i = 0; i < byteArray.length; i++)
      b[i] = byte(byteArray[i]);
  }
  
  /**
  * check if user and casino agree on the number of cards
  **/
  function checkNumCards(uint gameId, uint8 numCards, uint8 v, bytes32 r, bytes32 s) public view returns (bool correct){
    bytes32 msgHash = keccak256(abi.encode(gameId,numCards));
    return ecrecover(msgHash, v, r, s) == signer;
  }

  /**
   * determines the outcome of a game and returns the win.
   * in case of a loss, win is 0.
   **/
  function determineOutcome(uint gameId, uint8[] memory cards, uint8 numCards) public payable returns(uint win) {
    uint8 playerValue = getPlayerValue(cards, numCards);
    //bust if value > 21
    if (playerValue > 21) return 0;

    (uint8 dealerValue, bool dealerBJ) = getDealerValue(cards, numCards);

    //player wins
    if (playerValue == 21 && numCards == 2 && !dealerBJ){ //player blackjack but no dealer blackjack
      if(isSuited(cards[0], cards[2]))
        return games[gameId].bet * 3; //pay 2 to 1
      else
        return games[gameId].bet * 5 / 2;
    }
    else if(playerValue == 21 && numCards == 5) //automatic win on 5-card 21
      return games[gameId].bet * 2;
    else if (playerValue > dealerValue || dealerValue > 21)
      return games[gameId].bet * 2;
    //tie
    else if (playerValue == dealerValue)
      return games[gameId].bet;
    //player loses
    else
      return 0;

  }

  /**
   *   calculates the value of a player's hand.
   *   cards: holds the (partial) deck.
   *   numCards: the number of cards the player holds
   **/
  function getPlayerValue(uint8[] memory cards, uint8 numCards) view internal returns(uint8 playerValue) {
    //player receives first and third card and  all further cards after the 4. until he stands
    //determine value of the player's hand
    uint8 numAces;
    uint8 card;
    for (uint8 i = 0; i < numCards + 2; i++) {
      if (i != 1 && i != 3) { //1 and 3 are dealer cards
        card = cards[i] %13;
        playerValue += cardValues[card];
        if (card == 0) numAces++;
      }

    }
    while (numAces > 0 && playerValue > 21) {
      playerValue -= 10;
      numAces--;
    }
  }


  /**
   *   calculates the value of a dealer's hand.
   *   cards: holds the (partial) deck.
   *   numCards: the number of cards the player holds
   **/
  function getDealerValue(uint8[] memory cards, uint8 numCards) view internal returns(uint8 dealerValue, bool bj) {
    
    //dealer always receives second and forth card
    uint8 card  = cards[1] % 13;
    uint8 card2 = cards[3] % 13;
    dealerValue = cardValues[card] + cardValues[card2];
    uint8 numAces;
    if (card == 0) numAces++;
    if (card2 == 0) numAces++;
    if (dealerValue > 21) { //2 aces,count as 12
      dealerValue -= 10;
      numAces--;
    }
    else if(dealerValue==21){
      return (21, true);
    }
    //take cards until value reaches 17 or more.
    uint8 i;
    while (dealerValue < 17) {
      card = cards[numCards + i + 2] % 13 ;
      dealerValue += cardValues[card];
      if (card == 0) numAces++;
      if (dealerValue > 21 && numAces > 0) {
        dealerValue -= 10;
        numAces--;
      }
      i++;
    }
  }
  
  /** determines if two cards have the same color **/
  function isSuited(uint8 card1, uint8 card2) internal returns(bool){
    return card1/13 == card2/13;
  }
  
  /** the fallback function can be used to send ether to increase the casino bankroll **/
  function() external payable onlyOwner{
  }
  
  /** allows the owner to withdraw funds **/
  function withdraw(uint amount) public onlyOwner{
    require(amount < address(this).balance, "You do not own so much money!");
    
    //if(amount < address(this).balance)
      //if(!owner.send(amount))
        //Error(6);
  }
  
  /** allows the owner to change the signer address **/
  function setSigner(address signerAddress) public onlyOwner{
    signer = signerAddress;
  }
  
  /** allows the owner to change the minimum bet **/
  function setMinimumBet(uint newMin) public onlyOwner{
    minimumBet = newMin;
  }
  
  /** allows the owner to change the mximum **/
  function setMaximumBet(uint newMax) public onlyOwner{
    minimumBet = newMax;
  }
}
