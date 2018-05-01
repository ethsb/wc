pragma solidity ^0.4.18;
import '../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import './WccStorage.sol';
import './WccVoteStorage.sol';
import './common/Stoppable.sol';
contract WccPlayer is Ownable, Stoppable{
    using SafeMath for uint256;
    WccStorage wccs;
    WccVoteStorage vs;
    bytes32 public testOK;
    mapping(address => uint) public withdraws;
    uint public limit = 10 finney;
    function WccPlayer(address wccsAddress, address vsAddress) public Stoppable(msg.sender){
        wccs = WccStorage(wccsAddress);
        vs = WccVoteStorage(vsAddress);
    }
    function setLimit(uint _limit) external onlyOwner {
        limit = _limit;
    }
    function setWccs(address csAddress) external onlyOwner {
        wccs = WccStorage(csAddress);
    }
    function setVs(address vsAddress) external onlyOwner {
        vs = WccVoteStorage(vsAddress);
    }
    /// @author Bob Clampett
    /// @notice user join check
    /// @dev keccak256(p1, p2, gameType) will be game index
    /// @param index game index
    /// @param value bet value
    /// @return 0 if check passed
    function joinCheck(bytes32 index, uint value) public view returns(uint) {
        var (,,,,status,,,gameValued,) = wccs.games(index);
        if (!gameValued) {
            return 1; //game not exist
        }
        if (status != WccStorage.GameStatus.Standby) {
            return 2; //wrong status
        }
        if (value < limit) {
            return 3; // too small chip
        }
        if (msg.sender == owner) {
            return 4; // owner can not join
        }
        return 0;
    }
    event UserJoin(bytes32 gameIndex, string score, address user);

    /// @author Bob Clampett
    /// @notice user join game
    /// @dev keccak256(p1, p2, gameType) will be game index
    /// @param gameIndex game index
    /// @param score bet game score 
    function join(bytes32 gameIndex, string score) external payable stopInEmergency {
        require(joinCheck(gameIndex, msg.value) == 0);
        bytes32 scoreIndex = keccak256(score);
        wccs.userJoin(msg.sender, msg.value, gameIndex, score, scoreIndex);
        testOK = scoreIndex;
        withdraws[owner] = withdraws[owner].add(msg.value);
        UserJoin(gameIndex, score, msg.sender);
    }
    /// @author Bob Clampett
    /// @notice check if user win the game
    /// @param _gameIndex game index
    /// @param _scoreIndex score index
    /// @return true if check passed and win value 
    function isWin(bytes32 _gameIndex, bytes32 _scoreIndex) public view returns(bool win, uint value) {
        bytes32 target = vs.getVoteTarget(_gameIndex);
        var (, myValue,,) = wccs.joinedGamesScoreInfo(_gameIndex, msg.sender, _scoreIndex);
        if (target == _scoreIndex) { // win
            var (,totalWinValue,,) = wccs.gameScoreTotalInfos(_gameIndex, _scoreIndex);
            var (,,,,,totalValue,,,) = wccs.games(_gameIndex);
            return (true, totalValue.mul(myValue).div(totalWinValue));
        } else {
            return (false, 0);
        }
    }
    /// @author Bob Clampett
    /// @notice check if user can claim
    /// @param _gameIndex game index
    /// @param _scoreIndex score index
    /// @return 0 if check passed 
    function claimCheck(bytes32 _gameIndex, bytes32 _scoreIndex) public view returns(uint) {
        var (,,, passed, ended,,,blockNum) = vs.voteInfos(_gameIndex);
        var (win,) = isWin(_gameIndex, _scoreIndex);
        if (!ended) {
            return 1; // vote not finish
        }
        if (!passed) {
            return 2; // vote not passed
        }
        if(!win) {
            return 3; // not win
        }
        var (,,paid,) = wccs.joinedGamesScoreInfo(_gameIndex, msg.sender, _scoreIndex);
        if (paid) {
            return 4; //paid
        }
        if (blockNum > 0) {
            if (block.number < blockNum) {
                return 5; // wrong block number
            }
            if (block.number.sub(blockNum) > 576000 ) {
                return 6; // more than 100 days
            }
        }
        return 0;
    }
    event UserClaim(bytes32 _gameIndex, bytes32 _scoreIndex, address user);
    /// @author Bob Clampett
    /// @notice user claim win value
    /// @param _gameIndex game index
    /// @param _scoreIndex score index
    function claim(bytes32 _gameIndex, bytes32 _scoreIndex) external stopInEmergency{
        require(claimCheck(_gameIndex, _scoreIndex) == 0);
        var (, winValue) = isWin(_gameIndex, _scoreIndex);
        wccs.setUserScorePaid(_gameIndex, _scoreIndex, msg.sender);
        withdraws[msg.sender] = withdraws[msg.sender].add(winValue);
        testOK = keccak256(block.number);
        UserClaim(_gameIndex, _scoreIndex, msg.sender);
    }
    function setWithdraw(address user, uint value) external onlyOwner {
        withdraws[user] = value;
    }
    /// @author Bob Clampett
    /// @notice check voter user can claim bonus
    /// @param _gameIndex game index
    /// @return 0 if check passed     
    function claimByVoterCheck(bytes32 _gameIndex) public view returns(uint) {
        var (,,, passed, ended, changed,, blockNum) = vs.voteInfos(_gameIndex);
        var (vote,,paid,) = vs.userVotes(_gameIndex, msg.sender);
        if (!ended) {
            return 1; // vote not finish
        }
        if (!passed) {
            return 2; // vote not passed
        }
        if(!changed && !vote) {
            return 3; // not win
        }
        if (paid) {
            return 4; //paid
        }
        if (blockNum > 0) {
            if (block.number < blockNum) {
                return 5; // wrong block number
            }
            if (block.number.sub(blockNum) > 576000 ) {
                return 6; // more than 100 days
            }
        }
        return 0;
    }
    event VoterClaim(bytes32 _gameIndex, bytes32 _scoreIndex, address user);

    /// @author Bob Clampett
    /// @notice voter user claim bonus
    /// @param _gameIndex game index    
    function claimByVoter(bytes32 _gameIndex) external stopInEmergency {
        require(claimByVoterCheck(_gameIndex) == 0);
        var (,value,,) = vs.userVotes(_gameIndex, msg.sender);
        var (,yesCount,,,,,,) = vs.voteInfos(_gameIndex);
        vs.setUserVotePaid(_gameIndex, msg.sender);
        var (,,,,,totalValue,,,) = wccs.games(_gameIndex);
        // uint totalCount = yesCount.add(noCount);
        // (totalValue / 20) * value / (yesCount + noCount)
        withdraws[msg.sender] = withdraws[msg.sender].add(totalValue.div(20).mul(value).div(yesCount));
    }
    function() public payable { 
        withdraws[owner] = withdraws[owner].add(msg.value);
    }
    event UserWithdraw(address user, uint value);
    function withdrawCheck(address user) public view returns(uint) {
        uint value = withdraws[user];
        if (value == 0) {
            return 1; // no balance
        }
        if (address(this).balance < value.div(10).mul(9)) {
            return 2; // no enough balance
        }
        if (msg.sender == owner) {
            return 3; // owner
        }
        if (withdraws[owner] < value.div(10).mul(9)) {
            return 4; // withdraws[owner] not enough
        }
        return 0;
    }
    /// @author Bob Clampett
    /// @notice user withdraw eth    
    function withdraw() external stopInEmergency {
        uint value = withdraws[msg.sender];
        require(withdrawCheck(msg.sender) == 0);
        msg.sender.transfer(value.div(10).mul(9));
        delete withdraws[msg.sender];
        withdraws[owner] = withdraws[owner].sub(value.div(100).mul(85));
        UserWithdraw(msg.sender, value.div(100).mul(85));
    }
    /// @author Bob Clampett
    /// @notice owner withdraw eth 
    function withdrawByOwner() external stopInEmergency onlyOwner{
        uint value = withdraws[msg.sender];
        require(value > 0);
        require(address(this).balance >= value);
        withdraws[msg.sender] = 0;
        msg.sender.transfer(value);
        UserWithdraw(msg.sender, value);
    }
    /// @author Bob Clampett
    /// @notice check if user win the vote
    /// @param _gameIndex game index
    /// @return true if check passed and win value 
    function isVoterWin(bytes32 _gameIndex) public view returns(bool win, uint value) {
        var (,yesCount,, passed, ended, changed,,) = vs.voteInfos(_gameIndex);
        var (vote,weight,,) = vs.userVotes(_gameIndex, msg.sender);
        if(passed && ended) {
            if (vote || changed) {
                var (,,,,,totalValue,,,) = wccs.games(_gameIndex);
                return (true, totalValue.div(20).mul(weight).div(yesCount));
            } else {
                return (false, 0);
            }
        } else {
            return (false, 0);
        }
    }
}