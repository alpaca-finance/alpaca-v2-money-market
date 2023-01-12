// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { AVShareToken } from "../AVShareToken.sol";

// interfaces
import { IAVAdminFacet } from "../interfaces/IAVAdminFacet.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

contract AVAdminFacet is IAVAdminFacet {
  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function openVault(
    address _lpToken,
    address _stableToken,
    address _assetToken,
    address _handler,
    uint8 _leverageLevel,
    uint16 _managementFeePerSec,
    address _stableTokenInterestModel,
    address _assetTokenInterestModel
  ) external onlyOwner returns (address _newShareToken) {
    // sanity call
    IAVHandler(_handler).totalLpBalance();
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    string memory _tokenSymbol = IERC20(_lpToken).symbol();
    uint8 _tokenDecimals = IERC20(_lpToken).decimals();
    // TODO: move string stuff to AVShareToken view function
    _newShareToken = address(
      new AVShareToken(
        string.concat("Automated Vault Share Token ", _tokenSymbol),
        string.concat("avShare", _tokenSymbol),
        _tokenDecimals
      )
    );

    // sanity check interestModels
    IInterestRateModel(_stableTokenInterestModel).getInterestRate(1, 1);
    IInterestRateModel(_assetTokenInterestModel).getInterestRate(1, 1);

    avDs.vaultConfigs[_newShareToken] = LibAV01.VaultConfig({
      shareToken: _newShareToken,
      lpToken: _lpToken,
      stableToken: _stableToken,
      assetToken: _assetToken,
      handler: _handler,
      leverageLevel: _leverageLevel,
      managementFeePerSec: _managementFeePerSec,
      stableTokenInterestModel: _stableTokenInterestModel,
      assetTokenInterestModel: _assetTokenInterestModel
    });

    // todo: register lpToken to tokenConfig

    emit LogOpenVault(msg.sender, _lpToken, _stableToken, _assetToken, _newShareToken);
  }

  function setTokenConfigs(TokenConfigInput[] calldata configs) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    uint256 length = configs.length;
    for (uint256 _i; _i < length; ) {
      TokenConfigInput calldata config = configs[_i];
      avDs.tokenConfigs[config.token] = LibAV01.TokenConfig({
        tier: config.tier,
        to18ConversionFactor: LibAV01.to18ConversionFactor(config.token)
      });
      unchecked {
        ++_i;
      }
    }
  }

  function setMoneyMarket(address _newMoneyMarket) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    avDs.moneyMarket = _newMoneyMarket;
  }

  function setOracle(address _oracle) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    avDs.oracle = _oracle;
  }

  function setTreasury(address _treasury) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    avDs.treasury = _treasury;
  }

  function setManagementFeePerSec(address _vaultToken, uint16 _newManagementFeePerSec) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    avDs.vaultConfigs[_vaultToken].managementFeePerSec = _newManagementFeePerSec;
  }

  function setInterestRateModels(
    address _vaultToken,
    address _newStableTokenInterestRateModel,
    address _newAssetTokenInterestRateModel
  ) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    // sanity check
    IInterestRateModel(_newStableTokenInterestRateModel).getInterestRate(1, 1);
    IInterestRateModel(_newAssetTokenInterestRateModel).getInterestRate(1, 1);

    avDs.vaultConfigs[_vaultToken].stableTokenInterestModel = _newStableTokenInterestRateModel;
    avDs.vaultConfigs[_vaultToken].assetTokenInterestModel = _newAssetTokenInterestRateModel;
  }

  /// @notice Whitelist/Blacklist the address allowed for rebalancing
  /// @param _rebalancers an array of rebalancers' address
  /// @param _isOk a flag to allow or disallow
  function setRebalancersOk(address[] calldata _rebalancers, bool _isOk) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    uint256 _length = _rebalancers.length;
    for (uint8 _i; _i < _length; ) {
      avDs.rebalancerOk[_rebalancers[_i]] = _isOk;
      emit LogSetRebalancerOk(_rebalancers[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  function setRepurchaseRewardBps(uint16 _newBps) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    if (_newBps > LibAV01.MAX_BPS) {
      revert AVAdminFacet_InvalidParams();
    }
    avDs.repurchaseRewardBps = _newBps;
    emit LogSetRepurchaseRewardBps(_newBps);
  }
}
