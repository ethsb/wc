pragma solidity ^0.4.18;

contract Stoppable {
    address curator;
    bool public stopped;

    modifier stopInEmergency { 
        require(!stopped);
        _;
    }
    modifier onlyInEmergency { 
        require(stopped);
        _;
    }
    function Stoppable(address _curator) public {
        curator = _curator;
        stopped = false;
    }
  
    function emergencyStop() external {
        require(msg.sender == curator);
        stopped = true;
    }
    function start() external {
        require(msg.sender == curator);
        stopped = false;
    }
}