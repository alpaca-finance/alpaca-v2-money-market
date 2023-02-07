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
  event LogAddPool(uint256 indexed pid, uint256 allocPoint, address indexed stakingToken);
  event LogSetPool(uint256 indexed pid, uint256 allocPoint);
  event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 stakedBalance, uint256 accAlpacaPerShare);
  event LogAlpacaPerSecond(uint256 alpacaPerSecond);
  event LogApproveStakeDebtToken(uint256 indexed _pid, address indexed _staker, bool allow);
  event LogSetMaxAlpacaPerSecond(uint256 maxAlpacaPerSecond);
  event LogSetPoolRewarder(uint256 indexed pid, address rewarder);
  event LogSetWhitelistedCallers(address indexed caller, bool allow);

  struct UserInfo {
    mapping(address => uint256) fundedAmounts; // funders address => amount
    uint256 totalAmount;
    int256 rewardDebt;
  }

  struct PoolInfo {
    uint128 accAlpacaPerShare;
    uint64 lastRewardTime;
    uint64 allocPoint;
    bool isDebtTokenPool;
  }

  address public ALPACA;
  PoolInfo[] public poolInfo;
  address[] public stakingTokens;

  mapping(uint256 => address[]) public rewarders;
  mapping(address => bool) public isStakingToken;
  mapping(uint256 => mapping(address => bool)) public stakeDebtTokenAllowance;
  mapping(address => uint256) public stakingReserves;

  mapping(uint256 => mapping(address => UserInfo)) public userInfo; // pool id => user
  mapping(address => bool) public whitelistedCallers;

  uint256 public totalAllocPoint;
  uint256 public alpacaPerSecond;
  uint256 private constant ACC_ALPACA_PRECISION = 1e12;
  uint256 public maxAlpacaPerSecond;

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert MiniFL_Unauthorized();
    }
    _;
  }

  /// @param _alpaca The ALPACA token contract address.
  function initialize(address _alpaca, uint256 _maxAlpacaPerSecond) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    ALPACA = _alpaca;
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
    address _stakingToken,
    bool _isDebtTokenPool,
    bool _withUpdate
  ) external onlyWhitelisted {
    if (_stakingToken == ALPACA) {
      revert MiniFL_InvalidArguments();
    }
    if (isStakingToken[_stakingToken]) {
      revert MiniFL_DuplicatePool();
    }

    // Sanity check that the staking token is a valid ERC20 token.
    IERC20Upgradeable(_stakingToken).balanceOf(address(this));

    if (_withUpdate) massUpdatePools();

    totalAllocPoint = totalAllocPoint + _allocPoint;
    stakingTokens.push(_stakingToken);
    isStakingToken[_stakingToken] = true;

    poolInfo.push(
      PoolInfo({
        allocPoint: _allocPoint.toUint64(),
        lastRewardTime: block.timestamp.toUint64(),
        accAlpacaPerShare: 0,
        isDebtTokenPool: _isDebtTokenPool
      })
    );
    emit LogAddPool(stakingTokens.length - 1, _allocPoint, _stakingToken);
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
    UserInfo storage user = userInfo[_pid][_user];
    PoolInfo memory _poolInfo = poolInfo[_pid];

    uint256 accAlpacaPerShare = _poolInfo.accAlpacaPerShare;
    uint256 stakedBalance = stakingReserves[stakingTokens[_pid]];
    if (block.timestamp > _poolInfo.lastRewardTime && stakedBalance != 0) {
      uint256 timePast;
      unchecked {
        timePast = block.timestamp - _poolInfo.lastRewardTime;
      }

      uint256 alpacaReward = (timePast * alpacaPerSecond * _poolInfo.allocPoint) / totalAllocPoint;
      accAlpacaPerShare = accAlpacaPerShare + ((alpacaReward * ACC_ALPACA_PRECISION) / stakedBalance);
    }

    return (((user.totalAmount * accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256() - user.rewardDebt).toUint256();
  }

  /// @notice Perform actual update pool.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @return _poolInfo Returns the pool that was updated.
  function _updatePool(uint256 _pid) internal returns (PoolInfo memory _poolInfo) {
    _poolInfo = poolInfo[_pid];
    if (block.timestamp > _poolInfo.lastRewardTime) {
      uint256 stakedBalance = stakingReserves[stakingTokens[_pid]];
      if (stakedBalance > 0) {
        uint256 timePast;
        unchecked {
          timePast = block.timestamp - _poolInfo.lastRewardTime;
        }
        uint256 alpacaReward = (timePast * alpacaPerSecond * _poolInfo.allocPoint) / totalAllocPoint;
        _poolInfo.accAlpacaPerShare =
          _poolInfo.accAlpacaPerShare +
          ((alpacaReward * ACC_ALPACA_PRECISION) / stakedBalance).toUint128();
      }
      _poolInfo.lastRewardTime = block.timestamp.toUint64();
      // update memory poolInfo in state
      poolInfo[_pid] = _poolInfo;
      emit LogUpdatePool(_pid, _poolInfo.lastRewardTime, stakedBalance, _poolInfo.accAlpacaPerShare);
    }
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
  /// @param _amountToDeposit amount to deposit.
  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amountToDeposit
  ) external nonReentrant {
    UserInfo storage user = userInfo[_pid][_for];
    PoolInfo memory _poolInfo = _updatePool(_pid);

    // if pool is debt pool, staker should be whitelisted
    if (_poolInfo.isDebtTokenPool && !stakeDebtTokenAllowance[_pid][msg.sender]) {
      revert MiniFL_Forbidden();
    }

    address _stakingToken = stakingTokens[_pid];
    uint256 _receivedAmount = _unsafePullToken(msg.sender, _stakingToken, _amountToDeposit);

    // Effects
    unchecked {
      user.fundedAmounts[msg.sender] += _receivedAmount;
      user.totalAmount = user.totalAmount + _receivedAmount;
      stakingReserves[_stakingToken] += _receivedAmount;
    }
    user.rewardDebt =
      user.rewardDebt +
      ((_receivedAmount * _poolInfo.accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256();

    // Interactions
    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      // rewarder callback to do accounting
      IRewarder(_rewarder).onDeposit(_pid, _for, user.totalAmount);
      unchecked {
        ++_i;
      }
    }

    emit LogDeposit(msg.sender, _for, _pid, _receivedAmount);
  }

  /// @notice Withdraw tokens from MiniFL.
  /// @param _from Withdraw from who?
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _amountToWithdraw Staking token amount to withdraw.
  function withdraw(
    address _from,
    uint256 _pid,
    uint256 _amountToWithdraw
  ) external nonReentrant {
    UserInfo storage user = userInfo[_pid][_from];
    PoolInfo memory _poolInfo = _updatePool(_pid);

    // if pool is debt pool, staker should be whitelisted
    if (_poolInfo.isDebtTokenPool && !stakeDebtTokenAllowance[_pid][msg.sender]) {
      revert MiniFL_Forbidden();
    }

    // caller couldn't withdraw more than their funded
    if (_amountToWithdraw > user.fundedAmounts[msg.sender]) {
      revert MiniFL_InsufficientFundedAmount();
    }

    address _stakingToken = stakingTokens[_pid];

    // Effects
    unchecked {
      user.fundedAmounts[msg.sender] -= _amountToWithdraw;

      // total amount & staking reserves always >= user.fundedAmounts[msg.sender]
      user.totalAmount -= _amountToWithdraw;
      stakingReserves[_stakingToken] -= _amountToWithdraw;
    }

    user.rewardDebt =
      user.rewardDebt -
      (((_amountToWithdraw * _poolInfo.accAlpacaPerShare) / ACC_ALPACA_PRECISION)).toInt256();

    // Interactions
    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      // rewarder callback to do accounting
      IRewarder(_rewarder).onWithdraw(_pid, _from, user.totalAmount);
      unchecked {
        ++_i;
      }
    }

    IERC20Upgradeable(_stakingToken).safeTransfer(msg.sender, _amountToWithdraw);

    emit LogWithdraw(msg.sender, _from, _pid, _amountToWithdraw);
  }

  /// @notice Harvest ALPACA rewards
  /// @param _pid The index of the pool. See `poolInfo`.
  function harvest(uint256 _pid) external nonReentrant {
    UserInfo storage user = userInfo[_pid][msg.sender];
    PoolInfo memory _poolInfo = _updatePool(_pid);

    int256 accumulatedAlpaca = ((user.totalAmount * _poolInfo.accAlpacaPerShare) / ACC_ALPACA_PRECISION).toInt256();
    uint256 _pendingAlpaca = (accumulatedAlpaca - user.rewardDebt).toUint256();

    // Effects
    user.rewardDebt = accumulatedAlpaca;

    // Interactions
    if (_pendingAlpaca != 0) {
      IERC20Upgradeable(ALPACA).safeTransfer(msg.sender, _pendingAlpaca);
    }

    uint256 _rewarderLength = rewarders[_pid].length;
    address _rewarder;
    for (uint256 _i; _i < _rewarderLength; ) {
      _rewarder = rewarders[_pid][_i];
      // rewarder callback to claim reward
      IRewarder(_rewarder).onHarvest(_pid, msg.sender);
      unchecked {
        ++_i;
      }
    }

    emit LogHarvest(msg.sender, _pid, _pendingAlpaca);
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

  /// @notice Get amount of total staking token at pid
  /// @param _pid pool id
  function getStakingReserves(uint256 _pid) external view returns (uint256 _reserveAmount) {
    _reserveAmount = stakingReserves[stakingTokens[_pid]];
  }

  /// @notice Get amount of staking token funded for a user at pid
  /// @param _funder funder address
  /// @param _for user address
  /// @param _pid pool id
  function getFundedAmount(
    address _funder,
    address _for,
    uint256 _pid
  ) external view returns (uint256 _stakingAmount) {
    _stakingAmount = userInfo[_pid][_for].fundedAmounts[_funder];
  }

  function _unsafePullToken(
    address _from,
    address _token,
    uint256 _amount
  ) internal returns (uint256 _receivedAmount) {
    uint256 _currentTokenBalance = IERC20Upgradeable(_token).balanceOf(address(this));
    IERC20Upgradeable(_token).safeTransferFrom(_from, address(this), _amount);
    _receivedAmount = IERC20Upgradeable(_token).balanceOf(address(this)) - _currentTokenBalance;
  }

  /// @notice Set whitelisted callers
  /// @param _callers The addresses of the callers.
  /// @param _allow Whether to allow or disallow callers.
  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i; _i < _length; ) {
      whitelistedCallers[_callers[_i]] = _allow;
      emit LogSetWhitelistedCallers(_callers[_i], _allow);

      unchecked {
        ++_i;
      }
    }
  }
}
