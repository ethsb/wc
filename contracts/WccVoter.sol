pragma solidity ^0.4.18;
import '../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import './WccStorage.sol';
import './WccVoteStorage.sol';
import './common/Stoppable.sol';
import './common/KnotToken.sol';
contract WccVoter is Ownable, Stoppable{
    using SafeMath for uint256;
    WccStorage wccs;
    WccVoteStorage vs;
    KnotToken token;
    uint public testOK;
    mapping(bytes32 => bool) public canEnd;
    mapping(address => bool) public judges;
    modifier onlyJudge() {
        require(judges[msg.sender]);
        _;
    }
    function setJudge(address judge) public onlyOwner {
        if (!judges[judge]) {
            judges[judge] = true;
        }
    }
    function isJudge(address user) public view returns(bool) {
        return judges[user];
    }
    function WccVoter(address wccsAddress, address vsAddress, address tokenAddress) public Stoppable(msg.sender){
        wccs = WccStorage(wccsAddress);
        vs = WccVoteStorage(vsAddress);
        token = KnotToken(tokenAddress);
        judges[msg.sender] = true;
    }
    function setWccs(address csAddress) external onlyOwner {
        wccs = WccStorage(csAddress);
    }
    function setVs(address vsAddress) external onlyOwner {
        vs = WccVoteStorage(vsAddress);
    }
    function setToken(address tokenAddress) external onlyOwner {
        token = KnotToken(tokenAddress);
    }
    /// @author Bob Clampett
    /// @notice set game status to Playing
    /// @param _gameIndex game index  
    function setGameStart(bytes32 _gameIndex) external stopInEmergency onlyJudge {
        wccs.setGameStatus(_gameIndex, WccStorage.GameStatus.Playing);
    }
    /// @author Bob Clampett
    /// @notice judge start vote check
    /// @param _gameIndex game index
    /// @return 0 if check passed
    function startVoteCheck(bytes32 _gameIndex) public view returns(uint) {
        var (,,,,status,,,gameValued,) = wccs.games(_gameIndex);
        if (!gameValued) {
            return 1; //game not exist
        }
        if (status != WccStorage.GameStatus.Playing) {
            return 2; //wrong status
        }
        return 0;
    }
    event StartVote(bytes32 _gameIndex, string _result);
    /// @author Bob Clampett
    /// @notice judge start vote
    /// @param _gameIndex game index
    /// @param _result vote target   
    function startVote(bytes32 _gameIndex, string _result) external stopInEmergency onlyJudge {
        require(startVoteCheck(_gameIndex) == 0);
        // change game status to Voting
        wccs.setGameStatus(_gameIndex, WccStorage.GameStatus.Voting);
        // create new Vote info
        vs.setVote(_gameIndex, _result);
        testOK = block.number;
        StartVote(_gameIndex, _result);
    }
    event ChangeVote(bytes32 _gameIndex, string _result);
    /// @author Bob Clampett
    /// @notice judge change vote target
    /// @param _gameIndex game index
    /// @param _result vote target 
    function changeResult(bytes32 _gameIndex, string _result) external stopInEmergency onlyJudge {
        require(startVoteCheck(_gameIndex) == 0);
        vs.setVote(_gameIndex, _result);
        testOK = block.number;
        ChangeVote(_gameIndex, _result);
    }
    /// @author Bob Clampett
    /// @notice user vote check
    /// @param _gameIndex  game index
    /// @return 0 if check passed
    function voteCheck(bytes32 _gameIndex) public view returns(uint) {
        var (,,,,status,,,gameValued,) = wccs.games(_gameIndex);
        if (!gameValued) {
            return 1; //game not exist
        }
        if (status != WccStorage.GameStatus.Voting) {
            return 2; //wrong status
        }
        var (,,,,ended,voteValued,,) = vs.voteInfos(_gameIndex);
        if (ended) {
            return 3; //vote ended
        }
        if (!voteValued) {
            return 4; //vote not exist
        }
        var (,,,isValued) = vs.userVotes(_gameIndex, msg.sender);
        if (isValued) {
            return 5; //has voted
        }
        if (token.balanceOf(msg.sender) == 0) {
            return 6; //no vote token
        }
        if (msg.sender == owner) {
            return 7; //owner can not vote
        }
        return 0;
    }
    event UserVote(bytes32 _gameIndex, bool yesOrNo, address user);
    /// @author Bob Clampett
    /// @notice user vote
    /// @param _gameIndex game index
    /// @param yesOrNo agree or deny    
    function vote(bytes32 _gameIndex, bool yesOrNo) external stopInEmergency {
        require(voteCheck(_gameIndex) == 0);
        // add vote info
        vs.setUserVote(_gameIndex, yesOrNo, msg.sender, token.balanceOf(msg.sender));
        // check can end vote
        if (endVoteCheck(_gameIndex) == 0 && yesOrNo) {
            endVote(_gameIndex);
        }
        testOK = block.number;
        UserVote(_gameIndex, yesOrNo, msg.sender);
    }
    function canEndCheck(bytes32 _gameIndex) public view returns(uint) {
        var (,,,,status,,,gameValued,) = wccs.games(_gameIndex);
        if (!gameValued) {
            return 1; //game not exist
        }
        if (status != WccStorage.GameStatus.Voting) {
            return 2; //wrong status
        }
        var (,,,,ended,voteValued,,) = vs.voteInfos(_gameIndex);
        if (ended) {
            return 3; //vote ended
        }
        if (!voteValued) {
            return 4; //vote not exist
        }
        return 0;
    }
    function setCanEnd(bytes32 _gameIndex) external stopInEmergency onlyJudge {
        // need to add more condition
        require(canEndCheck(_gameIndex) == 0);
        canEnd[_gameIndex] = true;
    }
    function endVoteCheck(bytes32 _gameIndex) public view returns(uint) {
        var (,,,,status,,,gameValued,) = wccs.games(_gameIndex);
        if (!gameValued) {
            return 1; //game not exist
        }
        if (status != WccStorage.GameStatus.Voting) {
            return 2; //wrong status
        }
        if (!canEnd[_gameIndex]) {
            return 3; // can not end
        }
        var (,yesCount,noCount,,,,,) = vs.voteInfos(_gameIndex);
        // need change in future
        if (yesCount < yesCount.add(noCount).div(10)) {
            return 4; // not enough yes vote
        }
        return 0;
    }
    event EndVote(bytes32 _gameIndex);
    function endVote(bytes32 _gameIndex) public stopInEmergency {
        require(endVoteCheck(_gameIndex) == 0);
        // change game status to Paying
        wccs.setGameStatus(_gameIndex, WccStorage.GameStatus.Paying);
        vs.updateVote(_gameIndex, true, true);
        testOK = block.number;
        EndVote(_gameIndex);
    }
}