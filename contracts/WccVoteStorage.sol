pragma solidity ^0.4.18;
import '../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
contract WccVoteStorage is Ownable {
    using SafeMath for uint256;
    // enum GameType { First_stage, Round_of_16, Quarter_finals, Semi_finals, For_third, Final }
    // enum GameStatus { Standby, Playing, Voting, Paying, End}
    mapping(address => bool) public admins;
    modifier onlyAdmin() {
        require(admins[msg.sender]);
        _;
    }
    function setAdmin(address admin) public onlyOwner {
        if (!admins[admin]) {
            admins[admin] = true;
        }
    }
    struct VoteInfo {
        string target;
        uint yesCount;
        uint noCount;
        bool passed;
        bool ended;
        bool changed;
        bool isValued;
        uint number;
    }
    struct UserVote {
        bool vote;
        uint value;
        bool paid;
        bool isValued;
    }
    mapping(bytes32 => VoteInfo) public voteInfos;
    mapping(address => bytes32[]) userVotedGameIndexes;
    mapping(bytes32 => mapping(address => UserVote)) public userVotes;

    function setVote(bytes32 _gameIndex, string _result) external onlyAdmin {
        if (!voteInfos[_gameIndex].isValued) {
            voteInfos[_gameIndex] = VoteInfo({
                target: _result,
                yesCount: 0,
                noCount: 0,
                passed: false,
                ended: false,
                changed: false,
                isValued: true,
                number: 0
            });
        } else {
            if (keccak256(voteInfos[_gameIndex].target) != keccak256(_result)) {
                voteInfos[_gameIndex].target = _result;
                voteInfos[_gameIndex].changed = true;
            }
        }
    }
    function getVoteTarget(bytes32 _gameIndex) external view returns(bytes32) {
        return keccak256(voteInfos[_gameIndex].target);
    }
    // function getVoteTargetValue(bytes32 _gameIndex) external view returns(string) {
    //     return voteInfos[_gameIndex].target;
    // }
    function updateVote(bytes32 _gameIndex, bool _passed, bool _ended) external onlyAdmin {
        voteInfos[_gameIndex].passed = _passed;
        voteInfos[_gameIndex].ended = _ended;
        if (_ended) {
            voteInfos[_gameIndex].number = block.number;
        }
    }
    function setUserVote(bytes32 _gameIndex, bool yesOrNo, address user, uint votes) external onlyAdmin {
        if (!userVotes[_gameIndex][user].isValued) {
            userVotes[_gameIndex][user] = UserVote({
                vote: yesOrNo,
                value: votes,
                paid: false,
                isValued: true
            });
            if (yesOrNo) {
                voteInfos[_gameIndex].yesCount = voteInfos[_gameIndex].yesCount.add(votes);
            } else {
                voteInfos[_gameIndex].noCount = voteInfos[_gameIndex].noCount.add(votes);
            }
            userVotedGameIndexes[user].push(_gameIndex);
        }    
    }
    function setUserVotePaid(bytes32 _gameIndex, address user) external onlyAdmin {
        userVotes[_gameIndex][user].paid = true;
    }
    function getUserVotedGameIndex() external view returns(bytes32[]){
        return userVotedGameIndexes[msg.sender];
    }
}