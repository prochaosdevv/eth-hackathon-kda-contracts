// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title Simple ERC20 token + Simple Staking Contract
/// @notice Minimal implementations for learning/demo purposes. NOT production-ready — no safety audits.

/* ----------------------
   Minimal ERC20
   ---------------------- */
contract ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint256 _initialMint, address _owner) {
        name = _name;
        symbol = _symbol;
        _mint(_owner, _initialMint);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "mint to zero");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "transfer to zero");
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance too low");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }
}

/* ----------------------
   SimpleStaking
   ----------------------
   - Users stake the same token that is used for rewards.
   - Owner sets rewardRate (tokens distributed per second) and must fund the contract with reward tokens.
   - Rewards accrue linearly over time according to rewardRate and share of stake.
   - Functions: stake, withdraw, getReward, exit
*/
contract SimpleStaking {
    ERC20 public immutable stakingToken;
    address public owner;

    uint256 public rewardRate; // tokens per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalSupply; // total staked
    mapping(address => uint256) public balances;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateChanged(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(address _stakingToken, uint256 _rewardRate) {
        stakingToken = ERC20(_stakingToken);
        owner = msg.sender;
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    // update accounting for a given account
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 delta = block.timestamp - lastUpdateTime;
        // rewardRate * delta * 1e18 / totalSupply
        return rewardPerTokenStored + ((rewardRate * delta * 1e18) / totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        uint256 _balance = balances[account];
        uint256 _rpt = rewardPerToken();
        return ((_balance * (_rpt - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    // Stake tokens: user must approve this contract beforehand
    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalSupply += amount;
        balances[msg.sender] += amount;
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(balances[msg.sender] >= amount, "insufficient staked");
        totalSupply -= amount;
        balances[msg.sender] -= amount;
        require(stakingToken.transfer(msg.sender, amount), "transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(stakingToken.transfer(msg.sender, reward), "reward transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }

    // OWNER functions
    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
        emit RewardRateChanged(_rewardRate);
    }

    // Owner can recover tokens accidentally sent (except staked tokens)
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken) || tokenAmount <= stakingToken.balanceOf(address(this)) - totalSupply, "cannot recover staked tokens");
        ERC20(tokenAddress).transfer(owner, tokenAmount);
    }

    // Change owner
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0));
        owner = newOwner;
    }
}
