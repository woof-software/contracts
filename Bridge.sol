// SPDX-License-Identifier: UNLICENSED

/*
    This bridge contract runs on Arbitrum, operating alongside the Hyperliquid L1.
    The only asset for now is USDC, though the logic extends to any other ERC20 token on Arbitrum.
    The L1 runs tendermint consensus, with validator set updates happening at the end of each epoch.
    Epoch duration TBD, but likely somewhere between 1 day and 1 week

    Validator set updates:
      The current validators sign a hash of the new validator set and powers on the L1.
      This contract checks those signatures, and updates the hash of the current validator set.
      The current validators' stake is still locked for at least one more epoch (unbonding period),
      and the new validators will slash the old ones' stake if they do not properly generate the
      validator set update signatures.

    Withdrawals:
      The validators sign withdrawals on the L1, which the user sends to this contract in withdraw().
      This contract checks the signatures, and then sends the USDC to the user.

    Deposits:
      The validators on the L1 listen for and sign DepositEvent events emitted by this contract,
      crediting the L1 with the equivalent USDC. No additional work needs to be done on this contract.

    Note that on epoch changes, the L1 will ensure that new signatures are generated for unclaimed withdrawals
    for any validators that have changed.
*/

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Signature.sol";

struct ValsetArgs {
  uint256 epoch;
  address[] validators;
  uint256[] powers;
}

struct DepositEvent {
  address user;
  uint256 usdc;
  uint256 timestamp;
}

struct WithdrawEvent {
  address user;
  uint256 usdc;
  ValsetArgs valsetArgs;
  uint256 timestamp;
}

contract Bridge is Ownable, Pausable, ReentrancyGuard {
  ERC20 usdcToken;

  bytes32 public valsetCheckpoint;
  uint256 public epoch;
  uint256 public powerThreshold;
  uint256 public totalValidatorPower;

  mapping(bytes32 => bool) processedWithdrawals;

  event Deposit(DepositEvent e);
  event Withdraw(WithdrawEvent e);

  event ValsetUpdatedEvent(uint256 indexed epoch, address[] validators, uint256[] powers);

  constructor(
    uint256 _totalValidatorPower,
    uint256 _powerThreshold,
    address[] memory validators,
    uint256[] memory powers,
    address usdcAddress
  ) {
    require(validators.length == powers.length, "Malformed current validator set");

    powerThreshold = _powerThreshold;
    totalValidatorPower = _totalValidatorPower;
    require(
      powerThreshold >= (2 * totalValidatorPower) / 3,
      "Power threshold should be at least 2/3 of the total validator power."
    );
    checkNewValidatorPowers(powers);

    ValsetArgs memory valset;
    valset = ValsetArgs(0, validators, powers);
    bytes32 newCheckpoint = makeCheckpoint(valset);
    valsetCheckpoint = newCheckpoint;
    usdcToken = ERC20(usdcAddress);

    emit ValsetUpdatedEvent(0, validators, powers);
  }

  function makeCheckpoint(ValsetArgs memory valsetArgs) private pure returns (bytes32) {
    bytes32 checkpoint = keccak256(
      abi.encode(valsetArgs.validators, valsetArgs.powers, valsetArgs.epoch)
    );
    return checkpoint;
  }

  function deposit(uint256 usdc) external whenNotPaused nonReentrant {
    address user = msg.sender;
    usdcToken.transferFrom(user, address(this), usdc);
    emit Deposit(DepositEvent({ user: user, usdc: usdc, timestamp: blockMillis() }));
  }

  function withdraw(
    uint256 usdc,
    uint256 nonce,
    ValsetArgs memory valsetArgs,
    Signature[] memory signatures
  ) external nonReentrant whenNotPaused {
    require(
      makeCheckpoint(valsetArgs) == valsetCheckpoint,
      "Supplied current validators and powers do not match the current checkpoint."
    );

    // NOTE: this is a temporary workaround because EIP-191 signatures do not match between rust client and solidity.
    // For now we do not care about the overhead with EIP-712 because Arbitrum gas is basically free.
    Agent memory agent = Agent("a", keccak256(abi.encode(msg.sender, usdc, nonce)));
    bytes32 message = hash(agent);

    require(!processedWithdrawals[message], "Already withdrawn.");
    processedWithdrawals[message] = true;

    checkValidatorSignatures(message, valsetArgs, signatures);
    usdcToken.transfer(msg.sender, usdc);

    emit Withdraw(
      WithdrawEvent({
        user: msg.sender,
        usdc: usdc,
        valsetArgs: valsetArgs,
        timestamp: blockMillis()
      })
    );
  }

  function checkValidatorSignatures(
    bytes32 message,
    ValsetArgs memory valsetArgs,
    Signature[] memory signatures
  ) private view {
    uint256 cumulativePower = 0;
    for (uint256 i = 0; i < valsetArgs.validators.length; i++) {
      require(
        recoverSigner(message, signatures[i]) == valsetArgs.validators[i],
        "Validator signature does not match."
      );
      cumulativePower = cumulativePower + valsetArgs.powers[i];
      if (cumulativePower > powerThreshold) {
        break;
      }
    }
    require(
      cumulativePower > powerThreshold,
      "Submitted validator set signatures do not have enough power."
    );
  }

  function updateValset(
    ValsetArgs calldata newValset,
    ValsetArgs calldata currentValset,
    Signature[] calldata signatures
  ) external whenNotPaused {
    {
      require(
        currentValset.epoch == epoch,
        "Current valset epoch supplied doesn't match the current epoch"
      );
      require(
        newValset.epoch > currentValset.epoch,
        "New valset epoch must be greater than the current epoch"
      );

      require(
        newValset.validators.length == newValset.powers.length,
        "Malformed new validator set"
      );

      require(
        currentValset.validators.length == signatures.length,
        "Malformed current validator set"
      );

      require(
        makeCheckpoint(currentValset) == valsetCheckpoint,
        "Supplied current validators and powers do not match checkpoint."
      );
    }

    checkNewValidatorPowers(newValset.powers);
    bytes32 newCheckpoint = makeCheckpoint(newValset);
    checkValidatorSignatures(newCheckpoint, currentValset, signatures);
    valsetCheckpoint = newCheckpoint;
    epoch = newValset.epoch;

    emit ValsetUpdatedEvent(newValset.epoch, newValset.validators, newValset.powers);
  }

  function checkNewValidatorPowers(uint256[] memory powers) private view {
    uint256 cumulativePower = 0;
    for (uint256 i = 0; i < powers.length; i++) {
      cumulativePower = cumulativePower + powers[i];
      if (cumulativePower >= totalValidatorPower) {
        break;
      }
    }

    require(
      cumulativePower == totalValidatorPower,
      "Submitted validator powers do not equal totalValidatorPower."
    );
  }

  function blockMillis() private view returns (uint256) {
    return 1000 * block.timestamp;
  }

  function changePowerThreshold(uint256 _powerThreshold) external onlyOwner whenPaused {
    powerThreshold = _powerThreshold;
  }

  function emergencyPause() external onlyOwner {
    _pause();
  }

  function emergencyUnpause() external onlyOwner {
    _unpause();
  }
}
