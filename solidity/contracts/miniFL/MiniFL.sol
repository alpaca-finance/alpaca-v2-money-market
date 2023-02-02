// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import { IMiniFL } from "./interfaces/IMiniFL.sol";
import { IRewarder } from "./interfaces/IRewarder.sol";

contract MiniFL is IMiniFL, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeCastUpgradeable for uint256;
  using SafeCastUpgradeable for int256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event LogDeposit(address indexed caller, address indexed user, uint256 indexed pid, uint256 amount);
  event LogWithdraw(address indexed caller, address indexed user, uint256 indexed pid, uint256 amount);
  event LogEmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event LogHarvest(address indexed user, uint256 indexed pid, uint256 amount);
  event LogAddPool(uint256 indexed pid, uint256 allocPoint, IERC20Upgradeable indexed stakingToken);
  event LogSetPool(uint256 indexed pid, uint256 allocPoint);
  event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 stakedBalance, uint256 accAlpacaPerShare);
  event LogAlpacaPerSecond(uint256 alpacaPerSecond);
  event LogApproveStakeDebtToken(uint256 indexed _pid, address indexed _staker, bool allow);
  event LogSetMaxAlpacaPerSecond(uint256 maxAlpacaPerSecond);
  event LogSetPoolRewarder(uint256 indexed pid, address rewarder);

  struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
  }

  struct PoolInfo {
    uint128 accAlpacaPerShare;
    uint64 lastRewardTime;
    uint64 allocPoint;
    bool isDebtTokenPool;
  }

  IERC20Upgradeable public ALPACA;
  PoolInfo[] public poolInfo;
  IERC20Upgradeable[] public stakingToken;

  mapping(uint256 => address[]) public rewarders;
  mapping(address => bool) public isStakingToken;
  mapping(uint256 => mapping(address => bool)) public stakeDebtTokenAllowance;
  mapping(address => uint256) public stakingReserves;

  mapping(uint256 => mapping(address => UserInfo)) public userInfo;

  uint256 public totalAllocPoint;
  uint256 public alpacaPerSecond;
  uint256 private constant ACC_ALPACA_PRECISION = 1e12;
  uint256 public maxAlpacaPerSecond;

  /// @param _alpaca The ALPACA token contract address.
  function initialize(address _alpaca, uint256 _maxAlpacaPerSecond) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    ALPACA = IERC20Upgradeable(_alpaca);
    maxAlpacaPerSecond = _maxAlpacaPerSecond;
  }

  /// @notice Returns the number of pools.
  function poolLength() public view returns (uint256 pools) {
    pools = poolInfo.length;
  }

  /// @notice Add a new staking token pool. Can only be called by the owner.
  /// @param _allocPoint AP of the new pool.
  /// @param _stakingToken Address of the staking token.
  /// @param _isDebtTokenPool Whether the pool is a debt token pool.
  /// @param _withUpdate If true, do mass update pools.
  function addPool(
    uint256 _allocPoint,
    IERC20Upgradeable _stakingToken,
    bool _isDebtTokenPool,
    bool _withUpdate
  ) external onlyOwner {
    if (address(_stakingToken) == address(ALPACA)) {
      revert MiniFL_InvalidArguments();
    }
    if (isStakingToken[address(_stakingToken)]) {
      revert MiniFL_DuplicatePool();
    }

    // Sanity check that the staking token is a valid ERC20 token.
    _stakingToken.balanceOf(address(this));

    if (_withUpdate) massUpdatePools();

    totalAllocPoint = totalAllocPoint + _allocPoint;
    stakingToken.push(_stakingToken);
    isStakingToken[address(_stakingToken)] = true;

    poolInfo.push(
      PoolInfo({
        allocPoint: _allocPoint.toUint64(),
        lastRewardTime: block.timestamp.toUint64(),
        accAlpacaPerShare: 0,
        isDebtTokenPool: _isDebtTokenPool
      })
    );
    emit LogAddPool(stakingToken.length - 1, _allocPoint, _stakingToken);
  }

  /// @notice Update the given pool's ALPACA allocation point and `IRewarder` contract.
  /// @dev Can only be called by the owner.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _allocPoint New AP of the pool.
  /// @param _withUpdate If true, do mass update pools
  function setPool(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external onlyOwner {
    if (_withUpdate) massUpdatePools();

    totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
    poolInfo[_pid].allocPoint = _allocPoint.toUint64();

    emit LogSetPool(_pid, _allocPoint);
  }

  /// @notice Sets the ALPACA per second to be distributed. Can only be called by the owner.
  /// @param _alpacaPerSecond The amount of ALPACA to be distributed per second.
  /// @param _withUpdate If true, do mass update pools
  function setAlpacaPerSecond(uint256 _alpacaPerSecond, bool _withUpdate) external onlyOwner {
    if (_alpacaPerSecond > maxAlpacaPerSecond) {
      revert MiniFL_InvalidArguments();
    }
    if (_withUpdate) massUpdatePools();
    alpacaPerSecond = _alpacaPerSecond;
    emit LogAlpacaPerSecond(_alpacaPerSecond);
  }

  /// @notice View function to see pending ALPACA on frontend.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _user Address of a user.
  /// @return pending ALPACA reward for a given user.
  function pendingAlpaca(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo memory pool = poolInfo[_pid];
    UserInfo memory user = userInfo[_pid][_user];
    uint256 accAlpacaPerShare = pool.accAlpacaPerShare;
    uint256 stakedBalance = stakingReserves[address(stakingToken[_pid])];
    if (block.timestamp > pool.lastRewardTime && stakedBalance != 0) {
      uint256 timePast;
      unchecked {
        timePast = block.timestamp - pool.lastRewardTime;
      }

      uint256 alpacaReward = (timePast * alpacaPerSecond * pool.allocPoint) / totalAllocPoint;
      accAlpacaPerShare = accAlpacaPerShare + ((alpacaReward * ACC_ALPACA_PRECISION) / stakedBalance);
    }

    return (((user.amount * accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256() - user.rewardDebt).toUint256();
  }

  /// @notice Perform actual update pool.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @return pool Returns the pool that was updated.
  function _updatePool(uint256 pid) internal returns (PoolInfo memory) {
    PoolInfo memory pool = poolInfo[pid];
    if (block.timestamp > pool.lastRewardTime) {
      uint256 stakedBalance = stakingReserves[address(stakingToken[pid])];
      if (stakedBalance > 0) {
        uint256 timePast;
        unchecked {
          timePast = block.timestamp - pool.lastRewardTime;
        }
        uint256 alpacaReward = (timePast * alpacaPerSecond * pool.allocPoint) / totalAllocPoint;
        pool.accAlpacaPerShare =
          pool.accAlpacaPerShare +
          ((alpacaReward * ACC_ALPACA_PRECISION) / stakedBalance).toUint128();
      }
      pool.lastRewardTime = block.timestamp.toUint64();
      poolInfo[pid] = pool;
      emit LogUpdatePool(pid, pool.lastRewardTime, stakedBalance, pool.accAlpacaPerShare);
    }
    return pool;
  }

  /// @notice Update reward variables of the given pool.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @return pool Returns the pool that was updated.
  function updatePool(uint256 _pid) external nonReentrant returns (PoolInfo memory) {
    return _updatePool(_pid);
  }

  /// @notice Update reward variables for a given pools.
  function updatePools(uint256[] calldata _pids) external nonReentrant {
    uint256 len = _pids.length;
    for (uint256 _i; _i < len; ) {
      _updatePool(_pids[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Update reward variables for all pools.
  function massUpdatePools() public nonReentrant {
    uint256 len = poolLength();
    for (uint256 _i; _i < len; ) {
      _updatePool(_i);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Deposit tokens to MiniFL for ALPACA allocation.
  /// @param _for The beneficary address of the deposit.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _amount amount to deposit.
  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external nonReentrant {
    PoolInfo memory pool = _updatePool(_pid);
    UserInfo storage user = userInfo[_pid][_for];
    if (pool.isDebtTokenPool && !stakeDebtTokenAllowance[_pid][msg.sender]) {
      revert MiniFL_Forbidden();
    }
    if (!pool.isDebtTokenPool && msg.sender != _for) {
      revert MiniFL_Forbidden();
    }
    IERC20Upgradeable _stakingToken = stakingToken[_pid];
    _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

    // Effects
    stakingReserves[address(_stakingToken)] += _amount;
    user.amount = user.amount + _amount;
    user.rewardDebt = user.rewardDebt + ((_amount * pool.accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256();

    // Interactions
    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      IRewarder(_rewarder).onDeposit(_pid, _for, user.amount);
      unchecked {
        ++_i;
      }
    }

    emit LogDeposit(msg.sender, _for, _pid, _amount);
  }

  /// @notice Withdraw tokens from MiniFL.
  /// @param _for Withdraw for who?
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _amount Staking token amount to withdraw.
  function withdraw(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external nonReentrant {
    PoolInfo memory pool = _updatePool(_pid);
    UserInfo storage user = userInfo[_pid][_for];

    if (pool.isDebtTokenPool && !stakeDebtTokenAllowance[_pid][msg.sender]) {
      revert MiniFL_Forbidden();
    }
    if (!pool.isDebtTokenPool && msg.sender != _for) {
      revert MiniFL_Forbidden();
    }

    // Effects
    user.rewardDebt = user.rewardDebt - (((_amount * pool.accAlpacaPerShare) / ACC_ALPACA_PRECISION)).toInt256();
    user.amount = user.amount - _amount;

    // Interactions
    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      IRewarder(_rewarder).onWithdraw(_pid, _for, user.amount);
      unchecked {
        ++_i;
      }
    }
    IERC20Upgradeable _stakingToken = stakingToken[_pid];
    stakingReserves[address(_stakingToken)] -= _amount;

    _stakingToken.safeTransfer(msg.sender, _amount);

    emit LogWithdraw(msg.sender, _for, _pid, _amount);
  }

  /// @notice Harvest ALPACA rewards
  /// @param _pid The index of the pool. See `poolInfo`.
  function harvest(uint256 _pid) external nonReentrant {
    PoolInfo memory pool = _updatePool(_pid);
    UserInfo storage user = userInfo[_pid][msg.sender];

    int256 accumulatedAlpaca = ((user.amount * pool.accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256();
    uint256 _pendingAlpaca = (accumulatedAlpaca - user.rewardDebt).toUint256();

    // Effects
    user.rewardDebt = accumulatedAlpaca;

    // Interactions
    if (_pendingAlpaca != 0) {
      ALPACA.safeTransfer(msg.sender, _pendingAlpaca);
    }

    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      IRewarder(_rewarder).onHarvest(_pid, msg.sender);
      unchecked {
        ++_i;
      }
    }

    emit LogHarvest(msg.sender, _pid, _pendingAlpaca);
  }

  /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
  /// @param _pid The index of the pool. See `poolInfo`.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo memory _pool = poolInfo[_pid];
    UserInfo storage _user = userInfo[_pid][msg.sender];

    if (_pool.isDebtTokenPool) {
      revert MiniFL_Forbidden();
    }

    // amount before withdraw
    uint256 _amount = _user.amount;
    _user.amount = 0;
    _user.rewardDebt = 0;

    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      IRewarder(_rewarder).onWithdraw(_pid, msg.sender, 0);
      unchecked {
        ++_i;
      }
    }

    IERC20Upgradeable _stakingToken = stakingToken[_pid];
    stakingReserves[address(_stakingToken)] -= _amount;

    // Note: transfer can fail or succeed if `amount` is zero.
    _stakingToken.safeTransfer(msg.sender, _amount);

    emit LogEmergencyWithdraw(msg.sender, _pid, _amount);
  }

  /// @notice Approve stakers to stake debt token.
  /// @param _pids The pool ids.
  /// @param _stakers The addresses of the stakers.
  /// @param _allow Whether to allow or disallow staking.
  function approveStakeDebtToken(
    uint256[] calldata _pids,
    address[] calldata _stakers,
    bool _allow
  ) external onlyOwner {
    if (_stakers.length != _pids.length) {
      revert MiniFL_InvalidArguments();
    }
    uint256 _length = _stakers.length;
    for (uint256 _i; _i < _length; ) {
      if (poolInfo[_pids[_i]].isDebtTokenPool == false) {
        revert MiniFL_InvalidArguments();
      }

      stakeDebtTokenAllowance[_pids[_i]][_stakers[_i]] = _allow;
      emit LogApproveStakeDebtToken(_pids[_i], _stakers[_i], _allow);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set max reward per second
  /// @param _maxAlpacaPerSecond The max reward per second
  function setMaxAlpacaPerSecond(uint256 _maxAlpacaPerSecond) external onlyOwner {
    if (_maxAlpacaPerSecond < alpacaPerSecond) {
      revert MiniFL_InvalidArguments();
    }
    maxAlpacaPerSecond = _maxAlpacaPerSecond;
    emit LogSetMaxAlpacaPerSecond(_maxAlpacaPerSecond);
  }

  /// @notice Set rewarders in Pool
  /// @param _pid pool id
  /// @param _rewarders rewarders
  function setPoolRewarders(uint256 _pid, address[] calldata _rewarders) external onlyOwner {
    uint256 _length = _rewarders.length;
    // loop to check rewarder should be belong to this MiniFL only
    for (uint256 _i; _i < _length; ) {
      if (IRewarder(_rewarders[_i]).miniFL() != address(this)) {
        revert MiniFL_BadRewarder();
      }

      unchecked {
        ++_i;
      }
    }

    rewarders[_pid] = _rewarders;
  }

  function getStakingReserves(uint256 _pid) external view returns (uint256 _reservedAmount) {
    _reservedAmount = stakingReserves[address(stakingToken[_pid])];
  }
}
